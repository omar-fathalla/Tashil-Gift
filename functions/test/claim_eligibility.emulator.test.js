/**
 * Server-side claim eligibility against the local emulators (demo-tashil only).
 * Proves a rejected claim leaves stock, the receipt and the shard counters
 * exactly as they were, and that an eligible claim still decrements once.
 *
 * Run from functions/: npm run test:emulator
 * The App Check skip below is for the emulator only; never set it on a deployed function.
 */
const test = require("node:test");
const assert = require("node:assert");
const admin = require("../admin_sdk");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && PROJECT.startsWith("demo-");
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099"}`;

const DAY = 24 * 3600 * 1000;
const BARCODE = "6221134031478";
let db;

const lines = (price, extra = {}) => [Object.assign(
  { name: "جلاكسي شوكولاتة", price, quantity: 1, isTargetCompany: true, barcode: BARCODE }, extra)];

function campaign(extra = {}) {
  const now = Date.now();
  return Object.assign({
    eventName: "Eligibility fixture", companySlug: "elig", isActive: true,
    startDate: admin.firestore.Timestamp.fromMillis(now - 10 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(now + 10 * DAY),
    balanceMode: "campaign_only", allowMultipleChances: false, maxChancesPerReceipt: 1,
    promotionalRules: [{
      id: "t150", conditionType: "by_spend", minSpend: 150, selectedBarcodes: [BARCODE],
      linkedGifts: [{ giftId: "g150", giftName: "قسيمة 150", quantity: 1 }],
    }],
    allocatedPrizes: [{ giftId: "g150", name: "قسيمة 150", giftType: "voucher", unitValue: 150, branchId: "b1", remainingQuantity: 5 }],
  }, extra);
}

async function seed(eventId, event, receiptId, receipt) {
  await db.collection("events").doc(eventId).set(event);
  await db.collection("receipts_transactions").doc(receiptId).set(receipt);
}

async function snapshotOf(eventId, receiptId) {
  const event = await db.collection("events").doc(eventId).get();
  const receipt = await db.collection("receipts_transactions").doc(receiptId).get();
  const shards = await db.collection("events").doc(eventId).collection("sharded_counters").get();
  return JSON.stringify({ event: event.data(), receipt: receipt.data(), shards: shards.size });
}

const claim = (eventId, receiptId, uid) => applyCampaignPrizeClaim(db, {
  eventId, receiptId, actor: { anonymous: true, uid },
  decrements: [{ prizeIdentifier: "g150", branchId: "b1", count: 1 }],
  receiptPatch: { game_played: true },
});

test.before(() => {
  if (!RUN) return;
  admin.initializeApp({ projectId: PROJECT });
  db = admin.firestore();
});

const REJECTIONS = [
  ["campaign_inactive", () => campaign({ isActive: false }), () => lines(200)],
  ["campaign_ended", () => campaign({
    startDate: admin.firestore.Timestamp.fromMillis(Date.now() - 30 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(Date.now() - 5 * DAY),
  }), () => lines(200)],
  ["min_spend_not_met", () => campaign(), () => lines(100).concat([{ name: "ميلكي واي", price: 900, quantity: 1, isTargetCompany: true, barcode: "5000000000001" }])],
  ["required_products_missing", () => campaign(), () => [{ name: "ميلكي واي", price: 900, quantity: 1, isTargetCompany: true, barcode: "5000000000001" }]],
];

for (const [reason, makeEvent, makeLines] of REJECTIONS) {
  test(`${reason}: claim is rejected and nothing is written`, { skip: !RUN }, async () => {
    const eventId = `E_${reason}`;
    const receiptId = `R_${reason}`;
    await seed(eventId, makeEvent(), receiptId, {
      campaignId: eventId, submittedByUid: "rep1", receipt_date: "", extracted_products: makeLines(),
      timestamp: admin.firestore.Timestamp.now(), chances_earned: 1, branch_id: "b1",
    });
    const before = await snapshotOf(eventId, receiptId);
    await assert.rejects(claim(eventId, receiptId, "rep1"), (err) => {
      assert.strictEqual(err.code, "failed-precondition");
      assert.strictEqual(err.details.reason, reason);
      return true;
    });
    assert.strictEqual(await snapshotOf(eventId, receiptId), before);
    const stored = (await db.collection("events").doc(eventId).get()).data();
    assert.strictEqual(stored.allocatedPrizes[0].remainingQuantity, 5);
  });
}

test("eligible claim decrements stock exactly once", { skip: !RUN }, async () => {
  await seed("E_ok", campaign(), "R_ok", {
    campaignId: "E_ok", submittedByUid: "rep1", extracted_products: lines(200),
    timestamp: admin.firestore.Timestamp.now(), chances_earned: 1, branch_id: "b1",
  });
  const out = await claim("E_ok", "R_ok", "rep1");
  assert.strictEqual(out.ok, true);
  const stored = (await db.collection("events").doc("E_ok").get()).data();
  assert.strictEqual(stored.allocatedPrizes[0].remainingQuantity, 4);
});

async function anonymousToken() {
  const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await res.json();
  assert.ok(body.idToken, JSON.stringify(body));
  return { idToken: body.idToken, uid: body.localId };
}

test("decrementCampaignPrize callable: ended campaign is rejected with a reason code and no writes", { skip: !RUN || !process.env.FIREBASE_AUTH_EMULATOR_HOST }, async () => {
  const { idToken, uid } = await anonymousToken();
  await seed("E_callable", campaign({
    startDate: admin.firestore.Timestamp.fromMillis(Date.now() - 30 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(Date.now() - 5 * DAY),
  }), "R_callable", {
    campaignId: "E_callable", submittedByUid: uid, extracted_products: lines(200),
    timestamp: admin.firestore.Timestamp.now(), chances_earned: 1, branch_id: "b1",
  });
  const before = await snapshotOf("E_callable", "R_callable");
  const res = await fetch(`${FUNCTIONS}/decrementCampaignPrize`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${idToken}`, "x-firebase-appcheck": "local.emulator.token" },
    body: JSON.stringify({ data: {
      eventId: "E_callable", receiptId: "R_callable", receiptPatch: { game_played: true },
      decrements: [{ prizeIdentifier: "g150", branchId: "b1", count: 1 }],
    } }),
  });
  const body = await res.json();
  assert.strictEqual(res.status, 400, JSON.stringify(body));
  assert.strictEqual(body.error.status, "FAILED_PRECONDITION");
  assert.strictEqual(body.error.details.reason, "campaign_ended");
  assert.match(body.error.message, /انتهت الحملة/);
  assert.strictEqual(await snapshotOf("E_callable", "R_callable"), before);
});

test("autoCloseExpiredCampaigns on real Firestore: closes the ended campaign, keeps in-date and stock-depleted ones", { skip: !RUN }, async () => {
  const { autoCloseExpiredCampaigns } = require("../auto_close_campaigns");
  const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
  const now = Date.now();
  await db.collection("events").doc("AC_ended").set(campaign({ endDate: ts(now - 3 * DAY) }));
  await db.collection("events").doc("AC_current").set(campaign({ endDate: ts(now + 3 * DAY) }));
  await db.collection("events").doc("AC_depleted").set(campaign({
    endDate: ts(now + 3 * DAY),
    allocatedPrizes: [{ giftId: "g150", name: "قسيمة 150", giftType: "voucher", unitValue: 150, remainingQuantity: 0 }],
  }));
  const logs = [];
  const first = await autoCloseExpiredCampaigns(db, { log: (line) => logs.push(line) });
  assert.ok(first.closed.some((c) => c.eventId === "AC_ended"));
  assert.ok(!first.closed.some((c) => c.eventId === "AC_current" || c.eventId === "AC_depleted"));
  assert.ok(logs.some((l) => l.action === "closed" && l.eventId === "AC_ended"));

  const ended = (await db.collection("events").doc("AC_ended").get()).data();
  assert.strictEqual(ended.isActive, false);
  assert.strictEqual(ended.updatedBy, "system:auto-close");
  assert.ok(ended.updatedAt instanceof admin.firestore.Timestamp);
  for (const id of ["AC_current", "AC_depleted"]) {
    const kept = (await db.collection("events").doc(id).get()).data();
    assert.strictEqual(kept.isActive, true, id);
    assert.strictEqual(kept.updatedBy, undefined, id);
  }

  const second = await autoCloseExpiredCampaigns(db, { log: () => {} });
  assert.ok(!second.closed.some((c) => c.eventId === "AC_ended"));
});
