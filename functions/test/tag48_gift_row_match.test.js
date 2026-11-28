// TAG-48: a tier claim must take stock from a row of the same gift, never
// from another gift's row in the same branch.
const test = require("node:test");
const assert = require("node:assert/strict");
const { findBestPrizeMatchIndex, resolvePrizeIndexForDecrement } = require("../security_functions")._testing;

const bag = (id, name, branchId, remaining) => ({
  giftId: id, name, giftType: "product", unitValue: 0,
  branchId, branchName: `فرع ${branchId}`, allocatedQuantity: 10, remainingQuantity: remaining,
});
const voucher = (id, unit, branchId, remaining) => ({
  giftId: id, name: `فواتشر ${unit}`, giftType: "voucher", unitValue: unit,
  branchId, branchName: `فرع ${branchId}`, allocatedQuantity: 10, remainingQuantity: remaining,
});

// Knorr: tiers pay vouchers 25/50/75, the stock rows are spice bags only.
const knorrRows = () => [
  bag("bag-big", "شنطة بهارات كبيرة", "fathalla_241", 30),
  bag("bag-small", "شنطة بهارات صغيرة 25 جرام", "fathalla_241", 30),
];

test("voucher claim never takes a spice-bag row of the same branch", () => {
  const i = findBestPrizeMatchIndex(knorrRows(), "gift-voucher-25", {
    branchId: "fathalla_241", unitValue: 25, isVoucher: true,
  });
  assert.equal(i, -1);
});

test("voucher claim by name never takes a product row sharing a number", () => {
  const i = findBestPrizeMatchIndex(knorrRows(), "فواتشر 25", { branchId: "fathalla_241" });
  assert.equal(i, -1);
});

test("resolve returns -1 (no stock row) instead of another gift", () => {
  const r = resolvePrizeIndexForDecrement(knorrRows(), {
    prizeIdentifier: "gift-voucher-25", giftName: "فواتشر 25", unitValue: 25, isVoucher: true,
    branchId: "fathalla_241", count: 1,
  }, {});
  assert.equal(r.index, -1);
});

test("a known gift id never falls back to another gift id", () => {
  const rows = [voucher("v25", 25, "b1", 0), voucher("v50", 50, "b1", 9)];
  const i = findBestPrizeMatchIndex(rows, "v25", { branchId: "b1", unitValue: 25, isVoucher: true });
  assert.equal(i, 0); // the empty v25 row; the caller reports insufficient stock
});

test("voucher of another face value is not taken", () => {
  const rows = [voucher("v50", 50, "b1", 9)];
  const i = findBestPrizeMatchIndex(rows, "فواتشر 25", { branchId: "b1", unitValue: 25, isVoucher: true });
  assert.equal(i, -1);
});

test("the matching gift row in the receipt branch still wins", () => {
  const rows = [bag("bag-big", "شنطة بهارات كبيرة", "b1", 5), voucher("v25", 25, "b1", 4), voucher("v25", 25, "b2", 4)];
  const i = findBestPrizeMatchIndex(rows, "v25", { branchId: "b1", unitValue: 25, isVoucher: true });
  assert.equal(i, 1);
});

test("product gift by name still matches its row", () => {
  const i = findBestPrizeMatchIndex(knorrRows(), "شنطة بهارات كبيرة", { branchId: "fathalla_241" });
  assert.equal(i, 0);
});
