const test = require("node:test");
const assert = require("node:assert/strict");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;

const gift500 = "4QDy4H8psECEP4AnJSON";
const gift350 = "beGiYXcMAsW78OGevW5d";

function fakeDb(docs) {
  const store = new Map(Object.entries(docs).map(([key, value]) => [key, JSON.parse(JSON.stringify(value))]));
  const ref = (path) => ({ path, id: path.split("/").pop() });
  const snapOf = (r) => ({ exists: store.has(r.path), data: () => store.get(r.path), id: r.id, ref: r });
  const collection = (name) => {
    const q = { doc: (id) => ref(`${name}/${id}`), where: () => q, _query: true, _run: () => [] };
    return q;
  };
  return {
    store,
    collection,
    runTransaction: async (fn) => fn({
      get: async (r) => (r._query ? { docs: r._run() } : snapOf(r)),
      update: (r, data) => store.set(r.path, Object.assign({}, store.get(r.path), data)),
      set: (r, data) => store.set(r.path, Object.assign({}, store.get(r.path) || {}, data)),
    }),
  };
}

function tier(id, min, giftId, amount) {
  return {
    id,
    conditionType: "by_spend",
    minSpend: min,
    triggerProduct: "كادبري",
    requiredBrands: ["كادبري"],
    selectedBarcodes: ["6220000000011"],
    allowMultipliers: true,
    rewardOptions: [{
      kind: "voucher",
      giftId,
      giftType: "voucher",
      voucherAmount: amount,
      label: `قسيمة شراء ${amount} جنيه`,
    }],
  };
}

function row(giftId, unit, remaining) {
  return {
    giftId,
    name: `قسيمة شراء ${unit} جنيه`,
    giftType: "voucher",
    unitValue: unit,
    remainingQuantity: remaining,
  };
}

function event() {
  return {
    companySlug: "fixture-co",
    isActive: true,
    spendLadderMode: "consuming",
    allowMultipleChances: true,
    maxChancesPerReceipt: 3,
    balanceMode: "campaign_only",
    promotionalRules: [
      tier("tier-200", 200, "gift-200", 50),
      tier("tier-350", 350, gift350, 100),
      tier("tier-500", 500, gift500, 150),
    ],
    allocatedPrizes: [row(gift500, 150, 5), row(gift500, 100, 5), row(gift350, 100, 5)],
  };
}

function products() {
  return [492, 240, 294, 294, 82].map((price) => ({
    name: "كادبري بوبل",
    price,
    quantity: 1,
    barcode: "6220000000011",
    discountAmount: 0,
  }));
}

function receipt(extra = {}) {
  return Object.assign({
    campaignId: "E",
    submittedByUid: "u1",
    chances_earned: 1,
    game_played: false,
    remaining_chances: 3,
    extracted_products: products(),
  }, extra);
}

const actor = { staff: true, uid: "staff-1" };

function claim(db, prizeIdentifier, unitValue, patch, claimSlot) {
  return applyCampaignPrizeClaim(db, {
    eventId: "E",
    receiptId: "r1",
    actor,
    decrements: [{
      prizeIdentifier,
      count: 1,
      unitValue,
      isVoucher: true,
      gameType: "chooseGift",
      claimSlot,
    }],
    receiptPatch: Object.assign({
      game_played: true,
      claimed_gifts: [{ giftId: "forged", giftName: "قسيمة شراء 100 جنيه", quantity: 9, unitValue: 100 }],
      prize_won: "قسيمة شراء 100 جنيه",
      prizes_won: ["قسيمة شراء 100 جنيه"],
      remaining_chances: 0,
    }, patch),
  });
}

function stock(db, index) {
  return db.store.get("events/E").allocatedPrizes[index].remainingQuantity;
}

test("canonical metadata is stored and the client array cannot replace the ledger", async () => {
  const db = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt() });
  await assert.rejects(
    claim(db, gift350, 100, {}, 0),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(stock(db, 0), 5);
  assert.equal(db.store.get("receipts_transactions/r1").claimed_gifts, undefined);

  await claim(db, gift500, 100, {}, 0);
  await claim(db, gift500, 100, {}, 1);
  await claim(db, gift350, 150, {}, 2);
  const saved = db.store.get("receipts_transactions/r1");
  assert.deepEqual(saved.claimed_gifts.map((gift) => gift.giftId), [gift500, gift500, gift350]);
  assert.deepEqual(saved.claimed_gifts.map((gift) => gift.unitValue), [150, 150, 100]);
  assert.deepEqual(saved.claimed_gifts.map((gift) => gift.giftName), [
    "قسيمة شراء 150 جنيه",
    "قسيمة شراء 150 جنيه",
    "قسيمة شراء 100 جنيه",
  ]);
  assert.equal(saved.remaining_chances, 0);
  assert.equal(stock(db, 0), 3);
  assert.equal(stock(db, 1), 5);
  assert.equal(stock(db, 2), 4);

  await assert.rejects(
    claim(db, gift500, 150, {}, 3),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(stock(db, 0), 3);
  assert.equal(db.store.get("receipts_transactions/r1").claimed_gifts.length, 3);
});

test("a missing quantity still advances the round, and a later call keeps the earlier entry", async () => {
  const db = fakeDb({
    "events/E": event(),
    "receipts_transactions/r1": receipt({
      claimed_gifts: [{ giftId: gift500, giftName: "قسيمة شراء 150 جنيه" }],
      game_played: true,
      remaining_chances: 2,
    }),
  });
  await claim(db, gift500, 100, { claimed_gifts: [] }, 1);
  const saved = db.store.get("receipts_transactions/r1");
  assert.equal(saved.claimed_gifts.length, 2);
  assert.equal(saved.claimed_gifts[0].giftId, gift500);
  assert.equal(saved.claimed_gifts[1].unitValue, 150);
  assert.equal(stock(db, 0), 4);
});

test("name-only and unknown ids do not change stock", async () => {
  const db = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt() });
  await assert.rejects(claim(db, "قسيمة شراء 150 جنيه", 150, {}, 0), (error) => error.code === "failed-precondition");
  await assert.rejects(claim(db, "unknown-gift", 150, {}, 0), (error) => error.code === "failed-precondition");
  assert.equal(stock(db, 0), 5);
  assert.equal(stock(db, 2), 5);
});

test("replaying the same slot does not consume the next round or stock", async () => {
  const db = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt() });
  await claim(db, gift500, 150, {}, 0);
  await claim(db, gift500, 150, {}, 0);
  const saved = db.store.get("receipts_transactions/r1");
  assert.equal(saved.claimed_gifts.length, 1);
  assert.equal(saved.claimed_gifts[0].giftId, gift500);
  assert.equal(stock(db, 0), 4);
});

test("a consuming campaign without a spend rule does not decrement stock", async () => {
  const bare = event();
  bare.promotionalRules = [{ conditionType: "by_quantity", minSpend: 0, triggerProduct: "كادبري" }];
  const db = fakeDb({ "events/E": bare, "receipts_transactions/r1": receipt() });
  await assert.rejects(claim(db, gift500, 150, {}, 0), (error) => error.code === "failed-precondition");
  assert.equal(stock(db, 0), 5);
  assert.equal(db.store.get("receipts_transactions/r1").claimed_gifts, undefined);
});
