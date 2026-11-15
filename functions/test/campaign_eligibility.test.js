const test = require("node:test");
const assert = require("node:assert");
const {
  REASONS,
  evaluateClaimEligibility,
  campaignWindow,
  cairoMidnightMs,
  receiptDayCandidates,
  purchaseDateVerdict,
} = require("../campaign_eligibility");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;

const BARCODES = ["6221134031478", "6221134030914"];
const FIRST = Date.UTC(2026, 10, 1, 22, 0); // Cairo 2026-11-02 00:00 (UTC+2)
const LAST = Date.UTC(2026, 10, 6, 22, 0); // Cairo 2026-11-07 00:00
const at = (iso) => Date.parse(iso);
const NOW = at("2026-11-04T09:00:00Z");

const tier = (id, minSpend, extra = {}) => Object.assign({
  id, conditionType: "by_spend", minSpend, discountTolerance: 0, selectedBarcodes: BARCODES,
  linkedGifts: [{ giftId: `g_${id}`, giftName: id, quantity: 1 }],
}, extra);
const campaign = (extra = {}) => Object.assign({
  companySlug: "583", isActive: true, startDate: new Date(FIRST), endDate: new Date(LAST),
  allowMultipleChances: false, maxChancesPerReceipt: 1,
  promotionalRules: [tier("t150", 150), tier("t350", 350), tier("t450", 450)],
  allocatedPrizes: [
    { giftId: "g_t150", name: "t150", giftType: "voucher", unitValue: 150, branchId: "b1", remainingQuantity: 10 },
    { giftId: "g_t350", name: "t350", giftType: "voucher", unitValue: 350, branchId: "b1", remainingQuantity: 10 },
    { giftId: "g_t450", name: "t450", giftType: "voucher", unitValue: 450, branchId: "b1", remainingQuantity: 10 },
  ],
}, extra);
const brandLine = (price, extra = {}) => Object.assign(
  { name: "جلاكسي شوكولاتة", price, quantity: 1, isTargetCompany: true, barcode: BARCODES[0] }, extra);
const otherBrandLine = (price) => ({ name: "ميلكي واي", price, quantity: 1, isTargetCompany: true, barcode: "5000000000001" });
const receipt = (lines, extra = {}) => Object.assign({
  campaignId: "E", submittedByUid: "u1", branch_id: "b1", chances_earned: 1,
  receipt_date: "04/11/2026", timestamp: new Date(NOW - 3600 * 1000), extracted_products: lines,
}, extra);
const check = (event, rec, extra = {}) => evaluateClaimEligibility(Object.assign({ event, receipt: rec, nowMs: NOW }, extra));

test("Cairo midnight handles winter and summer offsets", () => {
  assert.strictEqual(cairoMidnightMs(2026, 11, 2), FIRST);
  assert.strictEqual(cairoMidnightMs(2026, 7, 1), Date.UTC(2026, 5, 30, 21, 0));
  const w = campaignWindow(campaign());
  assert.strictEqual(w.opensAtMs, FIRST);
  assert.strictEqual(w.cutoffMs, Date.UTC(2026, 10, 7, 22, 0));
});

test("date window: receipt inside the window is eligible, end day is inclusive", () => {
  assert.strictEqual(check(campaign(), receipt([brandLine(160)])).ok, true);
  const lastDay = receipt([brandLine(160)], { receipt_date: "07/11/2026", timestamp: new Date(at("2026-11-07T21:59:00Z")) });
  assert.strictEqual(check(campaign(), lastDay).ok, true);
  const firstDay = receipt([brandLine(160)], { receipt_date: "2026/11/02", timestamp: new Date(at("2026-11-01T22:00:00Z")) });
  assert.strictEqual(check(campaign(), firstDay).ok, true);
});

test("date window: upload after the Cairo cutoff or before the start is rejected", () => {
  const late = receipt([brandLine(160)], { timestamp: new Date(at("2026-11-07T22:00:00Z")) });
  const lateVerdict = check(campaign(), late);
  assert.strictEqual(lateVerdict.code, REASONS.CAMPAIGN_ENDED);
  assert.match(lateVerdict.message, /7\/11\/2026/);
  const early = receipt([brandLine(160)], { timestamp: new Date(at("2026-11-01T21:59:00Z")) });
  assert.strictEqual(check(campaign(), early).code, REASONS.CAMPAIGN_NOT_STARTED);
});

test("date window: the claim time is used when the receipt has no upload timestamp", () => {
  const rec = receipt([brandLine(160)]);
  delete rec.timestamp;
  assert.strictEqual(check(campaign(), rec).ok, true);
  assert.strictEqual(check(campaign(), rec, { nowMs: at("2026-11-09T09:00:00Z") }).code, REASONS.CAMPAIGN_ENDED);
});

