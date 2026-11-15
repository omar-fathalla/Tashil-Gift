const crypto = require("node:crypto");
const logger = require("firebase-functions/logger");

/**
 * Brute-force protection for partnerPortalLogin. Four limiters, all checked
 * and counted in one transaction before any account lookup:
 *
 *  user_ip      5 attempts / 15 min per username+IP, escalating lockout
 *               (15m, 1h, 6h, then 24h cap). Keyed by IP too, so a stranger
 *               cannot lock a real user out from elsewhere.
 *  user_global  30 attempts / hour per username across all IPs, flat 15 min
 *               lock (no escalation) against distributed guessing.
 *  ip_10m       20 attempts / 10 min per client IP.
 *  ip_day       300 attempts / 24 h per client IP.
 *
 * Every attempt is counted up front, so parallel requests can never get more
 * password checks than the limits allow. A successful login deletes the
 * username+IP doc (failures and lockout level) and refunds only its own
 * attempt on the global username counter: a success from one IP says nothing
 * about guesses from other IPs, so the global counter is not reset.
 *
 * Docs live in `loginThrottle/{sha256(namespaced key)}`; raw usernames and IPs
 * are never stored. `expireAt` is a Firestore TTL field; expired docs are also
 * treated as empty here, so TTL lag never extends a lock.
 * Clients can never read/write this collection (see firestore.rules).
 */
const COLLECTION = "loginThrottle";
const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const USER_IP_MAX = 5;
const USER_IP_WINDOW_MS = 15 * MINUTE;
const LOCKOUT_STEPS_MS = [15 * MINUTE, HOUR, 6 * HOUR, 24 * HOUR];
// How long the lockout level is remembered after the last lock/window ends.
const LEVEL_MEMORY_MS = DAY;
const USER_GLOBAL_MAX = 30;
const USER_GLOBAL_WINDOW_MS = HOUR;
const USER_GLOBAL_LOCK_MS = 15 * MINUTE;
const IP_MAX = 20;
const IP_WINDOW_MS = 10 * MINUTE;
const IP_DAY_MAX = 300;
const IP_DAY_WINDOW_MS = DAY;

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

/**
 * Rightmost X-Forwarded-For entry: the one Google's front end appends. Earlier
 * entries are client-controlled and can be spoofed.
 */
function loginClientIp(rawRequest) {
  if (!rawRequest) return "";
  const xff = rawRequest.headers && rawRequest.headers["x-forwarded-for"];
  if (typeof xff === "string") {
    const hops = xff.split(",").map((s) => s.trim()).filter(Boolean);
    if (hops.length) return hops[hops.length - 1];
  }
  return rawRequest.ip || (rawRequest.socket && rawRequest.socket.remoteAddress) || "";
}

function throttleKey(namespace, value) {
  return crypto.createHash("sha256").update(`${namespace}:${value}`).digest("hex");
}

function throttleKeys(identifier, ip) {
  const user = normalizeIdentifier(identifier);
  const addr = ip || "unknown";
  return {
    userIpKey: throttleKey("idip", `${user}|${addr}`),
    userKey: throttleKey("id", user),
    ipKey: throttleKey("ip", addr),
  };
}

function ms(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return Number(v) || 0;
}

function liveData(snap, now) {
  if (!snap.exists) return {};
  const d = snap.data() || {};
  return ms(d.expireAt) > now ? d : {};
}

/** Fixed window that starts at the first attempt and resets once it elapses. */
function windowOf(start, count, windowMs, now) {
  const s = ms(start);
  if (!s || now >= s + windowMs) return { start: now, count: 0 };
  return { start: s, count: Number(count) || 0 };
}

function retrySec(untilMs, now) {
  return Math.max(1, Math.ceil((untilMs - now) / 1000));
}

/**
 * Throws LoginThrottledError if any limiter is active (no writes then).
 * Otherwise records the attempt on every limiter and arms any lock it reaches.
 */
