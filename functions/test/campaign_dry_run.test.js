/**
 * C-05 dry run: same verdicts as evaluateClaimEligibility, staff only, and the
 * handler never writes (the fake db only implements get()).
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const { dryRunCampaignEligibilityHandler } = require("../campaign_dry_run");
const { evaluateClaimEligibility } = require("../campaign_eligibility");

const DAY = 24 * 3600 * 1000;
const NOW = Date.UTC(2026, 10, 25, 9, 0, 0); // 25 Nov 2026 11:00 Cairo

const admin = { uid: "a1", token: { role: "admin", firebase: { sign_in_provider: "password" } } };

function fakeDb(docs = {}) {
  const calls = [];
  const db = {
    calls,
    collection(name) {
      return {
        doc(id) {
          const key = `${name}/${id}`;
          const ref = {
            get: async () => { calls.push(["get", key]); return { exists: key in docs, data: () => docs[key] }; },
          };
          // Any write method would be a bug: make it loud.
          for (const m of ["set", "update", "delete", "create"]) {
            ref[m] = () => { calls.push([m, key]); throw new Error(`write ${m} ${key}`); };
          }
          return ref;
        },
        add: () => { calls.push(["add", name]); throw new Error(`write add ${name}`); },
      };
    },
    runTransaction: () => { calls.push(["tx"]); throw new Error("transaction"); },
    batch: () => { calls.push(["batch"]); throw new Error("batch"); },
  };
  return db;
}

const campaign = (over = {}) => ({
  eventName: "Dry", companySlug: "acme", isActive: false,
  startDate: NOW - 5 * DAY, endDate: NOW + 5 * DAY,
  minimumSpend: 200, requiredProducts: ["كادبري"], promotionalRules: [],
  ...over,
});
const line = (price, over = {}) => ({ name: "كادبري ديري ميلك", price, quantity: 1, isTargetCompany: true, ...over });

test("passes a receipt that meets the conditions, even for an inactive draft, and writes nothing", async () => {
  const db = fakeDb();
  const res = await dryRunCampaignEligibilityHandler(db, {
    auth: admin, data: { campaign: campaign(), receipt: { receipt_date: "24/11/2026", extracted_products: [line(250)] } },
  }, NOW);
  assert.equal(res.dryRun, true);
  assert.equal(res.ok, true);
  assert.equal(res.campaignActive, false);
  assert.deepEqual(db.calls, []);
});

test("returns the same reason and Arabic message as the claim check", async () => {
  const c = campaign();
  const r = { receipt_date: "24/11/2026", extracted_products: [line(150)] };
  const res = await dryRunCampaignEligibilityHandler(fakeDb(), { auth: admin, data: { campaign: c, receipt: r } }, NOW);
  const direct = evaluateClaimEligibility({ event: { ...c, isActive: true }, receipt: { ...r, timestamp: NOW }, nowMs: NOW });
  assert.equal(res.ok, false);
  assert.equal(res.code, "min_spend_not_met");
  assert.equal(res.code, direct.code);
  assert.equal(res.message, direct.message);
});

test("receipt date outside the campaign is rejected", async () => {
  const res = await dryRunCampaignEligibilityHandler(fakeDb(), {
    auth: admin, data: { campaign: campaign(), receipt: { receipt_date: "01/10/2026", extracted_products: [line(250)] } },
  }, NOW);
  assert.equal(res.ok, false);
  assert.equal(res.code, "receipt_date_outside_campaign");
});

test("missing campaign product is rejected", async () => {
  const res = await dryRunCampaignEligibilityHandler(fakeDb(), {
    auth: admin, data: { campaign: campaign(), receipt: { extracted_products: [line(500, { name: "شيبسي" , isTargetCompany: false })] } },
  }, NOW);
  assert.equal(res.code, "required_products_missing");
});

test("reads a stored receipt and a stored campaign without writing", async () => {
  const db = fakeDb({
    "events/E1": campaign({ isActive: true }),
    "receipts_transactions/R1": { receipt_date: "24/11/2026", timestamp: NOW - DAY, extracted_products: [line(300)], game_played: false },
  });
  const res = await dryRunCampaignEligibilityHandler(db, { auth: admin, data: { eventId: "E1", receiptId: "R1" } }, NOW);
  assert.equal(res.ok, true);
  assert.equal(res.receiptSource, "stored");
  assert.equal(res.campaignActive, true);
  assert.deepEqual(db.calls.map((c) => c[0]), ["get", "get"]);
});

test("only staff: anonymous reps, partners and signed-out callers are refused", async () => {
  const data = { campaign: campaign(), receipt: { extracted_products: [line(250)] } };
  for (const auth of [
    null,
    { uid: "r", token: { firebase: { sign_in_provider: "anonymous" } } },
    { uid: "p", token: { role: "partner", firebase: { sign_in_provider: "password" } } },
    { uid: "x", token: { role: "admin", firebase: { sign_in_provider: "anonymous" } } },
  ]) {
    await assert.rejects(() => dryRunCampaignEligibilityHandler(fakeDb(), { auth, data }, NOW), (e) => e.code === "permission-denied");
  }
});

test("rejects missing input and too many lines", async () => {
  await assert.rejects(() => dryRunCampaignEligibilityHandler(fakeDb(), { auth: admin, data: { receipt: {} } }, NOW), (e) => e.code === "invalid-argument");
  await assert.rejects(() => dryRunCampaignEligibilityHandler(fakeDb(), { auth: admin, data: { campaign: campaign() } }, NOW), (e) => e.code === "invalid-argument");
  const many = Array.from({ length: 201 }, () => line(1));
  await assert.rejects(() => dryRunCampaignEligibilityHandler(fakeDb(), { auth: admin, data: { campaign: campaign(), receipt: { extracted_products: many } } }, NOW), (e) => e.code === "invalid-argument");
});

test("exclusive spend tiers report the gift count the claim would allow", async () => {
  const c = campaign({
    minimumSpend: 0, requiredProducts: [],
    promotionalRules: [{ id: "r1", conditionType: "by_spend", minSpend: 100, requiredBrands: ["كادبري"], triggerProduct: "كادبري" }],
    allowMultipleChances: true, maxChancesPerReceipt: 5,
  });
  const res = await dryRunCampaignEligibilityHandler(fakeDb(), {
    auth: admin, data: { campaign: c, receipt: { receipt_date: "24/11/2026", extracted_products: [line(320)] } },
  }, NOW);
  const direct = evaluateClaimEligibility({ event: { ...c, isActive: true }, receipt: { receipt_date: "24/11/2026", timestamp: NOW, extracted_products: [line(320)] }, nowMs: NOW });
  assert.equal(res.ok, direct.ok);
  assert.equal(res.serverUnits, direct.serverUnits);
});