test("date window: printed purchase date outside the window is rejected", () => {
  const before = check(campaign(), receipt([brandLine(160)], { receipt_date: "30/10/2026" }));
  assert.strictEqual(before.code, REASONS.RECEIPT_DATE_OUTSIDE);
  assert.strictEqual(before.details.side, "before");
  const after = check(campaign(), receipt([brandLine(160)], { receipt_date: "٠٨/١١/٢٠٢٦" }));
  assert.strictEqual(after.code, REASONS.RECEIPT_DATE_OUTSIDE);
  assert.strictEqual(after.details.side, "after");
});

test("purchase date: ambiguous dd/mm vs mm/dd is accepted when one reading is inside; unreadable is not guessed", () => {
  const w = campaignWindow(campaign());
  assert.deepStrictEqual(receiptDayCandidates("03/11/2026"), [20261103, 20260311]);
  assert.strictEqual(purchaseDateVerdict("03/11/2026", w, NOW).status, "in");
  assert.strictEqual(purchaseDateVerdict("03/04/2026", w, NOW).status, "out");
  assert.strictEqual(purchaseDateVerdict("غير واضح", w, NOW).status, "unknown");
  assert.strictEqual(purchaseDateVerdict("", w, NOW).status, "unknown");
  assert.strictEqual(purchaseDateVerdict("04/11/2025", w, NOW).status, "in", "client heals a misread year");
});

test("inactive campaign is rejected", () => {
  const verdict = check(campaign({ isActive: false }), receipt([brandLine(160)]));
  assert.strictEqual(verdict.ok, false);
  assert.strictEqual(verdict.code, REASONS.CAMPAIGN_INACTIVE);
});

test("min spend counts only the campaign brand, never the invoice total or other brands", () => {
  const below = check(campaign(), receipt([brandLine(120), otherBrandLine(900)]));
  assert.strictEqual(below.code, REASONS.MIN_SPEND_NOT_MET);
  assert.strictEqual(below.details.required, 150);
  assert.strictEqual(below.details.counted, 120);
  assert.match(below.message, /120/);
  assert.strictEqual(check(campaign(), receipt([brandLine(150), otherBrandLine(900)])).ok, true);
  assert.strictEqual(check(campaign(), receipt([brandLine(160), otherBrandLine(5)])).serverUnits, 1);
});

test("min spend: a company-flagged line counts like on the page unless it is identifiably another product", () => {
  const flagged = (extra) => Object.assign({ name: "منظف متعدد الاستخدام", price: 70, quantity: 1, isTargetCompany: true, barcode: "" }, extra);
  assert.strictEqual(check(campaign(), receipt([brandLine(100), flagged()])).ok, true);
  const cases = [
    [flagged({ isTargetCompany: false }), "not flagged"],
    [flagged({ barcode: "5000000000001" }), "barcode outside a barcode-only campaign"],
    [flagged({ name: "كلوركس مبيض" }), "names another brand"],
    [flagged({ name: "؟" }), "no readable name"],
  ];
  for (const [line, why] of cases) {
    const verdict = check(campaign(), receipt([brandLine(100), line]));
    assert.strictEqual(verdict.code, REASONS.MIN_SPEND_NOT_MET, why);
    assert.strictEqual(verdict.details.counted, 100, why);
  }
});

test("min spend: campaign-level minimum without rules uses the company flag only when no product is named", () => {
  const ev = campaign({ promotionalRules: [], minimumSpend: 200 });
  const lines = [{ name: "صنف الشركة", price: 150, quantity: 1, isTargetCompany: true },
    { name: "صنف آخر", price: 500, quantity: 1, isTargetCompany: false }];
  assert.strictEqual(check(ev, receipt(lines)).code, REASONS.MIN_SPEND_NOT_MET);
  lines[0].price = 200;
  assert.strictEqual(check(ev, receipt(lines)).ok, true);
});

test("missing required product", () => {
  const verdict = check(campaign(), receipt([otherBrandLine(900)]));
  assert.strictEqual(verdict.code, REASONS.REQUIRED_PRODUCTS_MISSING);
  const named = campaign({ promotionalRules: [], requiredProducts: ["كلوريل"], minimumSpend: 0 });
  assert.strictEqual(check(named, receipt([{ name: "مبيض كلوركس", price: 40, quantity: 1, isTargetCompany: true }])).code,
    REASONS.REQUIRED_PRODUCTS_MISSING);
  assert.strictEqual(check(named, receipt([{ name: "مبيض كلوريل 1 لتر", price: 40, quantity: 1 }])).ok, true);
});

test("a campaign with no verifiable condition is left alone, lines missing or not", () => {
  const plain = { companySlug: "1", isActive: true };
  assert.deepStrictEqual(check(plain, { campaignId: "E" }), { ok: true, serverUnits: null });
});

