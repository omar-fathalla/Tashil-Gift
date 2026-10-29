const test = require("node:test");
const assert = require("node:assert");
const { resolvePrizeIndexForDecrement } = require("../security_functions")._testing;

const rows = [
  { giftId: "g50", name: "فواتشر 50 جنيه", unitValue: 50, giftType: "voucher", branchId: "fathalla_224", branchName: "فرع عجمي ستار", remainingQuantity: 5 },
  { giftId: "g50", name: "فواتشر 50 جنيه", unitValue: 50, giftType: "voucher", branchId: "fathalla_250", branchName: "فرع مدينة الرحاب (القاهرة)", remainingQuantity: 5 },
];
const dec = (branchId = "") => ({ prizeIdentifier: "g50", branchId, count: 1, unitValue: 50, isVoucher: true });

test("explicit branch picks that branch's row", () => {
  assert.strictEqual(resolvePrizeIndexForDecrement(rows, dec("fathalla_250"), {}).index, 1);
});
test("empty branch falls back to receipt.branch_id", () => {
  const r = resolvePrizeIndexForDecrement(rows, dec(), { branch_id: "fathalla_250" });
  assert.strictEqual(r.index, 1);
  assert.strictEqual(r.branchId, "fathalla_250");
});
test("empty branch falls back to receipt.branch_detected name", () => {
  assert.strictEqual(resolvePrizeIndexForDecrement(rows, dec(), { branch_detected: "فرع مدينة الرحاب (القاهرة)" }).index, 1);
});
test("empty branch with several branch rows and no hint is refused", () => {
  assert.throws(() => resolvePrizeIndexForDecrement(rows, dec(), {}), /تعذر تحديد فرع/);
});
test("unknown branch hint with several branch rows is refused", () => {
  assert.throws(() => resolvePrizeIndexForDecrement(rows, dec(), { branch_id: "other_1" }), /تعذر تحديد فرع/);
});
test("single branch row or general row stays allowed", () => {
  assert.strictEqual(resolvePrizeIndexForDecrement([rows[0]], dec(), {}).index, 0);
  const general = [...rows, { giftId: "g50", name: "فواتشر 50 جنيه", unitValue: 50, giftType: "voucher", remainingQuantity: 9 }];
  assert.strictEqual(resolvePrizeIndexForDecrement(general, dec(), {}).index, 2);
});
