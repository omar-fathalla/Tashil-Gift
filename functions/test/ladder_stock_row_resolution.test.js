const test = require("node:test");
const assert = require("node:assert/strict");
const { resolveLadderStockRow, ladderRowConflicts, applyCampaignPrizeClaim } = require("../security_functions")._testing;

// Cadbury-style fixture: the 500 tier's option is "voucher 150" but its stock
// is held by its own row; the "voucher 25" row is empty in every branch.
const V150 = "gift-voucher-150";
const V25 = "gift-voucher-25";
const row = (giftId, unit, branchId, remaining) => ({
  giftId, name: `فواتشر ${unit}`, giftType: "voucher", unitValue: unit,
  branchId, branchName: `فرع ${branchId}`, allocatedQuantity: 100, remainingQuantity: remaining,
});
const rows = () => [
  row(V150, 150, "b1", 51), row(V25, 25, "b1", 0),
  row(V150, 150, "b2", 7), row(V25, 25, "b2", 0),
];
const dec = (giftId, extra = {}) => Object.assign({
  prizeIdentifier: giftId, giftName: "فواتشر 150", unitValue: 150, isVoucher: true,
  branchId: "b1", count: 1, ladder: true,
}, extra);
const misconfigured = (err) => {
  assert.equal(err.code, "failed-precondition");
  assert.equal(err.details.reason, "campaign_misconfigured");
  assert.match(err.message, /إعداد الحملة غير صحيح/);
  assert.match(err.message, /فواتشر 150/);
  assert.match(err.message, /فرع b1/);
  return true;
};

test("correct giftId picks the voucher-150 row of the receipt branch", () => {
  assert.equal(resolveLadderStockRow(rows(), dec(V150), {}).index, 0);
  assert.equal(resolveLadderStockRow(rows(), dec(V150, { branchId: "" }), { branch_id: "b2" }).index, 2);
});

test("tier option bound to the voucher-25 id -> misconfigured, not insufficient stock", () => {
  assert.throws(() => resolveLadderStockRow(rows(), dec(V25), {}), misconfigured);
});

test("a row of another gift never wins on name/value score", () => {
  // Only the voucher-150 row exists for b1 under a different id; the request id has no row.
  const r = resolveLadderStockRow([row("other", 150, "b1", 51)], dec(V150), {});
  assert.equal(r.index, -1);
});

test("same giftId but a different branch only -> noBranchStock", () => {
  const r = resolveLadderStockRow([row(V150, 150, "b2", 7)], dec(V150), {});
  assert.equal(r.index, -1);
  assert.equal(r.noBranchStock, true);
});

test("general (branchless) row of the same gift stays allowed", () => {
  const general = Object.assign(row(V150, 150, "", 9), { branchId: "", branchName: "" });
  assert.equal(resolveLadderStockRow([row(V150, 150, "b2", 7), general], dec(V150), {}).index, 1);
});

test("no branch hint with several branch rows is refused", () => {
  assert.throws(() => resolveLadderStockRow(rows(), dec(V150, { branchId: "" }), {}), /تعذر تحديد فرع/);
});

test("value-agreeing duplicate row wins over a contradicting one", () => {
  const dup = [row(V150, 100, "b1", 5), row(V150, 150, "b1", 5)];
  assert.equal(resolveLadderStockRow(dup, dec(V150), {}).index, 1);
});

test("conflict check ignores product rows and missing values", () => {
  assert.equal(ladderRowConflicts({ name: "شوكولاتة 100 جم", giftType: "product" }, dec(V150)), false);
  assert.equal(ladderRowConflicts(row(V150, 150, "b1", 1), dec(V150, { unitValue: 0, giftName: "" })), false);
  assert.equal(ladderRowConflicts(row(V25, 25, "b1", 1), dec(V25, { unitValue: 0 })), true);
});

// ---- applyCampaignPrizeClaim end to end (fake transaction) ----
function fakeDb(docs) {
  const store = new Map(Object.entries(docs).map(([k, v]) => [k, JSON.parse(JSON.stringify(v))]));
  const ref = (path) => ({ path, id: path.split("/").pop() });
  const snapOf = (r) => ({ exists: store.has(r.path), data: () => store.get(r.path), id: r.id, ref: r });
  const collection = (name) => {
    const q = { doc: (id) => ref(`${name}/${id}`), where: () => q, _query: true, _run: () => [] };
    return q;
  };
  return {
    store, collection,
    runTransaction: async (fn) => fn({
      get: async (r) => (r._query ? { docs: r._run() } : snapOf(r)),
      update: (r, d) => store.set(r.path, Object.assign({}, store.get(r.path), d)),
      set: (r, d) => store.set(r.path, Object.assign({}, store.get(r.path) || {}, d)),
    }),
  };
}
function cadburyEvent(optionGiftId) {
  return {
    companySlug: "cadbury", isActive: true, spendLadderMode: "consuming",
    allowMultipleChances: true, maxChancesPerReceipt: 3, balanceMode: "campaign_only",
    promotionalRules: [{
      id: "t500", conditionType: "by_spend", minSpend: 500, requiredBrands: ["كادبري"],
      selectedBarcodes: ["6220000000011"], triggerProduct: "كادبري",
      rewardOptions: [{ kind: "voucher", giftId: optionGiftId, giftType: "voucher", voucherAmount: 150, label: "فواتشر 150" }],
    }],
    allocatedPrizes: rows(),
  };
}
const receiptDoc = () => ({
  campaignId: "E", submittedByUid: "u1", branch_id: "b1", chances_earned: 1, game_played: false,
  extracted_products: [{ name: "كادبري", price: 520, quantity: 1, barcode: "6220000000011" }],
});
const claim = (db, giftId) => applyCampaignPrizeClaim(db, {
  eventId: "E", receiptId: "r1", actor: { staff: true, uid: "s1" },
  decrements: [{ prizeIdentifier: giftId, branchId: "b1", count: 1, unitValue: 150, isVoucher: true, gameType: "chooseGift", claimSlot: 0 }],
  receiptPatch: { game_played: true },
});

test("claim: correct option id decrements the voucher-150 row (51 -> 50)", async () => {
  const db = fakeDb({ "events/E": cadburyEvent(V150), "receipts_transactions/r1": receiptDoc() });
  await claim(db, V150);
  const prizes = db.store.get("events/E").allocatedPrizes;
  assert.deepEqual(prizes.map((p) => p.remainingQuantity), [50, 0, 7, 0]);
});

test("claim: option bound to voucher-25 id fails as misconfigured and writes nothing", async () => {
  const db = fakeDb({ "events/E": cadburyEvent(V25), "receipts_transactions/r1": receiptDoc() });
  const before = JSON.stringify([...db.store]);
  await assert.rejects(claim(db, V25), (err) => err.details.reason === "campaign_misconfigured");
  assert.equal(JSON.stringify([...db.store]), before);
});

test("claim: empty correct row reports insufficient stock with gift, branch and remaining", async () => {
  const ev = cadburyEvent(V150);
  ev.allocatedPrizes[0].remainingQuantity = 0;
  const db = fakeDb({ "events/E": ev, "receipts_transactions/r1": receiptDoc() });
  await assert.rejects(claim(db, V150), (err) => {
    assert.equal(err.details.reason, "insufficient_stock");
    assert.equal(err.details.remaining, 0);
    assert.equal(err.details.branch, "فرع b1");
    assert.match(err.message, /^Not enough prize stock remaining for "فواتشر 150"/);
    return true;
  });
});
