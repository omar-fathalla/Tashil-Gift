const test = require("node:test");
const assert = require("node:assert");
const { REASONS, evaluateClaimEligibility } = require("../campaign_eligibility");
const { namesBrandOutsideCampaign } = require("../known_brands");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;

// Edku (ADCO) replay: the page's brand total was 384 and the server counted
// 329 against a 330 minimum, because «جالسى ملمع زجاج» (an OCR spelling of
// جلاسي that the page flagged as the company's) matched no brand token.
const NOW = Date.parse("2026-11-04T09:00:00Z");
const SPEED = "6221035002171";
const GLASSY = "6221035004120";
const brandRule = { id: "adco330", conditionType: "by_spend", minSpend: 330, requiredBrands: ["سبيد", "جلاسي"],
  linkedGifts: [{ giftId: "g330", giftName: "قسيمة 50", quantity: 1 }] };
const barcodeRule = { id: "adco330", conditionType: "by_spend", minSpend: 330, selectedBarcodes: [SPEED, GLASSY],
  selectedProductNames: ["سبيد منظف ارضيات 1 لتر", "جلاسي منظف زجاج 500 مل"],
  linkedGifts: [{ giftId: "g330", giftName: "قسيمة 50", quantity: 1 }] };
const edku = (rule, extra = {}) => Object.assign({
  eventName: "عرض أدكو - فتح الله", targetCompany: "أدكو", companySlug: "adco", isActive: true,
  startDate: new Date(Date.parse("2026-11-01T22:00:00Z")), endDate: new Date(Date.parse("2026-11-10T22:00:00Z")),
  allowMultipleChances: false, maxChancesPerReceipt: 1, balanceMode: "campaign_only", promotionalRules: [rule],
  allocatedPrizes: [{ giftId: "g330", name: "قسيمة 50", giftType: "voucher", unitValue: 50, branchId: "b1", remainingQuantity: 5 }],
}, extra);

const explicitLines = () => [
  { name: "سبيد منظف ارضيات 1 لتر", price: 65, quantity: 3, isTargetCompany: true, barcode: SPEED },
  { name: "جلاسي منظف زجاج 500 مل", price: 134, quantity: 1, isTargetCompany: true, barcode: GLASSY },
];
const galsy = (extra = {}) => Object.assign({ name: "جالسى ملمع زجاج", price: 55, quantity: 1, isTargetCompany: true, barcode: "" }, extra);
const invoiceNoise = () => [
  { name: "سكر الاسرة 1 كيلو", price: 38, quantity: 2, isTargetCompany: false, barcode: "6223000000011" },
  { name: "كلوركس مبيض 1 لتر", price: 42, quantity: 1, isTargetCompany: false, barcode: "6223000000028" },
  { name: "ارز الضحى 5 كيلو", price: 210, quantity: 1, isTargetCompany: false, barcode: "6223000000035" },
];
const receipt = (lines) => ({
  campaignId: "E", submittedByUid: "u1", branch_id: "b1", chances_earned: 1, receipt_date: "04/11/2026",
  timestamp: new Date(NOW - 3600 * 1000), target_company_total: 384, total_value: 712, extracted_products: lines,
});
const check = (event, lines) => evaluateClaimEligibility({ event, receipt: receipt(lines), nowMs: NOW });

for (const [label, rule] of [["brand-scoped rule", brandRule], ["barcode-scoped rule", barcodeRule]]) {
  test(`Edku, ${label}: the page-flagged «جالسى ملمع زجاج» counts, so 384 meets the 330 minimum`, () => {
    const lines = explicitLines().concat([galsy()], invoiceNoise());
    const verdict = check(edku(rule), lines);
    assert.deepStrictEqual(verdict, { ok: true, serverUnits: 1 });

    const without = check(edku(rule), explicitLines().concat(invoiceNoise()));
    assert.strictEqual(without.code, REASONS.MIN_SPEND_NOT_MET);
    assert.strictEqual(without.details.counted, 329);
    assert.strictEqual(without.details.required, 330);
  });

  test(`Edku, ${label}: never other brands, unflagged lines, or the invoice total`, () => {
    const cases = [
      [galsy({ isTargetCompany: false }), "the page did not flag it: not guessed into the campaign"],
      [galsy({ name: "كلوريل مبيض 1 لتر" }), "another ADCO brand the campaign does not cover"],
      [galsy({ name: "كلوركس جل 1 لتر" }), "a competitor brand"],
    ];
    for (const [line, why] of cases) {
      const verdict = check(edku(rule), explicitLines().concat([line], invoiceNoise()));
      assert.strictEqual(verdict.code, REASONS.MIN_SPEND_NOT_MET, why);
      assert.strictEqual(verdict.details.counted, 329, why);
    }
  });
}

test("Edku, barcode-only campaign: a flagged line with a barcode outside the campaign is another product", () => {
  const rule = Object.assign({}, barcodeRule, { selectedProductNames: [] });
  const verdict = check(edku(rule), explicitLines().concat([galsy({ barcode: "6221035009999" })]));
  assert.strictEqual(verdict.code, REASONS.MIN_SPEND_NOT_MET);
  assert.strictEqual(verdict.details.counted, 329);
});

test("Edku, consuming ladder: the page counts explicit lines only, so the server does too", () => {
  const verdict = check(edku(brandRule, { spendLadderMode: "consuming" }), explicitLines().concat([galsy()]));
  assert.strictEqual(verdict.code, REASONS.MIN_SPEND_NOT_MET);
});

test("Edku, a company-wide brand in the scope covers that company's brands", () => {
  const rule = Object.assign({}, brandRule, { requiredBrands: ["أدكو"] });
  const lines = [{ name: "أدكو سبيد 1 لتر", price: 300, quantity: 1, isTargetCompany: true }, galsy({ name: "كلوريل مبيض" })];
  assert.strictEqual(check(edku(rule), lines).ok, true);
});

test("namesBrandOutsideCampaign matches whole words only", () => {
  assert.strictEqual(namesBrandOutsideCampaign("كلوريل مبيض", ["سبيد", "جلاسي"]), true);
  assert.strictEqual(namesBrandOutsideCampaign("جالسى ملمع زجاج", ["سبيد", "جلاسي"]), false);
  assert.strictEqual(namesBrandOutsideCampaign("جلاسي ملمع", ["جلاسي منظف زجاج 500 مل"]), false);
  assert.strictEqual(namesBrandOutsideCampaign("مكسرات واكسب", []), false);
});

function fakeDb(docs) {
  const store = new Map(Object.entries(docs).map(([k, v]) => [k, structuredClone(v)]));
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

test("Edku claim: the receipt the page accepted now claims once instead of min_spend_not_met", async () => {
  const db = fakeDb({
    "events/E": edku(brandRule),
    "receipts_transactions/r1": receipt(explicitLines().concat([galsy()], invoiceNoise())),
  });
  const out = await applyCampaignPrizeClaim(db, {
    eventId: "E", receiptId: "r1", actor: { anonymous: true, uid: "u1" }, nowMs: NOW,
    decrements: [{ prizeIdentifier: "g330", branchId: "b1", count: 1 }], receiptPatch: { game_played: true },
  });
  assert.strictEqual(out.ok, true);
  assert.strictEqual(db.store.get("events/E").allocatedPrizes[0].remainingQuantity, 4);
});
