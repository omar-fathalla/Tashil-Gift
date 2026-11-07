const test = require("node:test");
const assert = require("node:assert");
const { replaceReceiptHandler, buildNewDoc, modeFor } = require("../receipt_replace");
const { deterministicDocId } = require("../receipt_duplicate_check");

const ID = deterministicDocId("E", "134/5/218");
function mkDb(existing, ev = { companySlug: "583", isActive: true }) {
  const writes = [];
  const docRef = (id, path) => ({
    id, path,
    collection: (c) => ({ doc: () => docRef("H1", `${path}/${c}/H1`) }),
    get: async () => ({ exists: !!existing, data: () => existing }),
  });
  return {
    writes,
    collection: (n) => n === "events"
      ? { doc: () => ({ get: async () => ({ exists: !!ev, data: () => ev }) }) }
      : n === "rateLimits" ? { doc: () => ({}) }
      : { doc: (id) => docRef(id, `receipts_transactions/${id}`) },
    runTransaction: async (fn) => fn({
      get: async (r) => (r.get ? r.get() : { exists: false }),
      getAll: async (...r) => r.map(() => ({ exists: false, data: () => ({}) })),
      set: (r, d) => { if (r.path) writes.push({ path: r.path, d }); },
      update: () => {},
    }),
  };
}
const payload = (x = {}) => ({ receipt_number: "134/5/218", campaignId: "E", companySlug: "583", status: "accepted", is_valid: true, total_value: 832.95, customerPhone: "0100", game_played: false, prize_won: null, ...x });
const req = (x = {}, tok = { firebase: { sign_in_provider: "anonymous" } }) => ({ app: {}, auth: { uid: "u2", token: tok }, rawRequest: { headers: {} }, data: { campaignId: "E", receiptNumber: "134/5/218", receipt: payload(x) } });

const ADMIN = { role: "admin", firebase: { sign_in_provider: "password" } };
test("2.0.152: approved doc is locked for anonymous rep: no writes, details returned", async () => {
  const old = { campaignId: "E", companySlug: "583", status: "accepted", is_valid: true, total_value: 772, branch_detected: "B1", prize_won: "100", customerPhone: "0111", timestamp: new Date("2026-10-30T14:12:00Z") };
  const db = mkDb(old);
  await assert.rejects(replaceReceiptHandler(db, req()), (e) => {
    assert.strictEqual(e.code, "failed-precondition");
    assert.strictEqual(e.message, "الفاتورة دي اتعمدت قبل كده");
    assert.strictEqual(e.details.locked, true);
    assert.strictEqual(e.details.summary.total, 772);
    assert.strictEqual(e.details.summary.branch, "B1");
    assert.strictEqual(e.details.summary.giftValue, "100");
    assert.strictEqual(e.details.summary.approvedAt, "2026-10-30T14:12:00.000Z");
    assert.ok(!JSON.stringify(e.details).includes("0111"));
    return true;
  });
  assert.strictEqual(db.writes.length, 0);
});
test("2.0.152: approved doc locked for non-admin signed-in roles and partner ops", async () => {
  const old = { campaignId: "E", companySlug: "583", status: "accepted", is_valid: true };
  for (const tok of [{ role: "partner", partnerAccess: "ops", companySlug: "583", firebase: { sign_in_provider: "password" } }, { role: "admin", firebase: { sign_in_provider: "anonymous" } }]) {
    const db = mkDb(old);
    await assert.rejects(replaceReceiptHandler(db, req({}, tok)), (e) => e.code === "failed-precondition" || e.code === "permission-denied");
    assert.strictEqual(db.writes.length, 0);
  }
});
test("2.0.152: admin and super_admin cannot replace an approved doc either", async () => {
  for (const role of ["admin", "super_admin"]) {
    const db = mkDb({ campaignId: "E", companySlug: "583", status: "accepted", is_valid: true, total_value: 1 });
    await assert.rejects(replaceReceiptHandler(db, req({}, { role, firebase: { sign_in_provider: "password" } })), (e) => e.code === "failed-precondition" && e.details.locked === true);
    assert.strictEqual(db.writes.length, 0);
  }
});
test("2.0.152: rejected-but-claimed doc is locked for rep too", async () => {
  const db = mkDb({ campaignId: "E", companySlug: "583", status: "rejected", is_valid: false, game_played: true });
  await assert.rejects(replaceReceiptHandler(db, req()), (e) => e.details && e.details.locked === true);
  assert.strictEqual(db.writes.length, 0);
});
test("no existing doc: tells client to create normally (case 134)", async () => {
  const db = mkDb(null);
  const r = await replaceReceiptHandler(db, req());
  assert.strictEqual(r.mode, "create"); assert.strictEqual(r.replaced, false); assert.strictEqual(db.writes.length, 0);
});
test("rejected doc: re-upload, history kept, becomes accepted with fresh game", async () => {
  const old = { campaignId: "E", companySlug: "583", status: "rejected", is_valid: false, rejection_reason: "x", total_value: 10, submittedByUid: "u1" };
  const db = mkDb(old);
  const r = await replaceReceiptHandler(db, req());
  assert.strictEqual(r.mode, "reupload");
  assert.strictEqual(db.writes.length, 2);
  assert.match(db.writes[0].path, /history/); assert.strictEqual(db.writes[0].d.status, "rejected");
  const n = db.writes[1].d;
  assert.strictEqual(n.status, "accepted"); assert.strictEqual(n.total_value, 832.95); assert.strictEqual(n.game_played, false); assert.strictEqual(n.replace_count, 1);
});
test("rejected but previously claimed is treated as replace (no second claim)", () => {
  assert.strictEqual(modeFor({ status: "rejected", is_valid: false, game_played: true }), "replace");
  assert.strictEqual(modeFor({ status: "rejected", is_valid: false }), "reupload");
});
test("replace cannot smuggle server-only fields", () => {
  const n = buildNewDoc({ status: "accepted", prize_won: "A" }, { prize_won: "B", status: "accepted", history: [1] }, "replace", "u");
  assert.strictEqual(n.prize_won, "A"); assert.strictEqual(n.history, undefined);
});
test("company mismatch and inactive campaign are refused", async () => {
  await assert.rejects(replaceReceiptHandler(mkDb({}), req({ companySlug: "999" })), /mismatch/);
  await assert.rejects(replaceReceiptHandler(mkDb({}, { companySlug: "583", isActive: false }), req()), /not active/);
});
test("non-anonymous non-staff caller refused; App Check required", async () => {
  await assert.rejects(replaceReceiptHandler(mkDb({}), req({}, { firebase: { sign_in_provider: "password" }, role: "viewer" })), /Not allowed/);
  await assert.rejects(replaceReceiptHandler(mkDb({}), { ...req(), app: undefined }), /App Check/);
});
