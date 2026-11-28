/**
 * TAG-62 against the Firestore emulator (demo- project only): a large
 * campaign whose products live in events/{id}/content is still checked by the
 * claim transaction and the dry run, missing content fails closed, and the
 * migration script (dry-run, then --apply) moves a Unilever-sized campaign.
 *
 * Run from functions/: npm run test:emulator
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const admin = require("../admin_sdk");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;
const { dryRunCampaignEligibilityHandler } = require("../campaign_dry_run");
const { planContentWrite, withCampaignContent } = require("../campaign_content");

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && PROJECT.startsWith("demo-");
const DAY = 24 * 3600 * 1000;
const BARCODE = "6221134099999";
let db;

const manyProducts = (n) => Array.from({ length: n }, (_, i) => `صنف تجريبي رقم ${i} - عبوة 250 جم - منظف متعدد الاستخدامات برائحة الليمون`);
const PRODUCTS = [...manyProducts(9999), "دوف شامبو 400 مل"];
const PROMPT = "تعليمات فحص ".repeat(12000);

function campaign() {
  const now = Date.now();
  return {
    eventName: "TAG-62 large", companySlug: "tag62", isActive: true,
    startDate: admin.firestore.Timestamp.fromMillis(now - 10 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(now + 10 * DAY),
    balanceMode: "campaign_only", allowMultipleChances: false, maxChancesPerReceipt: 1, minimumSpend: 100,
    promotionalRules: [],
    allocatedPrizes: [{ giftId: "g1", name: "قسيمة", giftType: "voucher", unitValue: 50, branchId: "b1", remainingQuantity: 5 }],
  };
}

/** Writes a campaign the way CampaignContentRepository.createWithContent does. */
async function seedExternal(eventId, { withContent = true } = {}) {
  const write = planContentWrite({ products: PRODUCTS, prompt: PROMPT, version: 1, ts: admin.firestore.Timestamp.now() });
  assert.equal(write.inline, false);
  const batch = db.batch();
  batch.set(db.collection("events").doc(eventId), Object.assign(campaign(), write.eventFields));
  if (withContent) {
    for (const [id, doc] of Object.entries(write.docs)) batch.set(db.collection("events").doc(eventId).collection("content").doc(id), doc);
  }
  await batch.commit();
}

const receipt = (eventId, name, price) => ({
  campaignId: eventId, submittedByUid: "rep1", receipt_date: "", chances_earned: 1, branch_id: "b1",
  timestamp: admin.firestore.Timestamp.now(), extracted_products: [{ name, price, quantity: 1, isTargetCompany: true, barcode: BARCODE }],
});

const claim = (eventId, receiptId) => applyCampaignPrizeClaim(db, {
  eventId, receiptId, actor: { anonymous: true, uid: "rep1" },
  decrements: [{ prizeIdentifier: "g1", branchId: "b1", count: 1 }],
  receiptPatch: { game_played: true },
});

const remaining = async (eventId) => (await db.collection("events").doc(eventId).get()).data().allocatedPrizes[0].remainingQuantity;

test.before(() => {
  if (!RUN) return;
  admin.initializeApp({ projectId: PROJECT });
  db = admin.firestore();
});

test("claim on an external-content campaign: matching product passes, other product is rejected", { skip: !RUN }, async () => {
  await seedExternal("E_t62_claim");
  const doc = (await db.collection("events").doc("E_t62_claim").get()).data();
  assert.equal("requiredProducts" in doc, false);
  assert.ok(Buffer.byteLength(JSON.stringify(doc)) < 10 * 1024);

  await db.collection("receipts_transactions").doc("R_t62_other").set(receipt("E_t62_claim", "شيبسي عائلي", 200));
  await assert.rejects(claim("E_t62_claim", "R_t62_other"), (err) => {
    assert.equal(err.code, "failed-precondition");
    assert.equal(err.details.reason, "required_products_missing");
    return true;
  });
  assert.equal(await remaining("E_t62_claim"), 5);

  await db.collection("receipts_transactions").doc("R_t62_ok").set(receipt("E_t62_claim", "دوف شامبو 400 مل", 200));
  assert.equal((await claim("E_t62_claim", "R_t62_ok")).ok, true);
  assert.equal(await remaining("E_t62_claim"), 4);
});