test("missing invoice lines are refused for a campaign with conditions, except for a server-created receipt", () => {
  const rec = receipt([]);
  assert.strictEqual(check(campaign(), rec).code, REASONS.RECEIPT_LINES_MISSING);
  assert.strictEqual(check(campaign(), rec, { system: true }).ok, true);
  assert.strictEqual(check(campaign({ spendLadderMode: "consuming" }), rec).ok, true);
});

test("gift count: remainder offer applies even when the campaign hands out one gift per invoice", () => {
  const single = campaign({ allowMultipleChances: false, maxChancesPerReceipt: 1 });
  assert.strictEqual(check(single, receipt([brandLine(618)])).serverUnits, 2);
  assert.strictEqual(check(single, receipt([brandLine(309.5)])).serverUnits, 1);
  const multi = campaign({ allowMultipleChances: true, maxChancesPerReceipt: 3 });
  assert.strictEqual(check(multi, receipt([brandLine(1500)])).serverUnits, 4);
});

test("gift count: only the campaign brand earns offers, ambiguous lines add nothing", () => {
  const single = campaign();
  const verdict = check(single, receipt([brandLine(160), otherBrandLine(2000), { name: "؟", price: 900, quantity: 1, isTargetCompany: true }]));
  assert.strictEqual(verdict.serverUnits, 1);
});

test("gift count: rules the ladder cannot read still get a per-rule upper bound", () => {
  const rule = { id: "r", conditionType: "by_spend", minSpend: 100, requiredBrands: ["جلاكسي"], linkedGifts: [{ giftId: "g", giftName: "g", quantity: 1 }] };
  const ev = campaign({ promotionalRules: [rule], allowMultipleChances: true, maxChancesPerReceipt: 0 });
  assert.strictEqual(check(ev, receipt([{ name: "جلاكسي لوز", price: 260, quantity: 1 }])).serverUnits, 2);
  assert.strictEqual(check(ev, receipt([{ name: "جلاكسي لوز", price: 60, quantity: 1 }])).code, REASONS.MIN_SPEND_NOT_MET);
  const off = campaign({ promotionalRules: [rule], allowMultipleChances: false });
  assert.strictEqual(check(off, receipt([{ name: "جلاكسي لوز", price: 260, quantity: 1 }])).serverUnits, 1);
});

test("gift count: a combo rule is not guessed (no opinion), presence is still enforced", () => {
  const combo = { id: "c", conditionType: "combo_spend", minSpend: 100, matchMode: "AND", requiredBrands: ["جلاكسي", "ميلكي"], linkedGifts: [] };
  const ev = campaign({ promotionalRules: [combo] });
  const verdict = check(ev, receipt([{ name: "جلاكسي لوز", price: 120, quantity: 1 }]));
  assert.strictEqual(verdict.ok, true);
  assert.strictEqual(verdict.serverUnits, null);
  assert.strictEqual(check(ev, receipt([{ name: "سكر", price: 120, quantity: 1 }])).code, REASONS.REQUIRED_PRODUCTS_MISSING);
});

function fakeDb(docs) {
  const store = new Map(Object.entries(docs).map(([k, v]) => [k, structuredClone(v)]));
  const ref = (path) => ({ path, id: path.split("/").pop() });
  const snapOf = (r) => ({ exists: store.has(r.path), data: () => store.get(r.path), id: r.id, ref: r });
  const collection = (name) => {
    const q = { doc: (id) => ref(`${name}/${id}`), where: () => q, _query: true, _run: () => [] };
    return q;
  };
  const writes = [];
  return {
    store, collection, writes,
    runTransaction: async (fn) => fn({
      get: async (r) => (r._query ? { docs: r._run() } : snapOf(r)),
      update: (r, d) => { writes.push(r.path); store.set(r.path, Object.assign({}, store.get(r.path), d)); },
      set: (r, d) => { writes.push(r.path); store.set(r.path, Object.assign({}, store.get(r.path) || {}, d)); },
    }),
  };
}
const actor = { anonymous: true, uid: "u1" };
const rem = (db, i) => db.store.get("events/E").allocatedPrizes[i].remainingQuantity;
const claim = (db, decrements, extra = {}) => applyCampaignPrizeClaim(db, Object.assign({
  eventId: "E", receiptId: "r1", actor, nowMs: NOW, decrements, receiptPatch: { game_played: true },
}, extra));
const rejects = async (promise, reason) => {
  await assert.rejects(promise, (err) => {
    assert.strictEqual(err.code, "failed-precondition");
    assert.strictEqual(err.details.reason, reason);
    return true;
  });
};

