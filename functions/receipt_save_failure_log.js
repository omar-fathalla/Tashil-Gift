const { HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");

/**
 * 2.0.155: rep app reports a failed receipt save so the failing step is
 * visible in Cloud Logging (Firestore rule denials are not logged by Google).
 * Log only - writes nothing except the shared rate-limit bucket.
 */
const LIMITS = [
  { name: "min", windowMs: 60 * 1000, max: 10 },
  { name: "day", windowMs: 24 * 60 * 60 * 1000, max: 200 },
];

function clip(v, max) {
  return String(v == null ? "" : v).slice(0, max);
}

async function logReceiptSaveFailureHandler(db, request) {
  const data = request.data || {};
  const uid = request.auth ? request.auth.uid : "";
  try {
    await consumeRateLimit({
      db,
      scope: "saveFailLog",
      key: clientKey({ uid, rawRequest: request.rawRequest }),
      limits: LIMITS,
    });
  } catch (e) {
    if (e instanceof RateLimitError) return { ok: false, limited: true };
    throw new HttpsError("internal", "rate limit unavailable");
  }
  logger.warn("receipt_save_failure", {
    step: clip(data.step, 40),
    code: clip(data.code, 60),
    message: clip(data.message, 500),
    uid,
    authProvider: request.auth ? clip(request.auth.token.firebase && request.auth.token.firebase.sign_in_provider, 40) : "none",
    role: request.auth ? clip(request.auth.token.role, 40) : "",
    clientUid: clip(data.clientUid, 128),
    receiptNumber: clip(data.receiptNumber, 80),
    campaignId: clip(data.campaignId, 128),
    companySlug: clip(data.companySlug, 128),
    appVersion: clip(data.appVersion, 40),
  });
  return { ok: true };
}

module.exports = { logReceiptSaveFailureHandler, LIMITS };
