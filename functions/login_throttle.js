const crypto = require("node:crypto");
const logger = require("firebase-functions/logger");

/**
 * Brute-force protection for partnerPortalLogin.
 *
 * Every attempt is counted up front, inside the same transaction that checks
 * the lockout, so parallel requests can never get more than ID_MAX_FAILURES
 * password checks per window. A successful login deletes the identifier doc,
 * which resets both the failure count and the lockout level.
 *
 * Docs live in `loginThrottle/{sha256('id:'+identifier | 'ip:'+ip)}`; raw
 * identifiers and IPs are never stored. `expireAt` is a Firestore TTL field;
 * expired docs are also treated as empty here, so TTL lag never extends a lock.
 * Clients can never read/write this collection (see firestore.rules).
 */
const COLLECTION = "loginThrottle";
const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;

const ID_MAX_FAILURES = 5;
const ID_WINDOW_MS = 15 * MINUTE;
const LOCKOUT_STEPS_MS = [15 * MINUTE, HOUR, 6 * HOUR, 24 * HOUR];
// How long the lockout level is remembered after the last lock/window ends.
const LEVEL_MEMORY_MS = 24 * HOUR;
const IP_MAX_ATTEMPTS = 20;
const IP_WINDOW_MS = 10 * MINUTE;

class LoginThrottledError extends Error {
  constructor(retryAfterSec) {
    super(`Login throttled. Retry in ${retryAfterSec}s.`);
    this.code = 429;
    this.retryAfterSec = retryAfterSec;
  }
}

/** Same normalization as sameUser() in partner_portal.js: trim + lowercase. */
function normalizeIdentifier(raw) {
  return (raw === undefined || raw === null ? "" : String(raw)).trim().toLowerCase();
}

function throttleKey(namespace, value) {
  return crypto.createHash("sha256").update(`${namespace}:${value}`).digest("hex");
}

function ms(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return Number(v) || 0;
}

function liveData(snap, now) {
  if (!snap.exists) return null;
  const d = snap.data() || {};
  return ms(d.expireAt) > now ? d : null;
}

function retrySec(untilMs, now) {
  return Math.max(1, Math.ceil((untilMs - now) / 1000));
}

/**
 * Throws LoginThrottledError if the identifier is locked or the IP is capped
 * (no writes then). Otherwise records the attempt against both keys and, on
 * the ID_MAX_FAILURES-th attempt in the window, arms the next lockout.
 */
async function beginLoginAttempt({ db, identifier, ip, now = Date.now() }) {
  const idKey = throttleKey("id", normalizeIdentifier(identifier));
  const ipKey = throttleKey("ip", ip || "unknown");
  const idRef = db.collection(COLLECTION).doc(idKey);
  const ipRef = db.collection(COLLECTION).doc(ipKey);

  const outcome = await db.runTransaction(async (tx) => {
    const [idSnap, ipSnap] = await Promise.all([tx.get(idRef), tx.get(ipRef)]);
    const idDoc = liveData(idSnap, now) || {};
    const ipDoc = liveData(ipSnap, now) || {};

    let ipStart = ms(ipDoc.windowStart);
    let ipCount = Number(ipDoc.count) || 0;
    if (!ipStart || now >= ipStart + IP_WINDOW_MS) {
      ipStart = now;
      ipCount = 0;
    }
    const ipCapped = ipCount >= IP_MAX_ATTEMPTS;
    const lockedUntil = ms(idDoc.lockedUntil);
    const level = Number(idDoc.level) || 0;
    const idLocked = lockedUntil > now;
    if (ipCapped || idLocked) {
      return {
        blocked: {
          retryAfterSec: retrySec(Math.max(ipCapped ? ipStart + IP_WINDOW_MS : 0, idLocked ? lockedUntil : 0), now),
          ipCapped,
          ipCount,
          idLocked,
          level,
        },
      };
    }

    let idStart = ms(idDoc.windowStart);
    let failures = Number(idDoc.failures) || 0;
    if (!idStart || now >= idStart + ID_WINDOW_MS) {
      idStart = now;
      failures = 0;
    }
    failures += 1;
    let lockout = null;
    let newLevel = level;
    let newLockedUntil = 0;
    if (failures >= ID_MAX_FAILURES) {
      newLevel = level + 1;
      newLockedUntil = now + LOCKOUT_STEPS_MS[Math.min(newLevel, LOCKOUT_STEPS_MS.length) - 1];
      lockout = { count: failures, level: newLevel, retryAfterSec: retrySec(newLockedUntil, now) };
      failures = 0;
      idStart = now;
    }

    tx.set(idRef, {
      kind: "id",
      failures,
      level: newLevel,
      windowStart: new Date(idStart),
      lockedUntil: newLockedUntil ? new Date(newLockedUntil) : null,
      expireAt: new Date(Math.max(newLockedUntil, idStart + ID_WINDOW_MS) + LEVEL_MEMORY_MS),
    });
    tx.set(ipRef, {
      kind: "ip",
      count: ipCount + 1,
      windowStart: new Date(ipStart),
      expireAt: new Date(ipStart + IP_WINDOW_MS),
    });
    return { lockout };
  });

  if (outcome.blocked) {
    const b = outcome.blocked;
    if (b.ipCapped) {
      logger.warn("partnerPortalLogin IP cap hit", {
        event: "login_ip_cap",
        key: ipKey,
        ip: ip || "unknown",
        count: b.ipCount,
        lockoutLevel: b.level,
        retryAfter: b.retryAfterSec,
      });
    }
    throw new LoginThrottledError(b.retryAfterSec);
  }
  if (outcome.lockout) {
    logger.warn("partnerPortalLogin identifier locked", {
      event: "login_lockout",
      key: idKey,
      ip: ip || "unknown",
      count: outcome.lockout.count,
      lockoutLevel: outcome.lockout.level,
      retryAfter: outcome.lockout.retryAfterSec,
    });
  }
  return { idKey, ipKey };
}

/** Successful login: clear the identifier's failures and lockout level. */
async function recordLoginSuccess({ db, idKey }) {
  await db.collection(COLLECTION).doc(idKey).delete();
}

module.exports = {
  COLLECTION,
  ID_MAX_FAILURES,
  ID_WINDOW_MS,
  LOCKOUT_STEPS_MS,
  IP_MAX_ATTEMPTS,
  IP_WINDOW_MS,
  LoginThrottledError,
  beginLoginAttempt,
  normalizeIdentifier,
  recordLoginSuccess,
  throttleKey,
};
