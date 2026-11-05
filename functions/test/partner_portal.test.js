const test = require("node:test");
const assert = require("node:assert");
const { _test } = require("../partner_portal");
const { verifyCredentials, publicInfo, deterministicPin, defaults, buildRepCredentialWrite, portalTokenSpec } = _test;
const { hashPassword, verifyPassword } = require("../password_hash");

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

test("portal token claims", () => {
  const a = portalTokenSpec("583", { role: "brand_manager", username: "Dina", credentialVersion: 4, isCampaignTier: false });
  assert.deepStrictEqual(a.claims, { role: "partner", companySlug: "583", partnerAccess: "read", portalRole: "brand_manager", credVersion: 4 });
  assert.ok(a.uid.startsWith("portal_") && a.uid.length <= 128);
  const b = portalTokenSpec("583", { role: "agency_ops", username: "x", credentialVersion: 2, isCampaignTier: true, lockedEventId: "e1" });
  assert.strictEqual(b.claims.partnerAccess, "ops");
  assert.strictEqual(b.claims.lockedEventId, "e1");
  assert.notStrictEqual(a.uid, b.uid);
  const rep = portalTokenSpec("583", { role: "rep_uploader", username: "rep_583", credentialVersion: 3, isCampaignTier: false });
  assert.strictEqual(rep.claims.partnerAccess, "upload");
  assert.strictEqual(rep.claims.portalRole, "rep_uploader");
  assert.strictEqual(rep.claims.credVersion, 3);
  assert.notStrictEqual(rep.uid, a.uid);
});

test("rep_uploader: hash success, wrong password, agency password rejected, version", () => {
  const hash = hashPassword("rep-secret", { iterations: 1000 });
  const co = {
    ...company,
    repUploaderUsername: "rep_co",
    repUploaderPasswordHash: hash,
    repUploaderCredentialVersion: 5,
  };
  const ok = verifyCredentials({ slug: "co", role: "rep_uploader", username: "REP_CO", password: "rep-secret", company: co });
  assert.strictEqual(ok.error, undefined);
  assert.strictEqual(ok.credentialVersion, 5);
  assert.strictEqual(ok.role, "rep_uploader");
  assert.strictEqual(ok.legacyUpgrade, null);
  const bad = verifyCredentials({ slug: "co", role: "rep_uploader", username: "rep_co", password: "nope", company: co });
  assert.strictEqual(bad.error, "invalid_rep");
  const agencyOnRep = verifyCredentials({ slug: "co", role: "rep_uploader", username: "ops", password: "p2", company: co });
  assert.strictEqual(agencyOnRep.error, "partner_creds_on_rep");
  const repOnAgency = verifyCredentials({ slug: "co", role: "agency_ops", username: "rep_co", password: "rep-secret", company: co });
  assert.strictEqual(repOnAgency.error, "rep_creds_on_partner");
  const missing = verifyCredentials({ slug: "co", role: "rep_uploader", username: "rep_co", password: "rep-secret", company });
  assert.strictEqual(missing.error, "rep_not_configured");
});

test("rotating the rep password bumps credentialVersion", () => {
  const first = buildRepCredentialWrite({ username: "rep_co", password: "first-secret", current: {} });
  assert.strictEqual(first.credentialVersion, 1);
  assert.ok(verifyPassword(first.update.repUploaderPasswordHash, "first-secret"));
  assert.ok(!("repUploaderPassword" in first.update));
  const rotated = buildRepCredentialWrite({
    username: "rep_co",
    password: "second-secret",
    current: { repUploaderUsername: "rep_co", repUploaderPasswordHash: first.update.repUploaderPasswordHash, repUploaderCredentialVersion: 1 },
  });
  assert.strictEqual(rotated.credentialVersion, 2);
  assert.ok(verifyPassword(rotated.update.repUploaderPasswordHash, "second-secret"));
  assert.ok(!verifyPassword(rotated.update.repUploaderPasswordHash, "first-secret"));
  const kept = buildRepCredentialWrite({
    username: "rep_co",
    password: "",
    current: { repUploaderUsername: "rep_co", repUploaderPasswordHash: first.update.repUploaderPasswordHash, repUploaderCredentialVersion: 2 },
  });
  assert.strictEqual(kept.credentialVersion, 2);
  assert.ok(!("repUploaderPasswordHash" in kept.update));
});

test("legacy plaintext partner password verifies and asks for a hash upgrade", () => {
  const r = verifyCredentials({ slug: "co", role: "brand_manager", username: "Boss", password: "p1", company });
  assert.strictEqual(r.legacyUpgrade.field, "brandManagerPassword");
  assert.strictEqual(r.legacyUpgrade.scope, "company");
  const hashed = hashPassword("p1", { iterations: 1000 });
  const upgraded = { ...company, brandManagerPassword: hashed };
  const r2 = verifyCredentials({ slug: "co", role: "brand_manager", username: "Boss", password: "p1", company: upgraded });
  assert.strictEqual(r2.legacyUpgrade, null);
  assert.strictEqual(r2.credentialVersion, 4);
});

test("publicInfo exposes rep version only, never the hash or password", () => {
  const hash = hashPassword("rep-secret", { iterations: 1000 });
  const co = { ...company, repUploaderUsername: "rep_co", repUploaderPasswordHash: hash, repUploaderCredentialVersion: 5 };
  const info = publicInfo({ slug: "co", eventId: null, event: null, company: co });
  const s = JSON.stringify(info);
  assert.ok(!s.includes("rep-secret"), "password leaked");
  assert.ok(!s.includes(hash), "hash leaked");
  assert.ok(!s.includes("rep_co"), "username leaked");
  assert.strictEqual(info.repUploaderConfigured, true);
  assert.strictEqual(info.repUploaderCredentialVersion, 5);
  assert.strictEqual(publicInfo({ slug: "co", eventId: null, event: null, company }).repUploaderConfigured, false);
});
