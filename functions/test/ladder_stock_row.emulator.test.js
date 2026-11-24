/**
 * TG-2 (Cadbury false zero stock) against the local Firestore emulator
 * (demo- project only). A consuming-ladder claim must draw from the row with
 * the tier option's giftId in the receipt branch, and an option bound to a
 * different voucher's id fails as "campaign misconfigured" with no writes.
 *
 * Run from functions/: npm run test:emulator
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("../admin_sdk");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && PROJECT.startsWith("demo-");
const DAY = 24 * 3600 * 1000;
const BARCODE = "6220000000011";
const V150 = "gift-voucher-150";
const V25 = "gift-voucher-25";
let db;

const row = (giftId, unit, branchId, remaining) => ({
  giftId, name: `فواتشر ${unit}`, giftType: "voucher", unitValue: unit,
  branchId, branchName: `فرع ${branchId}`, allocatedQuantity: 100, remainingQuantity: remaining,
});

function campaign(optionGiftId) {
  const now = Date.now();
  return {
    eventName: "Cadbury ladder fixture", companySlug: "cadbury-fixture", isActive: true,
    startDate: admin.firestore.Timestamp.fromMillis(now - 10 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(now + 10 * DAY),
    spendLadderMode: "consuming", allowMultipleChances: true, maxChancesPerReceipt: 3,
    balanceMode: "campaign_only",
    promotionalRules: [{
      id: "t500", conditionType: "by_spend", minSpend: 500, selectedBarcodes: [BARCODE],
      requiredBrands: ["كادبري"], triggerProduct: "كادبري",
      rewardOptions: [{ kind: "voucher", giftId: optionGiftId, giftType: "voucher", voucherAmount: 150, label: "فواتشر 150" }],
    }],
    allocatedPrizes: [row(V150, 150, "b1", 51), row(V25, 25, "b1", 0), row(V150, 150, "b2", 7), row(V25, 25, "b2", 0)],
  };
}

async function seed(id, optionGiftId) {
  await db.collection("events").doc(`E_${id}`).set(campaign(optionGiftId));
  await db.collection("receipts_transactions").doc(`R_${id}`).set({
    campaignId: `E_${id}`, submittedByUid: "rep1", branch_id: "b1", chances_earned: 1,
    timestamp: admin.firestore.Timestamp.now(), game_played: false,
    extracted_products: [{ name: "كادبري", price: 520, quantity: 1, barcode: BARCODE, isTargetCompany: true }],
  });
}

const stocks = async (id) => (await db.collection("events").doc(`E_${id}`).get()).data()
  .allocatedPrizes.map((p) => p.remainingQuantity);
const claim = (id, giftId) => applyCampaignPrizeClaim(db, {
  eventId: `E_${id}`, receiptId: `R_${id}`, actor: { anonymous: true, uid: "rep1" },
  decrements: [{ prizeIdentifier: giftId, branchId: "b1", count: 1, unitValue: 150, isVoucher: true, gameType: "chooseGift", claimSlot: 0 }],
  receiptPatch: { game_played: true },
});

test.before(() => {
  if (!RUN) return;
  admin.initializeApp({ projectId: PROJECT });
  db = admin.firestore();
});

test("correct option id decrements the voucher-150 row of the receipt branch", { skip: !RUN }, async () => {
  await seed("ok", V150);
  const out = await claim("ok", V150);
  assert.equal(out.ok, true);
  assert.deepEqual(await stocks("ok"), [50, 0, 7, 0]);
  const r = (await db.collection("receipts_transactions").doc("R_ok").get()).data();
  assert.equal(r.claimed_gifts[0].giftId, V150);
});

test("option bound to the voucher-25 id fails as misconfigured and writes nothing", { skip: !RUN }, async () => {
  await seed("bad", V25);
  await assert.rejects(claim("bad", V25), (err) => {
    assert.equal(err.code, "failed-precondition");
    assert.equal(err.details.reason, "campaign_misconfigured");
    assert.match(err.message, /فرع b1/);
    return true;
  });
  assert.deepEqual(await stocks("bad"), [51, 0, 7, 0]);
  const r = (await db.collection("receipts_transactions").doc("R_bad").get()).data();
  assert.equal(r.game_played, false);
});
