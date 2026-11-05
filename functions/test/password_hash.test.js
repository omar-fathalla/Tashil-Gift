const test = require("node:test");
const assert = require("node:assert");
const { hashPassword, verifyPassword, isPasswordHash, passwordMatches, DEFAULT_ITERATIONS } = require("../password_hash");

test("pbkdf2 matches RFC 6070 SHA-256 c=1", () => {
  const stored = hashPassword("password", { iterations: 1, salt: Buffer.from("salt") });
  assert.strictEqual(
    stored,
    "pbkdf2-sha256$1$c2FsdA$Eg-2z_z4syxD5yJSVsT4N6hlSMkszDVICAWYfLcL4Xs",
  );
  assert.strictEqual(verifyPassword(stored, "password"), true);
  assert.strictEqual(verifyPassword(stored, "password1"), false);
});

test("hash verifies and plaintext is legacy", () => {
  const stored = hashPassword("field-secret", { iterations: 1000 });
  assert.strictEqual(isPasswordHash(stored), true);
  assert.deepStrictEqual(passwordMatches(stored, "field-secret"), { ok: true, legacy: false });
  assert.deepStrictEqual(passwordMatches(stored, "other"), { ok: false, legacy: false });
  assert.deepStrictEqual(passwordMatches("plain-secret", "plain-secret"), { ok: true, legacy: true });
  assert.deepStrictEqual(passwordMatches("plain-secret", "nope"), { ok: false, legacy: true });
  assert.deepStrictEqual(passwordMatches("", "x"), { ok: false, legacy: false });
});

test("default iteration count is the production cost", () => {
  assert.strictEqual(DEFAULT_ITERATIONS, 210000);
});
