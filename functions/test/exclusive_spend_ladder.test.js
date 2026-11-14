const test = require("node:test");
const assert = require("node:assert");
const { exclusiveLadderUnits } = require("../exclusive_spend_ladder");
const { receiptUnitLimit } = require("../security_functions")._testing;

const BARCODES = ["6221134031478", "6221134030914"];
const tier = (id, minSpend, extra = {}) => Object.assign({
  id, conditionType: "by_spend", minSpend, discountTolerance: 5, selectedBarcodes: BARCODES,
  linkedGifts: [{ giftId: `g_${id}`, giftName: id, quantity: 1 }],
}, extra);
const galaxy = (extra = {}) => Object.assign({
  companySlug: "583", isActive: true, allowMultipleChances: true, maxChancesPerReceipt: 3,
  promotionalRules: [tier("t150", 150), tier("t350", 350), tier("t450", 450)],
}, extra);
const receipt = (spend, extra = {}) => Object.assign({
  campaignId: "E", submittedByUid: "u1",
  extracted_products: [{ name: "جلاكسي", price: spend, quantity: 1, isTargetCompany: true, barcode: BARCODES[0] }],
}, extra);

test("618 eligible -> 450 + 150 (2 offers)", () => {
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(618)), 2);
});

test("309.5 and 308.5 -> exactly one 150", () => {
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(309.5)), 1);
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(308.5)), 1);
});

test("tolerance edges: 445 reaches 450 with no remainder; 595 = 450 + 145 reaches 150", () => {
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(445)), 1);
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(444.99)), 1);
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(595)), 2);
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(594.99)), 1);
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(144.99)), 0);
});

test("remainder buys one lower tier only, never a cascade", () => {
  // 1000 with multipliers: 2 x 450, remainder 100 -> nothing.
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(1000)), 2);
  // 1250: 2 x 450, remainder 350 -> one 350 (not 350 + more).
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(1250)), 3);
});

test("Smart Multipliers OFF keeps one offer", () => {
  assert.strictEqual(exclusiveLadderUnits(galaxy({ allowMultipleChances: false }), receipt(618)), 1);
});

test("consuming mode and non-barcode rules are left alone", () => {
  assert.strictEqual(exclusiveLadderUnits(galaxy({ spendLadderMode: "consuming" }), receipt(618)), null);
  const qty = galaxy();
  qty.promotionalRules.push({ id: "q", conditionType: "by_quantity", minQuantity: 2, selectedBarcodes: ["1"] });
  assert.strictEqual(exclusiveLadderUnits(qty, receipt(618)), null);
  assert.strictEqual(exclusiveLadderUnits(galaxy(), { extracted_products: [] }), null);
});

test("only campaign products count toward the ladder", () => {
  const r = receipt(0, {
    extracted_products: [
      { name: "جلاكسي", price: 470, quantity: 1, isTargetCompany: true, barcode: BARCODES[0] },
      { name: "سكر", price: 200, quantity: 1, isTargetCompany: false, barcode: "999" },
    ],
  });
  assert.strictEqual(exclusiveLadderUnits(galaxy(), r), 1);
});

test("receiptUnitLimit: client cannot inflate chances_earned past the ladder", () => {
  assert.strictEqual(receiptUnitLimit(galaxy(), receipt(618, { chances_earned: 2 })), 2);
  assert.strictEqual(receiptUnitLimit(galaxy(), receipt(618, { chances_earned: 3 })), 2);
  assert.strictEqual(receiptUnitLimit(galaxy(), receipt(309.5, { chances_earned: 3 })), 1);
});

test("receiptUnitLimit: per-receipt cap still wins over the ladder", () => {
  // 1500 = 3 x 450 + 150 remainder -> 4 offers, capped at 3.
  assert.strictEqual(exclusiveLadderUnits(galaxy(), receipt(1500)), 4);
  assert.strictEqual(receiptUnitLimit(galaxy(), receipt(1500, { chances_earned: 4 })), 3);
});