async function beginLoginAttempt({ db, identifier, ip, now = Date.now() }) {
  const keys = throttleKeys(identifier, ip);
  const col = db.collection(COLLECTION);
  const refs = [col.doc(keys.userIpKey), col.doc(keys.userKey), col.doc(keys.ipKey)];
  const logIp = ip || "unknown";

  const outcome = await db.runTransaction(async (tx) => {
    const [uiDoc, uDoc, ipDoc] = (await Promise.all(refs.map((r) => tx.get(r)))).map((s) => liveData(s, now));

    const ip10 = windowOf(ipDoc.windowStart, ipDoc.count, IP_WINDOW_MS, now);
    const ipDay = windowOf(ipDoc.dayStart, ipDoc.dayCount, IP_DAY_WINDOW_MS, now);
    const uiLockedUntil = ms(uiDoc.lockedUntil);
    const uLockedUntil = ms(uDoc.lockedUntil);
    const level = Number(uiDoc.level) || 0;

    const active = [];
    if (ip10.count >= IP_MAX) active.push({ limiter: "ip_10m", key: keys.ipKey, count: ip10.count, until: ip10.start + IP_WINDOW_MS });
    if (ipDay.count >= IP_DAY_MAX) active.push({ limiter: "ip_day", key: keys.ipKey, count: ipDay.count, until: ipDay.start + IP_DAY_WINDOW_MS });
    if (uiLockedUntil > now) active.push({ limiter: "user_ip", key: keys.userIpKey, until: uiLockedUntil });
    if (uLockedUntil > now) active.push({ limiter: "user_global", key: keys.userKey, until: uLockedUntil });
    if (active.length) {
      return { blocked: active, level, retryAfterSec: retrySec(Math.max(...active.map((a) => a.until)), now) };
    }

    const lockouts = [];
    const ui = windowOf(uiDoc.windowStart, uiDoc.failures, USER_IP_WINDOW_MS, now);
    ui.count += 1;
    let newLevel = level;
    let uiLock = 0;
    if (ui.count >= USER_IP_MAX) {
      newLevel = level + 1;
      uiLock = now + LOCKOUT_STEPS_MS[Math.min(newLevel, LOCKOUT_STEPS_MS.length) - 1];
      lockouts.push({ limiter: "user_ip", key: keys.userIpKey, count: ui.count, level: newLevel, retryAfterSec: retrySec(uiLock, now) });
      ui.count = 0;
      ui.start = now;
    }
    const u = windowOf(uDoc.windowStart, uDoc.failures, USER_GLOBAL_WINDOW_MS, now);
    u.count += 1;
    let uLock = 0;
    if (u.count >= USER_GLOBAL_MAX) {
      uLock = now + USER_GLOBAL_LOCK_MS;
      lockouts.push({ limiter: "user_global", key: keys.userKey, count: u.count, level: 0, retryAfterSec: retrySec(uLock, now) });
      u.count = 0;
      u.start = now;
    }

    tx.set(refs[0], {
      kind: "idip",
      failures: ui.count,
      level: newLevel,
      windowStart: new Date(ui.start),
      lockedUntil: uiLock ? new Date(uiLock) : null,
      expireAt: new Date(Math.max(uiLock, ui.start + USER_IP_WINDOW_MS) + LEVEL_MEMORY_MS),
    });
    tx.set(refs[1], {
      kind: "id",
      failures: u.count,
      windowStart: new Date(u.start),
      lockedUntil: uLock ? new Date(uLock) : null,
      expireAt: new Date(Math.max(uLock, u.start + USER_GLOBAL_WINDOW_MS)),
    });
    tx.set(refs[2], {
      kind: "ip",
      count: ip10.count + 1,
      windowStart: new Date(ip10.start),
      dayCount: ipDay.count + 1,
      dayStart: new Date(ipDay.start),
      expireAt: new Date(Math.max(ip10.start + IP_WINDOW_MS, ipDay.start + IP_DAY_WINDOW_MS)),
    });
    return { lockouts };
  });

  if (outcome.blocked) {
    for (const b of outcome.blocked) {
      if (b.limiter !== "ip_10m" && b.limiter !== "ip_day") continue;
      logger.warn("partnerPortalLogin IP cap hit", {
        event: "login_ip_cap",
        limiter: b.limiter,
        key: b.key,
        ip: logIp,
        count: b.count,
        lockoutLevel: outcome.level,
        retryAfter: outcome.retryAfterSec,
      });
    }
    throw new LoginThrottledError(outcome.retryAfterSec);
  }
  for (const l of outcome.lockouts) {
    logger.warn("partnerPortalLogin identifier locked", {
      event: "login_lockout",
      limiter: l.limiter,
      key: l.key,
      ip: logIp,
      count: l.count,
      lockoutLevel: l.level,
      retryAfter: l.retryAfterSec,
    });
  }
  return keys;
}

/**
 * Successful login: clear the username+IP doc and refund this attempt on the
 * global username counter (which is otherwise left as is, see above).
 */
async function recordLoginSuccess({ db, userIpKey, userKey, now = Date.now() }) {
  const col = db.collection(COLLECTION);
  const uRef = col.doc(userKey);
  await db.runTransaction(async (tx) => {
    const d = liveData(await tx.get(uRef), now);
    const failures = Number(d.failures) || 0;
    if (failures > 0 && !(ms(d.lockedUntil) > now)) tx.set(uRef, { ...d, failures: failures - 1 });
    tx.delete(col.doc(userIpKey));
  });
}

module.exports = {
  COLLECTION,
  IP_DAY_MAX,
  IP_MAX,
  LOCKOUT_STEPS_MS,
  USER_GLOBAL_LOCK_MS,
  USER_GLOBAL_MAX,
  USER_IP_MAX,
  LoginThrottledError,
  beginLoginAttempt,
  loginClientIp,
  normalizeIdentifier,
  recordLoginSuccess,
  throttleKey,
  throttleKeys,
};