test("claim: rejected receipt changes nothing (no stock, no receipt write)", async () => {
  const cases = [
    [campaign({ isActive: false }), receipt([brandLine(160)]), REASONS.CAMPAIGN_INACTIVE],
    [campaign(), receipt([brandLine(160)], { timestamp: new Date(at("2026-11-08T10:00:00Z")) }), REASONS.CAMPAIGN_ENDED],
    [campaign(), receipt([brandLine(160)], { receipt_date: "20/10/2026" }), REASONS.RECEIPT_DATE_OUTSIDE],
    [campaign(), receipt([brandLine(100), otherBrandLine(900)]), REASONS.MIN_SPEND_NOT_MET],
    [campaign(), receipt([otherBrandLine(900)]), REASONS.REQUIRED_PRODUCTS_MISSING],
    [campaign({ spendLadderMode: "consuming" }), receipt([brandLine(160)], { receipt_date: "20/10/2026" }), REASONS.RECEIPT_DATE_OUTSIDE],
  ];
  for (const [ev, rec, reason] of cases) {
    const db = fakeDb({ "events/E": ev, "receipts_transactions/r1": rec });
    const before = JSON.stringify([...db.store]);
    await rejects(claim(db, [{ prizeIdentifier: "g_t150", branchId: "b1", count: 1 }]), reason);
    assert.strictEqual(JSON.stringify([...db.store]), before, reason);
    assert.deepStrictEqual(db.writes, [], reason);
  }
});

test("claim: eligible receipt decrements stock once", async () => {
  const db = fakeDb({ "events/E": campaign(), "receipts_transactions/r1": receipt([brandLine(160)]) });
  const out = await claim(db, [{ prizeIdentifier: "g_t150", branchId: "b1", count: 1 }]);
  assert.strictEqual(out.ok, true);
  assert.strictEqual(rem(db, 0), 9);
});

test("claim: client count above the server count is cut to the server count, silently", async () => {
  const db = fakeDb({ "events/E": campaign(), "receipts_transactions/r1": receipt([brandLine(160)], { chances_earned: 9 }) });
  const out = await claim(db, [{ prizeIdentifier: "g_t150", branchId: "b1", count: 3 }]);
  assert.strictEqual(out.trimmed, true);
  assert.strictEqual(out.grantedUnits, 1);
  assert.strictEqual(rem(db, 0), 9);
});

test("claim: single-gift campaign still honours the remainder offer (618 = 450 + 150)", async () => {
  const ev = campaign({ allowMultipleChances: false, maxChancesPerReceipt: 1 });
  const db = fakeDb({ "events/E": ev, "receipts_transactions/r1": receipt([brandLine(618)], { chances_earned: 9 }) });
  const out = await claim(db, [
    { prizeIdentifier: "g_t450", branchId: "b1", count: 1, unitValue: 450 },
    { prizeIdentifier: "g_t150", branchId: "b1", count: 2, unitValue: 150 },
  ]);
  assert.strictEqual(out.trimmed, true);
  assert.strictEqual(out.grantedUnits, 2);
  assert.strictEqual(rem(db, 2), 9);
  assert.strictEqual(rem(db, 1), 10);
  assert.strictEqual(rem(db, 0), 9);
});

test("claim: a receipt that earns 0 gifts is rejected even when its ladder shape is not exclusive-readable", async () => {
  const rule = { id: "q", conditionType: "by_quantity", minQuantity: 3, selectedProductNames: ["جلاكسي شوكولاتة"], linkedGifts: [] };
  const ev = campaign({ promotionalRules: [rule], allowMultipleChances: true });
  const db = fakeDb({ "events/E": ev, "receipts_transactions/r1": receipt([brandLine(40)]) });
  await rejects(claim(db, [{ prizeIdentifier: "g_t150", branchId: "b1", count: 1 }]), REASONS.NO_ELIGIBLE_GIFT);
  assert.deepStrictEqual(db.writes, []);
});

test("claim: staff keep their manual override; a rep retry of an already claimed receipt still says already claimed", async () => {
  const staffDb = fakeDb({ "events/E": campaign({ isActive: false }), "receipts_transactions/r1": receipt([otherBrandLine(10)]) });
  const out = await claim(staffDb, [{ prizeIdentifier: "g_t150", branchId: "b1", count: 1 }], { actor: { staff: true, uid: "s" } });
  assert.strictEqual(out.ok, true);

  const claimed = receipt([brandLine(160)], { game_played: true, remaining_chances: 0, claimed_gifts: [{ giftId: "g_t150", quantity: 1 }] });
  const db = fakeDb({ "events/E": campaign({ endDate: new Date(at("2026-11-03T00:00:00Z")) }), "receipts_transactions/r1": claimed });
  await assert.rejects(claim(db, [{ prizeIdentifier: "g_t150", branchId: "b1", count: 1 }]), /already claimed/);
});
