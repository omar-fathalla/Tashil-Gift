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
