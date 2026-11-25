/**
 * TAG-56 against the local emulators (demo- project only):
 *  - the migration script is a dry run by default and refuses --apply outside
 *    a demo- emulator project;
 *  - --apply copies a Unilever-sized campaign into events/{id}/content and is
 *    idempotent;
 *  - dryRunCampaignEligibility reads the products from the chunks once the
 *    legacy fields are gone, and fails closed when a chunk is missing.
 *
 * Run from functions/: npm run test:emulator
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const admin = require("../admin_sdk");

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST && PROJECT.startsWith("demo-");
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099"}`;
const SCRIPT = path.join(__dirname, "..", "scripts", "migrate_campaign_content.js");
const DAY = 24 * 3600 * 1000;
const EVENT = "E_cc_unilever";
let db;

const products = [...Array.from({ length: 3636 }, (_, i) => `منتج يونيلفر رقم ${i} - صابون لوكس ${i % 7} جم`), "جلاكسي"];
const prompt = "أنت مساعد ذكي لفحص فواتير يونيلفر. ".repeat(7100);
const lines = (name) => [{ name, price: 200, quantity: 1, isTargetCompany: true, barcode: "" }];

function runScript(args) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { env: process.env, encoding: "utf8" });
}

async function idToken() {
  const email = "cc-admin@example.com";
  const user = await admin.auth().createUser({ email, password: "content-pass-1" });
  await admin.auth().setCustomUserClaims(user.uid, { role: "admin" });
  const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password: "content-pass-1", returnSecureToken: true }),
  });
  return (await res.json()).idToken;
}

const dryRun = async (token, receiptId) => {
  const res = await fetch(`${FUNCTIONS}/dryRunCampaignEligibility`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}`, "x-firebase-appcheck": "local.emulator.token" },
    body: JSON.stringify({ data: { eventId: EVENT, receiptId } }),
  });
  return { status: res.status, body: await res.json() };
};

test.before(async () => {
  if (!RUN) return;
  admin.initializeApp({ projectId: PROJECT });
  db = admin.firestore();
  const now = Date.now();
  await db.collection("events").doc(EVENT).set({
    eventName: "يونيلفر (نسخة تجربة)", companySlug: "cc", isActive: true,
    startDate: admin.firestore.Timestamp.fromMillis(now - 10 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(now + 10 * DAY),
    minimumSpend: 0, requiredProducts: products, customPrompt: prompt,
    allocatedPrizes: [{ giftId: "g1", name: "قسيمة", giftType: "voucher", unitValue: 50, branchId: "b1", remainingQuantity: 3 }],
  });
  for (const [id, name] of [["R_cc_match", "جلاكسي"], ["R_cc_miss", "بيبسي كولا"]]) {
    await db.collection("receipts_transactions").doc(id).set({
      campaignId: EVENT, submittedByUid: "rep1", receipt_date: "", chances_earned: 1, game_played: false,
      timestamp: admin.firestore.Timestamp.now(), extracted_products: lines(name),
    });
  }
});

test("migration: dry run writes nothing; --apply refuses a non-demo project", { skip: !RUN }, async () => {
  const before = (await db.collection("events").doc(EVENT).get()).updateTime;
  const out = JSON.parse(execFileSync(process.execPath, [SCRIPT, "--project", PROJECT, "--event", EVENT], { env: process.env, encoding: "utf8" }));
  assert.equal(out.summary.mode, "DRY RUN (no writes)");
  assert.equal(out.campaigns[0].action, "migrate");
  assert.equal(out.campaigns[0].products, products.length);
  assert.ok(out.campaigns[0].docBytes > 400 * 1024);
  assert.equal((await db.collection("events").doc(EVENT).collection("content").get()).size, 0);
  assert.ok((await db.collection("events").doc(EVENT).get()).updateTime.isEqual(before));

  const refused = runScript(["--project", "tashil-gift", "--event", EVENT, "--apply"]);
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /only on the Firestore emulator with a demo- project/);
  assert.equal((await db.collection("events").doc(EVENT).collection("content").get()).size, 0);
});

test("migration: --apply copies the content, keeps legacy fields, and is idempotent", { skip: !RUN }, async () => {
  const applied = JSON.parse(execFileSync(process.execPath, [SCRIPT, "--project", PROJECT, "--event", EVENT, "--apply"], { env: process.env, encoding: "utf8" }));
  assert.equal(applied.summary.toMigrate, 1);
  const ref = db.collection("events").doc(EVENT);
  const snap = await ref.get();
  const data = snap.data();
  assert.equal(data.contentVersion, 1);
  assert.equal(data.contentRevision, 1);
  assert.equal(data.requiredProductsCount, products.length);
  assert.equal(data.requiredProducts.length, products.length, "legacy fields stay until cleanup");
  const content = await ref.collection("content").get();
  assert.equal(content.size, data.contentProductsChunks + data.contentPromptChunks);

  const again = JSON.parse(execFileSync(process.execPath, [SCRIPT, "--project", PROJECT, "--event", EVENT, "--apply"], { env: process.env, encoding: "utf8" }));
  assert.equal(again.campaigns[0].action, "skip");
  assert.equal(again.campaigns[0].reason, "already migrated");
  assert.ok((await ref.get()).updateTime.isEqual(snap.updateTime));
});

test("server eligibility reads products from the chunks and fails closed", { skip: !RUN }, async () => {
  const ref = db.collection("events").doc(EVENT);
  // What a large edit leaves behind: pointer + chunks, no legacy fields.
  await ref.update({ requiredProducts: admin.firestore.FieldValue.delete(), customPrompt: admin.firestore.FieldValue.delete() });
  const token = await idToken();
  const match = await dryRun(token, "R_cc_match");
  assert.equal(match.status, 200, JSON.stringify(match.body));
  assert.equal(match.body.result.ok, true);
  const miss = await dryRun(token, "R_cc_miss");
  assert.equal(miss.status, 200, JSON.stringify(miss.body));
  assert.equal(miss.body.result.ok, false, "products loaded from the chunks must still restrict eligibility");

  await ref.collection("content").doc("products_1").delete();
  const broken = await dryRun(token, "R_cc_match");
  assert.ok(broken.body.error, "an incomplete product list must not widen eligibility");
});
