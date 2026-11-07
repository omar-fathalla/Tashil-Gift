"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { roundsFromRules, verifyConsumingDecrements, planConsumingClaim, netLine } = require("../consuming_spend_ladder");

const gift500 = "4QDy4H8psECEP4AnJSON";
const gift350 = "beGiYXcMAsW78OGevW5d";

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

const rules = [tier("tier-200", 200, "gift-200", 50), tier("tier-350", 350, gift350, 100), tier("tier-500", 500, gift500, 150)];

function line(price, extra = {}) {
  return Object.assign({ name: "كادبري بوبل", price, quantity: 1, barcode: "6220000000011", discountAmount: 0 }, extra);
}

function event(extra = {}) {
  return Object.assign({
    spendLadderMode: "consuming",
    allowMultipleChances: true,
    maxChancesPerReceipt: 3,
    promotionalRules: rules,
  }, extra);
}

test("1402 server rounds are 500, 500, 350", () => {
  const products = [line(492), line(240), line(294), line(294), line(82)];
  const result = roundsFromRules(rules, products, true);
  assert.deepEqual(result.rounds.map((round) => round.tierMinSpend), [500, 500, 350]);
  assert.deepEqual(result.rounds.map((round) => round.giftIds[0]), [gift500, gift500, gift350]);
});

test("forged 150 on the 350 round and extra quantity are rejected", () => {
  const products = [line(1402)];
  const receipt = { extracted_products: products, claimed_gifts: [
    { giftId: gift500, giftName: "قسيمة شراء 150 جنيه", quantity: 1, unitValue: 150 },
    { giftId: gift500, giftName: "قسيمة شراء 150 جنيه", quantity: 1, unitValue: 150 },
  ], game_played: true, remaining_chances: 1 };
  assert.equal(verifyConsumingDecrements(event(), receipt, [
    { prizeIdentifier: gift500, count: 1, claimSlot: 2, unitValue: 150, giftName: "قسيمة شراء 150 جنيه" },
  ]), "tier_mismatch");
  assert.equal(verifyConsumingDecrements(event(), {
    extracted_products: products,
    claimed_gifts: [],
    game_played: false,
    remaining_chances: 3,
  }, [{ prizeIdentifier: gift500, count: 4, claimSlot: 0, unitValue: 150 }]), "tier_mismatch");
  assert.equal(verifyConsumingDecrements(event(), {
    extracted_products: products,
    claimed_gifts: [{ quantity: 1 }, { quantity: 1 }, { quantity: 1 }],
    game_played: true,
    remaining_chances: 1,
  }, [{ prizeIdentifier: gift350, count: 1, claimSlot: 3, unitValue: 100 }]), "extra_quantity");
});

test("canonical gift id is the only authorization", () => {
  const products = [line(1402)];
  const base = {
    extracted_products: products,
    claimed_gifts: [
      { giftId: gift500, quantity: 1 },
      { giftId: gift500 },
    ],
    game_played: true,
    remaining_chances: 1,
  };
  assert.equal(verifyConsumingDecrements(event(), base, [{
    giftId: gift500,
    prizeIdentifier: gift500,
    count: 1,
    claimSlot: 2,
    unitValue: 100,
    giftName: "قسيمة شراء 100 جنيه",
  }]), "tier_mismatch");
  assert.equal(verifyConsumingDecrements(event(), base, [{
    giftId: "unknown-gift",
    count: 1,
    claimSlot: 2,
    unitValue: 100,
    giftName: "قسيمة شراء 100 جنيه",
  }]), "tier_mismatch");
  assert.equal(verifyConsumingDecrements(event(), base, [{
    prizeIdentifier: "قسيمة شراء 100 جنيه",
    count: 1,
    claimSlot: 2,
    unitValue: 100,
    giftName: "قسيمة شراء 100 جنيه",
  }]), "tier_mismatch");
  assert.equal(verifyConsumingDecrements(event(), base, [{
    prizeIdentifier: gift350,
    count: 1,
    claimSlot: 2,
    unitValue: 150,
    giftName: "قسيمة شراء 150 جنيه",
  }]), null);
  const stored = planConsumingClaim(event(), base, [{
    prizeIdentifier: gift350,
    count: 1,
    claimSlot: 2,
    unitValue: 150,
    giftName: "قسيمة شراء 150 جنيه",
  }]);
  assert.equal(stored.reason, null);
  assert.equal(stored.claimed_gifts.length, 3);
  assert.equal(stored.claimed_gifts[2].giftId, gift350);
  assert.equal(stored.claimed_gifts[2].unitValue, 100);
  assert.equal(stored.claimed_gifts[2].giftName, "قسيمة شراء 100 جنيه");
  assert.equal(stored.decrements[0].unitValue, 100);
  assert.equal(stored.decrements[0].prizeIdentifier, gift350);
  assert.equal(stored.remaining_chances, 0);
  const wiped = planConsumingClaim(event(), base, [{
    prizeIdentifier: gift350,
    count: 1,
    claimSlot: 2,
    unitValue: 100,
  }]);
  assert.deepEqual(wiped.claimed_gifts.slice(0, 2).map((gift) => gift.giftId), [gift500, gift500]);
});

