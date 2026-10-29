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
