/**
 * Password hashing for portal credentials.
 *
 * Stored form: pbkdf2-sha256$<iterations>$<saltB64url>$<hashB64url>
 * Plaintext partner fields (legacy) still verify, and a successful match is
 * marked legacy so the caller can replace the field with a hash. The
 * plaintext is never logged.
 */
const crypto = require("node:crypto");

const PREFIX = "pbkdf2-sha256";
const DEFAULT_ITERATIONS = 210000;
const DK_LEN = 32;
const SALT_LEN = 16;
const MAX_ITERATIONS = 2000000;

function b64url(buf) {
  return Buffer.from(buf).toString("base64url");
}

function fromB64url(s) {
  try {
    return Buffer.from(String(s), "base64url");
  } catch (_) {
    return null;
  }
}

function isPasswordHash(value) {
  return typeof value === "string" && value.startsWith(`${PREFIX}$`);
}

function hashPassword(password, { iterations = DEFAULT_ITERATIONS, salt } = {}) {
  const iter = Number(iterations);
  if (!Number.isInteger(iter) || iter < 1 || iter > MAX_ITERATIONS) {
    throw new Error("invalid_iterations");
  }
  const secret = password == null ? "" : String(password);
  const saltBuf = salt ? Buffer.from(salt) : crypto.randomBytes(SALT_LEN);
  const dk = crypto.pbkdf2Sync(secret, saltBuf, iter, DK_LEN, "sha256");
  return `${PREFIX}$${iter}$${b64url(saltBuf)}$${b64url(dk)}`;
}

function verifyPassword(stored, password) {
  if (!isPasswordHash(stored)) return false;
  const parts = String(stored).split("$");
  if (parts.length !== 4 || parts[0] !== PREFIX) return false;
  const iter = Number(parts[1]);
  if (!Number.isInteger(iter) || iter < 1 || iter > MAX_ITERATIONS) return false;
  const salt = fromB64url(parts[2]);
  const expected = fromB64url(parts[3]);
  if (!salt || !expected || expected.length === 0) return false;
  const dk = crypto.pbkdf2Sync(String(password ?? ""), salt, iter, expected.length, "sha256");
  if (dk.length !== expected.length) return false;
  return crypto.timingSafeEqual(dk, expected);
}

/**
 * @returns {{ok: boolean, legacy: boolean}}
 * legacy is true only when [stored] is non-empty plaintext (not a hash).
 */
function passwordMatches(stored, password) {
  const value = stored == null ? "" : String(stored);
  if (!value) return { ok: false, legacy: false };
  if (isPasswordHash(value)) {
    return { ok: verifyPassword(value, password), legacy: false };
  }
  const a = Buffer.from(value);
  const b = Buffer.from(password == null ? "" : String(password));
  if (a.length !== b.length) return { ok: false, legacy: true };
  return { ok: crypto.timingSafeEqual(a, b), legacy: true };
}

module.exports = {
  PREFIX,
  DEFAULT_ITERATIONS,
  hashPassword,
  verifyPassword,
  isPasswordHash,
  passwordMatches,
};