test("partial retry uses persisted gifts, and a missing quantity still counts as one", () => {
  const products = [line(1402)];
  const once = {
    extracted_products: products,
    claimed_gifts: [{ giftId: gift500, giftName: "قسيمة شراء 150 جنيه" }],
    remaining_chances: 2,
  };
  assert.equal(verifyConsumingDecrements(event(), once, [{ prizeIdentifier: gift350, count: 1, claimSlot: 1, unitValue: 100 }]), "tier_mismatch");
  assert.equal(verifyConsumingDecrements(event(), once, [{ prizeIdentifier: gift500, count: 1, claimSlot: 1, unitValue: 150 }]), null);
  assert.equal(verifyConsumingDecrements(event(), once, [{ prizeIdentifier: gift500, count: 1, unitValue: 150 }]), "round_unbound");
  const replay = planConsumingClaim(event(), once, [{ prizeIdentifier: gift500, count: 1, claimSlot: 0, unitValue: 150 }]);
  assert.equal(replay.reason, null);
  assert.equal(replay.idempotent, true);
  assert.deepEqual(replay.decrements, []);
  assert.equal(replay.claimed_gifts.length, 1);
  const afterTwo = {
    extracted_products: products,
    claimed_gifts: [{ giftId: gift500 }, { giftId: gift500, quantity: null }],
    remaining_chances: 1,
  };
  assert.equal(verifyConsumingDecrements(event(), afterTwo, [{ prizeIdentifier: gift500, count: 1, claimSlot: 2, unitValue: 150 }]), "tier_mismatch");
  assert.equal(verifyConsumingDecrements(event(), {
    extracted_products: products,
    claimed_gifts: [{ quantity: 3 }],
    game_played: true,
    remaining_chances: 0,
  }, [{ prizeIdentifier: gift500, count: 1, claimSlot: 3, unitValue: 150 }]), "already_claimed");
});

test("a 350-only product does not fund the 500 tier", () => {
  const separate = [
    tier("only-500", 500, gift500, 150),
    tier("only-350", 350, gift350, 100),
  ];
  separate[0].selectedBarcodes = ["5005005005005"];
  separate[0].requiredBrands = ["فاخر"];
  separate[1].selectedBarcodes = ["3503503503503"];
  separate[1].requiredBrands = ["حليب"];
  const result = roundsFromRules(separate, [
    { name: "حليب محلى", price: 1402, quantity: 1, barcode: "3503503503503", discountAmount: 0 },
  ], true);
  assert.deepEqual(result.rounds.map((round) => round.ruleId), ["only-350", "only-350", "only-350", "only-350"]);
});

test("ambiguous net line is not membership and an already-net price is kept", () => {
  assert.equal(netLine({ price: 64, quantity: 3, discountAmount: 22 }), 126);
  assert.equal(netLine({ price: 57, quantity: 1, discountAmount: 28, originalPrice: 85 }), 57);
  const result = roundsFromRules(rules, [
    line(1402),
    { name: "لارش كيك ميلت شوك", price: 64, quantity: 3, discountAmount: 22, barcode: "", isTargetCompany: true },
  ], true);
  assert.deepEqual(result.rounds.map((round) => round.tierMinSpend), [500, 500, 350]);
});

test("exclusive campaigns are not verified by this gate", () => {
  assert.equal(verifyConsumingDecrements({ spendLadderMode: "exclusive", promotionalRules: rules }, {
    extracted_products: [line(1402)],
  }, [{ prizeIdentifier: gift500, count: 9 }]), null);
});