test("claim fails closed when the content docs are missing", { skip: !RUN }, async () => {
  await seedExternal("E_t62_missing", { withContent: false });
  await db.collection("receipts_transactions").doc("R_t62_missing").set(receipt("E_t62_missing", "دوف شامبو 400 مل", 200));
  await assert.rejects(claim("E_t62_missing", "R_t62_missing"), (err) => {
    assert.equal(err.details.reason, "campaign_content_unavailable");
    return true;
  });
  assert.equal(await remaining("E_t62_missing"), 5);
});

test("dry run reads stored content by eventId and by contentEventId", { skip: !RUN }, async () => {
  await seedExternal("E_t62_trial");
  const auth = { token: { role: "admin", firebase: { sign_in_provider: "password" } } };
  const lines = (name) => ({ receipt_date: "", extracted_products: [{ name, price: 200, quantity: 1, isTargetCompany: true }] });
  const byId = await dryRunCampaignEligibilityHandler(db, { auth, data: { eventId: "E_t62_trial", receipt: lines("شيبسي") } });
  assert.equal(byId.ok, false);
  assert.equal(byId.code, "required_products_missing");
  const draft = Object.assign(campaign(), { startDate: Date.now() - DAY, endDate: Date.now() + DAY });
  const byContent = await dryRunCampaignEligibilityHandler(db, { auth, data: { campaign: draft, contentEventId: "E_t62_trial", receipt: lines("دوف شامبو 400 مل") } });
  assert.equal(byContent.ok, true);
});

test("migration script: dry-run writes nothing, --apply externalizes and is idempotent", { skip: !RUN }, async () => {
  const big = Object.assign(campaign(), { requiredProducts: manyProducts(3636), customPrompt: "ب".repeat(145000) });
  await db.collection("events").doc("E_t62_migrate").set(big);
  const script = path.join(__dirname, "..", "scripts", "migrate_campaign_content.js");
  const run = (...extra) => JSON.parse(execFileSync("node", [script, "--project", PROJECT, "--event", "E_t62_migrate", ...extra], { env: process.env }).toString());

  const dry = run();
  assert.equal(dry.mode, "dry-run");
  assert.equal(dry.report[0].action, "externalize");
  assert.ok(dry.report[0].docBytesBefore > 256 * 1024);
  assert.deepEqual((await db.collection("events").doc("E_t62_migrate").get()).data(), big);

  const applied = run("--apply");
  assert.equal(applied.report[0].applied, true);
  const after = (await db.collection("events").doc("E_t62_migrate").get()).data();
  assert.equal("requiredProducts" in after, false);
  assert.equal(after.hasExternalContent, true);
  assert.equal(after.requiredProductsCount, 3636);
  const loaded = await withCampaignContent(db, "E_t62_migrate", after);
  assert.deepEqual(loaded.requiredProducts, big.requiredProducts);
  assert.equal(loaded.customPrompt, big.customPrompt);
  const backup = (await db.collection("events").doc("E_t62_migrate").collection("content").doc("legacy_backup").get()).data();
  assert.deepEqual(backup.requiredProducts, big.requiredProducts);

  assert.equal(run("--apply").report[0].action, "skip");
});

test("migration script refuses --apply on a non-demo project without approval", { skip: !RUN }, () => {
  const script = path.join(__dirname, "..", "scripts", "migrate_campaign_content.js");
  assert.throws(() => execFileSync("node", [script, "--project", "tashil-gift", "--apply"], { env: process.env, stdio: "pipe" }));
});
