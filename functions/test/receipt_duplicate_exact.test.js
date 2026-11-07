const test = require("node:test");
const assert = require("node:assert");
const { checkReceiptDuplicateHandler, deterministicDocId } = require("../receipt_duplicate_check");

function db(existing) {
  const docs = { [deterministicDocId("E", "123")]: existing };
  const q = { where: () => q, limit: () => q, get: async () => ({ docs: [] }) };
  return {
    collection: (n) => n === "events"
      ? { doc: () => ({ get: async () => ({ exists: true, data: () => ({ companySlug: "469", branchNames: [] }) }) }) }
      : n === "rateLimits" ? { doc: () => ({}) }
      : { doc: (id) => ({ get: async () => ({ exists: !!docs[id], data: () => docs[id] }) }), ...q },
    runTransaction: async (fn) => fn({ getAll: async (...r) => r.map(() => ({ exists: false, data: () => ({}) })), get: async () => ({ exists: false }), set: () => {} }),
  };
}
const req = (extra) => ({ app: {}, auth: { uid: "u" }, rawRequest: { headers: {} }, data: { receiptNumber: "123", companySlug: "469", campaignId: "E", ...extra } });

test("rejected doc at exact id: not duplicate by default (backward compatible)", async () => {
  const r = await checkReceiptDuplicateHandler(db({ status: "rejected", is_valid: false }), req({}));
  assert.strictEqual(r.duplicate, false);
});
test("rejected doc at exact id with exactDocId: reported as already uploaded", async () => {
  const r = await checkReceiptDuplicateHandler(db({ status: "rejected", is_valid: false }), req({ exactDocId: true }));
  assert.strictEqual(r.duplicate, true);
  assert.strictEqual(r.exactDocExists, true);
  assert.strictEqual(r.summary.status, "rejected");
});
test("2.0.152: approved doc is locked for anonymous rep with details, no PII", async () => {
  const d = { status: "accepted", is_valid: true, total_value: 772, branch_detected: "B", prize_won: "100", customerPhone: "0100", customerName: "X", timestamp: new Date("2026-10-30T14:12:00Z") };
  const r = await checkReceiptDuplicateHandler(db(d), { ...req({ exactDocId: true }), auth: { uid: "u", token: { firebase: { sign_in_provider: "anonymous" } } } });
  assert.strictEqual(r.duplicate, true); assert.strictEqual(r.locked, true); assert.strictEqual(r.exactDocExists, true);
  assert.strictEqual(r.message, "الفاتورة دي اتعمدت قبل كده");
  assert.strictEqual(r.summary.total, 772); assert.strictEqual(r.summary.approvedAt, "2026-10-30T14:12:00.000Z");
  assert.ok(!JSON.stringify(r).includes("0100")); assert.ok(!JSON.stringify(r).includes("customerName"));
});
test("2.0.152: approved doc locked for admin too", async () => {
  const r = await checkReceiptDuplicateHandler(db({ status: "accepted", is_valid: true }), { ...req({}), auth: { uid: "u", token: { role: "admin", firebase: { sign_in_provider: "password" } } } });
  assert.strictEqual(r.duplicate, true); assert.strictEqual(r.locked, true); assert.strictEqual(r.exactDocExists, true);
});
test("2.0.152: rejected doc not locked (re-upload allowed)", async () => {
  const r = await checkReceiptDuplicateHandler(db({ status: "rejected", is_valid: false }), req({ exactDocId: true }));
  assert.strictEqual(r.locked, false);
});
