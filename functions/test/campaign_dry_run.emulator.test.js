/**
 * C-05 dryRunCampaignEligibility against the local emulators (demo- project
 * only). An admin gets the claim verdict, a rep is refused, and the database
 * is byte-for-byte the same afterwards (no stock, claim or receipt writes).
 *
 * Run from functions/: npm run test:emulator
 * The App Check skip is for the emulator only; never set it on a deployed function.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../admin_sdk");

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST && PROJECT.startsWith("demo-");
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099"}`;
const DAY = 24 * 3600 * 1000;
let db;

const lines = (price) => [{ name: "جلاكسي شوكولاتة", price, quantity: 1, isTargetCompany: true, barcode: "6221134031478" }];

// Other emulator test files run at the same time, so the snapshot covers every
// document tied to this fixture (in any root collection, with subcollections).
const mine = (id, d) => /dry/i.test(id) || d.campaignId === "E_dry" || d.eventId === "E_dry" || d.companySlug === "dry";
async function dumpAll() {
  const out = {};
  for (const col of await db.listCollections()) {
    const snap = await col.get();
    for (const d of snap.docs) {
      if (!mine(d.id, d.data())) continue;
      const subs = {};
      for (const sub of await d.ref.listCollections()) {
        subs[sub.id] = (await sub.get()).docs.map((x) => [x.id, x.data()]);
      }
      out[`${col.id}/${d.id}`] = { data: d.data(), subs };
    }
  }
  return JSON.stringify(out);
}

async function tokenFor(email, claims) {
  const user = await admin.auth().createUser({ email, password: "dry-run-pass-1" });
  if (claims) await admin.auth().setCustomUserClaims(user.uid, claims);
  const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password: "dry-run-pass-1", returnSecureToken: true }),
  });
  const body = await res.json();
  assert.ok(body.idToken, JSON.stringify(body));
  return body.idToken;
}

async function anonymousToken() {
  const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  return (await res.json()).idToken;
}

const call = async (idToken, data) => {
  const res = await fetch(`${FUNCTIONS}/dryRunCampaignEligibility`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${idToken}`, "x-firebase-appcheck": "local.emulator.token" },
    body: JSON.stringify({ data }),
  });
  return { status: res.status, body: await res.json() };
};

test.before(async () => {
  if (!RUN) return;
  admin.initializeApp({ projectId: PROJECT });
  db = admin.firestore();
  const now = Date.now();
  await db.collection("events").doc("E_dry").set({
    eventName: "Dry fixture", companySlug: "dry", isActive: true,
    startDate: admin.firestore.Timestamp.fromMillis(now - 10 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(now + 10 * DAY),
    minimumSpend: 150, requiredProducts: ["جلاكسي"],
    allocatedPrizes: [{ giftId: "g1", name: "قسيمة", giftType: "voucher", unitValue: 50, branchId: "b1", remainingQuantity: 3 }],
  });
  await db.collection("receipts_transactions").doc("R_dry").set({
    campaignId: "E_dry", submittedByUid: "rep1", receipt_date: "", chances_earned: 1, game_played: false,
    timestamp: admin.firestore.Timestamp.now(), extracted_products: lines(200),
  });
});

test("admin dry run returns the verdict and writes nothing", { skip: !RUN }, async () => {
  const idToken = await tokenFor("dry-admin@example.com", { role: "admin" });
  const before = await dumpAll();
  assert.ok(before.includes("events/E_dry") && before.includes("receipts_transactions/R_dry"));

  const stored = await call(idToken, { eventId: "E_dry", receiptId: "R_dry" });
  assert.equal(stored.status, 200, JSON.stringify(stored.body));
  assert.equal(stored.body.result.ok, true);
  assert.equal(stored.body.result.dryRun, true);

  const now = Date.now();
  const draft = {
    eventName: "Draft", companySlug: "dry", isActive: false, startDate: now - DAY, endDate: now + DAY,
    minimumSpend: 150, requiredProducts: ["جلاكسي"],
  };
  const low = await call(idToken, { campaign: draft, receipt: { receipt_date: "", extracted_products: lines(100) } });
  assert.equal(low.status, 200, JSON.stringify(low.body));
  assert.equal(low.body.result.ok, false);
  assert.equal(low.body.result.code, "min_spend_not_met");
  assert.equal(low.body.result.campaignActive, false);

  assert.equal(await dumpAll(), before);
});

test("an anonymous rep is refused and nothing is written", { skip: !RUN }, async () => {
  const before = await dumpAll();
  const res = await call(await anonymousToken(), { eventId: "E_dry", receiptId: "R_dry" });
  assert.equal(res.body.error.status, "PERMISSION_DENIED");
  assert.equal(await dumpAll(), before);
});
