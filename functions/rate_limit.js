const crypto = require("node:crypto");

/**
 * Per-client fixed-window rate limiting backed by Firestore (M3).
 * One doc per (scope, client, window, bucket) in `rateLimits`; `expireAt`
 * is a Firestore TTL field so old buckets are deleted automatically.
 * Clients can never read/write this collection (see firestore.rules).
 */
const COLLECTION = "rateLimits";
const MINUTE = 60 * 1000;
const DAY = 24 * 60 * MINUTE;

const LIMITS = {
  gemini: [
    { name: "min", windowMs: MINUTE, max: 20 },
    { name: "day", windowMs: DAY, max: 200 },
  ],
  waha: [
    { name: "min", windowMs: MINUTE, max: 30 },
    { name: "day", windowMs: DAY, max: 500 },
  ],
};

class RateLimitError extends Error {
  constructor(scope, window, retryAfterSec) {
    super(`Rate limit exceeded (${scope}/${window}). Retry in ${retryAfterSec}s.`);
    this.code = 429;
    this.scope = scope;
    this.window = window;
    this.retryAfterSec = retryAfterSec;
  }
}

function hash(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 32);
}

/** First client IP: X-Forwarded-For (set by Google front end) or socket. */
function clientIp(rawRequest) {
  if (!rawRequest) return "";
  const xff = rawRequest.headers && rawRequest.headers["x-forwarded-for"];
  if (typeof xff === "string" && xff.trim()) return xff.split(",")[0].trim();
  return rawRequest.ip || (rawRequest.socket && rawRequest.socket.remoteAddress) || "";
}

/**
 * Client key: Firebase Auth uid when present (reps get an anonymous uid on
 * public links), else a hash of the client IP. App Check `sub` is the app id,
 * shared by every device, so it is not used as a key.
 */
function clientKey({ uid, rawRequest }) {
  if (uid) return "uid:" + uid;
  const ip = clientIp(rawRequest);
  return "ip:" + hash(ip || "unknown");
}

/**
 * Atomically increments every window counter for `key`; throws RateLimitError
 * if any window is already at its max (no increment happens then).
 */
async function consumeRateLimit({ db, scope, key, now = Date.now(), limits }) {
  const windows = limits || LIMITS[scope];
  if (!db || !windows) throw new Error("consumeRateLimit: missing db or scope");
  const keyHash = hash(key);
  const refs = windows.map((w) => {
    const bucket = Math.floor(now / w.windowMs);
    return {
      w,
      bucket,
      ref: db.collection(COLLECTION).doc(`${scope}_${keyHash}_${w.name}_${bucket}`),
    };
  });

  return db.runTransaction(async (tx) => {
    const snaps = await Promise.all(refs.map((r) => tx.get(r.ref)));
    const counts = snaps.map((s) => (s.exists ? Number((s.data() || {}).count) || 0 : 0));
    for (let i = 0; i < refs.length; i++) {
      if (counts[i] >= refs[i].w.max) {
        const resetAt = (refs[i].bucket + 1) * refs[i].w.windowMs;
        throw new RateLimitError(scope, refs[i].w.name, Math.max(1, Math.ceil((resetAt - now) / 1000)));
      }
    }
    refs.forEach((r, i) => {
      tx.set(r.ref, {
        scope,
        window: r.w.name,
        count: counts[i] + 1,
        expireAt: new Date((r.bucket + 1) * r.w.windowMs + r.w.windowMs),
      });
    });
    return refs.map((r, i) => ({ window: r.w.name, remaining: r.w.max - counts[i] - 1 }));
  });
}

module.exports = { LIMITS, COLLECTION, RateLimitError, clientKey, clientIp, consumeRateLimit, hash };
