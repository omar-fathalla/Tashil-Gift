const test = require("node:test");
const assert = require("node:assert");
const { _test } = require("../partner_portal");
const { verifyCredentials, publicInfo, deterministicPin, defaults } = _test;

test("pin matches dart2js output", () => {
  assert.strictEqual(deterministicPin("abc", "BM2026"), "1656");
  assert.strictEqual(deterministicPin("583:Ev_XyZ12", "CAMP2026"), "8960");
});

const company = { name: "Co", logoUrl: "https://x/l.png", brandManagerUsername: "Boss", brandManagerPassword: "p1", brandCredentialVersion: 4, agencyOpsUsername: "ops", agencyOpsPassword: "p2" };

test("brand login: case-insensitive user, exact password", () => {
  const r = verifyCredentials({ slug: "co", role: "brand_manager", username: " boss ", password: "p1", company });
  assert.strictEqual(r.credentialVersion, 4);
  assert.strictEqual(r.username, "Boss");
  assert.strictEqual(verifyCredentials({ slug: "co", role: "brand_manager", username: "boss", password: "P1", company }).error, "invalid_brand");
});

test("role isolation", () => {
  assert.strictEqual(verifyCredentials({ slug: "co", role: "brand_manager", username: "ops", password: "p2", company }).error, "agency_creds_on_brand");
  assert.strictEqual(verifyCredentials({ slug: "co", role: "agency_ops", username: "boss", password: "p1", company }).error, "brand_creds_on_agency");
});

test("agency company + campaign tiers", () => {
  assert.strictEqual(verifyCredentials({ slug: "co", role: "agency_ops", username: "ops", password: "p2", company }).isCampaignTier, false);
  const ev = { hasCustomAgencyCredentials: true, customAgencyUsername: "camp", customAgencyPassword: "p3", customAgencyCredentialVersion: 2 };
  const r = verifyCredentials({ slug: "co", role: "agency_ops", eventId: "e1", event: ev, username: "camp", password: "p3", company });
  assert.deepStrictEqual([r.isCampaignTier, r.lockedEventId, r.credentialVersion], [true, "e1", 2]);
  assert.strictEqual(verifyCredentials({ slug: "co", role: "agency_ops", eventId: "e1", event: ev, username: "ops", password: "p2", company }).error, "campaign_requires_custom");
  const r2 = verifyCredentials({ slug: "co", role: "agency_ops", username: "camp", password: "p3", company, companyEvents: [{ id: "e1", data: ev }] });
  assert.strictEqual(r2.lockedEventId, "e1");
});

test("defaults used only when fields empty", () => {
  const r = verifyCredentials({ slug: "zz", role: "brand_manager", username: defaults.brandUser("zz"), password: defaults.brandPass("zz"), company: {} });
  assert.ok(!r.error);
  assert.strictEqual(verifyCredentials({ slug: "co", role: "brand_manager", username: defaults.brandUser("co"), password: defaults.brandPass("co"), company }).error, "invalid_brand");
});

test("publicInfo never leaks credentials", () => {
  const info = publicInfo({ slug: "co", eventId: null, event: null, company });
  const s = JSON.stringify(info);
  for (const bad of ["p1", "p2", "Boss", "Password", "Username"]) assert.ok(!s.includes(bad), bad);
  assert.strictEqual(info.companyName, "Co");
  assert.strictEqual(info.logoUrl, "https://x/l.png");
});
