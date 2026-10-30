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
test("known receipt branch without a stock row -> noBranchStock (not ambiguity)", () => {
  const r = resolvePrizeIndexForDecrement(rows, dec(), { branch_id: "other_1" });
  assert.strictEqual(r.index, -1);
  assert.strictEqual(r.noBranchStock, true);
  assert.strictEqual(r.branchId, "other_1");
});
test("store-coded receipt for a branch with no row -> noBranchStock", () => {
  const r = resolvePrizeIndexForDecrement(rows, dec(), { receipt_number: "200/4/243/301026", branch_id: "fathalla_243" });
  assert.strictEqual(r.index, -1);
  assert.strictEqual(r.noBranchStock, true);
});
test("no-branch-stock message text", () => {
  assert.strictEqual(require("../security_functions")._testing.NO_BRANCH_STOCK_MESSAGE, "مفيش رصيد للهدية دي في فرع الفاتورة، كلّم المشرف");
});
test("single branch row or general row stays allowed", () => {
  assert.strictEqual(resolvePrizeIndexForDecrement([rows[0]], dec(), {}).index, 0);
  const general = [...rows, { giftId: "g50", name: "فواتشر 50 جنيه", unitValue: 50, giftType: "voucher", remainingQuantity: 9 }];
  assert.strictEqual(resolvePrizeIndexForDecrement(general, dec(), {}).index, 2);
});

const { storeCodeFromReceiptNumber, branchIdFromStoreCode } = require("../security_functions")._testing;
test("store code parsed from receipt number (Fathalla 224)", () => {
  assert.strictEqual(storeCodeFromReceiptNumber("145/10/224/301026"), "224");
  assert.strictEqual(storeCodeFromReceiptNumber("١٤٥/١٠/٢٢٤/٣٠١٠٢٦"), "224");
  assert.strictEqual(storeCodeFromReceiptNumber("INV-55"), "");
});
test("store code overrides wrong AI branch_id (Badr ad -> 224)", () => {
  const r = resolvePrizeIndexForDecrement(rows, dec("fathalla_250"), { receipt_number: "145/10/224/301026", branch_id: "fathalla_272" });
  assert.strictEqual(r.index, 0);
  assert.strictEqual(r.branchId, "fathalla_224");
  assert.strictEqual(r.fromStoreCode, true);
});
test("no store-code match keeps the existing branch hint", () => {
  assert.strictEqual(branchIdFromStoreCode(rows, { receipt_number: "145/10/999/301026" }), "");
  const r = resolvePrizeIndexForDecrement(rows, dec(), { receipt_number: "145/10/999/301026", branch_id: "fathalla_250" });
  assert.strictEqual(r.index, 1);
});
