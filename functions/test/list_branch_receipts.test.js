const test = require("node:test");
const assert = require("node:assert");
const { resolveEventBranch, projectReceipt, maskPhone, listBranchReceiptsHandler } = require("../list_branch_receipts");

const ev = {
  isActive: true, isPromoterActive: true, companySlug: "469",
  branchNames: ["فرع طنطا (الغربية)", "فرع عجمي ستار (الإسكندرية)"],
  branchIds: ["fathalla_231", "fathalla_224"],
};

test("resolveEventBranch maps canonical name to aligned branch id", () => {
  assert.deepStrictEqual(resolveEventBranch(ev, "فرع عجمي ستار (الإسكندرية)", ""),
    { branchName: "فرع عجمي ستار (الإسكندرية)", branchId: "fathalla_224" });
  assert.strictEqual(resolveEventBranch(ev, "فرع غير موجود", ""), null);
});

test("projectReceipt hides personal data and flags session", () => {
  const p = projectReceipt("x", { customerPhone: "01012345678", customerName: "A", image_url: "u", submittedByUid: "u1", status: "accepted" }, "u2");
  assert.strictEqual(p.customer_phone_masked, "********678");
  assert.strictEqual(p.same_session, false);
  assert.ok(!("customerName" in p) && !("image_url" in p));
  assert.strictEqual(maskPhone("12"), null);
});

function fakeDb(docs) {
  const q = (filters) => ({
    where: (f, _op, v) => q([...filters, [f, v]]),
    limit: () => q(filters),
    get: async () => ({ docs: docs.filter((d) => filters.every(([f, v]) => d.data[f] === v)).map((d) => ({ id: d.id, data: () => d.data })) }),
  });
  return {
    collection: (name) => {
      if (name === "events") return { doc: () => ({ get: async () => ({ exists: true, data: () => ev }) }) };
      if (name === "rateLimits") {
        return { doc: () => ({}) };
      }
      return q([]);
    },
    runTransaction: async (fn) => fn({ getAll: async (...refs) => refs.map(() => ({ exists: false, data: () => ({}) })), get: async () => ({ exists: false }), set: () => {} }),
  };
}

test("handler returns other-session receipts for the branch (by id and name)", async () => {
  const db = fakeDb([
    { id: "a", data: { campaignId: "E", branch_id: "fathalla_224", branch_detected: "فرع عجمي ستار (الإسكندرية)", submittedByUid: "old" } },
    { id: "b", data: { campaignId: "E", branch_detected: "فرع عجمي ستار (الإسكندرية)", submittedByUid: "me" } },
    { id: "c", data: { campaignId: "E", branch_id: "fathalla_231", submittedByUid: "old" } },
  ]);
  const res = await listBranchReceiptsHandler(db, { app: {}, auth: { uid: "me" }, data: { campaignId: "E", branchName: "فرع عجمي ستار (الإسكندرية)" }, rawRequest: { ip: "1.1.1.1", headers: {} } });
  assert.deepStrictEqual(res.receipts.map((r) => r.id).sort(), ["a", "b"]);
  assert.strictEqual(res.otherSessionCount, 1);
});

test("handler rejects missing App Check and foreign branch", async () => {
  await assert.rejects(listBranchReceiptsHandler(fakeDb([]), { auth: { uid: "x" }, data: {} }));
  await assert.rejects(listBranchReceiptsHandler(fakeDb([]), { app: {}, auth: { uid: "x" }, data: { campaignId: "E", branchName: "غير" }, rawRequest: { headers: {} } }));
});
