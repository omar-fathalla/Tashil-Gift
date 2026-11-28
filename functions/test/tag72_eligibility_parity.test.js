// TAG-72: the server (evaluateClaimEligibility) and the upload page
// (PromotionalRuleMatcher, test/tag72_eligibility_parity_test.dart) must agree
// on the same fixtures: test/fixtures/eligibility_parity.json.
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs");
const { evaluateClaimEligibility } = require("../campaign_eligibility");

const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "test", "fixtures", "eligibility_parity.json"), "utf8"));
const NOW = Date.UTC(2026, 10, 28, 10, 0, 0);

for (const c of fixtures.cases) {
  test(c.name, () => {
    const event = Object.assign({ isActive: true, allowMultipleChances: false, spendLadderMode: "exclusive" }, c.event);
    const receipt = { extracted_products: c.receipt, receipt_date: "2026-11-28", timestamp: NOW };
    const r = evaluateClaimEligibility({ event, receipt, nowMs: NOW });
    assert.equal(r.ok, c.expected.eligible, `${r.code || ""} ${r.message || ""}`);
    if (r.ok && c.expected.units != null && r.serverUnits != null) {
      assert.equal(r.serverUnits, c.expected.units);
    }
  });
}
