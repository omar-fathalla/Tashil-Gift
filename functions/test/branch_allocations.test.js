const test = require("node:test");
const assert = require("node:assert");
const { _test } = require("../branch_allocations");
const { cleanPrize, assertConsumedKept, authorize } = _test;
const req = (token) => ({ auth: { uid: "u", token: { firebase: { sign_in_provider: "custom" }, ...token } } });

test("authorize: ops partner of same company only", () => {
  assert.doesNotThrow(() => authorize(req({ role: "partner", companySlug: "galaxy", partnerAccess: "ops" }), "galaxy"));
  assert.throws(() => authorize(req({ role: "partner", companySlug: "galaxy", partnerAccess: "read" }), "galaxy"));
  assert.throws(() => authorize(req({ role: "partner", companySlug: "other", partnerAccess: "ops" }), "galaxy"));
  assert.throws(() => authorize({ auth: { uid: "a", token: { firebase: { sign_in_provider: "anonymous" }, role: "admin" } } }, "galaxy"));
  assert.throws(() => authorize({}, "galaxy"));
  assert.doesNotThrow(() => authorize(req({ role: "admin" }), "galaxy"));
});

test("cleanPrize validates numbers and drops unknown fields", () => {
  const p = cleanPrize({ giftId: "g", name: "n", allocatedQuantity: 50, remainingQuantity: 24, giftType: "gift", unitValue: 0, branchName: "b", x: 1 }, 0);
  assert.deepStrictEqual(Object.keys(p).sort(), ["allocatedQuantity", "branchName", "giftId", "giftType", "name", "remainingQuantity", "unitValue"]);
  assert.throws(() => cleanPrize({ allocatedQuantity: 5, remainingQuantity: 6 }, 0));
  assert.throws(() => cleanPrize({ allocatedQuantity: -1, remainingQuantity: 0 }, 0));
  assert.throws(() => cleanPrize({ allocatedQuantity: 1.5, remainingQuantity: 0 }, 0));
});

test("bulk edit cannot erase handed-out gifts", () => {
  const old = [{ giftId: "g", branchName: "B", allocatedQuantity: 50, remainingQuantity: 24 }];
  assert.doesNotThrow(() => assertConsumedKept(old, [{ giftId: "g", name: "n", branchName: "B", allocatedQuantity: 60, remainingQuantity: 34 }]));
  assert.throws(() => assertConsumedKept(old, [{ giftId: "g", name: "n", branchName: "B", allocatedQuantity: 60, remainingQuantity: 60 }]));
});

test("only changed rows are validated, against real handed-out (screen) count", () => {
  const { buildHandedOut } = _test;
  const B = "فرع عجمي ستار (الإسكندرية)";
  const old = [
    { giftId: "lb", name: "lunch box", branchName: B, allocatedQuantity: 10, remainingQuantity: 0 },
    { giftId: "kn", name: "سكينة", branchName: B, allocatedQuantity: 23, remainingQuantity: 5 },
  ];
  const handed = buildHandedOut([
    { branch_detected: B, claimed_gifts: [{ giftId: "lb", giftName: "lunch box", quantity: 1 }] },
    ...Array.from({ length: 29 }, () => ({ branch_detected: B, claimed_gifts: [{ giftId: "kn", giftName: "سكينة", quantity: 1 }] })),
  ], 0);
  // lunch box 10 -> 6 (stored consumed 10 is stale; real handed out = 1): allowed.
  const w = assertConsumedKept(old, [
    { giftId: "lb", name: "lunch box", branchName: B, allocatedQuantity: 6, remainingQuantity: 0 },
    { giftId: "kn", name: "سكينة", branchName: B, allocatedQuantity: 23, remainingQuantity: 5 },
  ], handed);
  // untouched سكينة (23 < 29 handed out) reported, not blocking
  assert.equal(w.length, 1);
  assert.equal(w[0].name, "سكينة");
  // changed row below real handed out is rejected
  assert.throws(() => assertConsumedKept(old, [
    { giftId: "kn", name: "سكينة", branchName: B, allocatedQuantity: 25, remainingQuantity: 0 },
  ], handed));
  assert.doesNotThrow(() => assertConsumedKept(old, [
    { giftId: "kn", name: "سكينة", branchName: B, allocatedQuantity: 29, remainingQuantity: 0 },
  ], handed));
});
