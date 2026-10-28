/**
 * Partner portal (Brand Executive /portal and Agency Ops /ops) server-side auth.
 *
 * companies/* and events/* hold plaintext portal credentials and are readable
 * by admins only. These callables do the credential check with the Admin SDK
 * and never return a password.
 *
 * partnerPortalInfo:  public branding (name + logo) and credential versions,
 *                     used for the login screen and session revalidation.
 * partnerPortalLogin: verifies username/password for the requested role.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("./admin_sdk");
const { RateLimitError, clientKey, consumeRateLimit } = require("./rate_limit");

const MINUTE = 60 * 1000;
const DAY = 24 * 60 * MINUTE;
const LOGIN_CLIENT_LIMITS = [
  { name: "min", windowMs: MINUTE, max: 10 },
  { name: "day", windowMs: DAY, max: 200 },
];
const LOGIN_ACCOUNT_LIMITS = [
  { name: "min", windowMs: MINUTE, max: 20 },
  { name: "day", windowMs: DAY, max: 500 },
];
const INFO_CLIENT_LIMITS = [
  { name: "min", windowMs: MINUTE, max: 60 },
  { name: "day", windowMs: DAY, max: 2000 },
];

const callableOptions = {
  region: "us-central1",
  memory: "256MiB",
  // Portal visitors are often not signed in; App Check is monitored, not
  // enforced, across the project. Brute force is bounded by the rate limits.
  enforceAppCheck: false,
};

const ROLE_BRAND = "brand_manager";
const ROLE_AGENCY = "agency_ops";

function str(v) {
  return v === undefined || v === null ? "" : String(v).trim();
}
function ver(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 1;
}
function cleanId(v, max = 128) {
  const s = str(v);
  if (s.length > max || /[/]/.test(s)) return "";
  return s;
}

// ---- Default credentials (parity with PartnerPortalAuthService in Dart) ----
function sanitizeSlug(raw) {
  const c = str(raw).toLowerCase().replace(/[^a-z0-9_-]/g, "");
  return c || "partner";
}
// Mirrors the Dart code as compiled for the web (dart2js number semantics),
// which is what produced every default credential admins have shared.
function deterministicPin(input, salt) {
  let h = 2166136261;
  const combined = `${salt}:${input}`;
  for (let i = 0; i < combined.length; i++) {
    h = (h ^ combined.charCodeAt(i)) >>> 0;
    h = ((h * 16777619) & 0x7fffffff) >>> 0;
  }
  return String((h % 9000) + 1000);
}
const defaults = {
  brandUser: (s) => `brand_${sanitizeSlug(s)}`,
  brandPass: (s) => `Bm#${sanitizeSlug(s)}${deterministicPin(sanitizeSlug(s), "BM2026")}`,
  agencyUser: (s) => `ops_${sanitizeSlug(s)}`,
  agencyPass: (s) => `Op#${sanitizeSlug(s)}${deterministicPin(sanitizeSlug(s), "OPS2026")}`,
  campUser: (s, e) => {
    const short = String(e).replace(/[^a-zA-Z0-9]/g, "").toLowerCase();
    const suffix = short.length >= 4 ? short.substring(0, 4) : short || "camp";
    return `ops_${sanitizeSlug(s)}_${suffix}`;
  },
  campPass: (s, e) => `Cp#${sanitizeSlug(s)}${deterministicPin(`${sanitizeSlug(s)}:${e}`, "CAMP2026")}`,
};

function sameUser(a, b) {
  return str(a).toLowerCase() === str(b).toLowerCase();
}

/** Pure credential check. Returns a session object or {error}. */
function verifyCredentials({ slug, role, eventId, username, password, company, event, companyEvents }) {
  const c = company || {};
  const brandUser = str(c.brandManagerUsername) || defaults.brandUser(slug);
  const brandPass = str(c.brandManagerPassword) || defaults.brandPass(slug);
  const agencyUser = str(c.agencyOpsUsername) || defaults.agencyUser(slug);
  const agencyPass = str(c.agencyOpsPassword) || defaults.agencyPass(slug);
  const user = str(username);
  const pass = str(password);

  const campaignCreds = (id, data) => ({
    id,
    user: str(data.customAgencyUsername) || defaults.campUser(slug, id),
    pass: str(data.customAgencyPassword) || defaults.campPass(slug, id),
    version: ver(data.customAgencyCredentialVersion),
  });
  const evHasCustom = !!(event && event.hasCustomAgencyCredentials === true);

  if (role === ROLE_BRAND) {
    const isAgency = (sameUser(user, agencyUser) && pass === agencyPass) ||
      (evHasCustom && (() => {
        const cc = campaignCreds(eventId, event);
        return sameUser(user, cc.user) && pass === cc.pass;
      })());
    if (isAgency) return { error: "agency_creds_on_brand" };
    if (sameUser(user, brandUser) && pass === brandPass) {
      return { role, username: brandUser, credentialVersion: ver(c.brandCredentialVersion), isCampaignTier: false, lockedEventId: null };
    }
    return { error: "invalid_brand" };
  }

  // agency_ops
  if (sameUser(user, brandUser) && pass === brandPass) return { error: "brand_creds_on_agency" };

  if (eventId && evHasCustom) {
    const cc = campaignCreds(eventId, event);
    if (sameUser(user, cc.user) && pass === cc.pass) {
      return { role, username: cc.user, credentialVersion: cc.version, isCampaignTier: true, lockedEventId: eventId };
    }
    return { error: "campaign_requires_custom" };
  }

  for (const ev of companyEvents || []) {
    if (!ev.data || ev.data.hasCustomAgencyCredentials !== true) continue;
    const cc = campaignCreds(ev.id, ev.data);
    if (sameUser(user, cc.user) && pass === cc.pass) {
      return { role, username: cc.user, credentialVersion: cc.version, isCampaignTier: true, lockedEventId: ev.id };
    }
  }

  if (sameUser(user, agencyUser) && pass === agencyPass) {
    return { role, username: agencyUser, credentialVersion: ver(c.agencyCredentialVersion), isCampaignTier: false, lockedEventId: eventId || null };
  }
  return { error: "invalid_agency" };
}

async function loadContext(db, rawSlug, rawEventId) {
  let slug = cleanId(rawSlug).toLowerCase();
  const eventId = cleanId(rawEventId) || null;
  let event = null;
  if (eventId) {
    const s = await db.collection("events").doc(eventId).get();
    if (s.exists) {
      event = s.data() || {};
      if (!slug) slug = cleanId(event.companySlug).toLowerCase();
    }
  }
  let company = null;
  if (slug) {
    const s = await db.collection("companies").doc(slug).get();
    if (s.exists) company = s.data() || {};
  }
  return { slug, eventId, event, company };
}

function publicInfo({ slug, eventId, event, company }) {
  const c = company || {};
  const e = event || {};
  let logo = str(c.logoUrl);
  if (logo && !/^https:\/\//i.test(logo)) logo = "";
  return {
    companySlug: slug,
    companyName: str(c.name) || str(e.targetCompany),
    logoUrl: logo,
    eventId: eventId,
    eventName: event ? str(e.eventName) || null : null,
    brandCredentialVersion: ver(c.brandCredentialVersion),
    agencyCredentialVersion: ver(c.agencyCredentialVersion),
    hasCustomAgencyCredentials: !!(event && e.hasCustomAgencyCredentials === true),
    customAgencyCredentialVersion: ver(e.customAgencyCredentialVersion),
  };
}

async function limit(db, scope, key, limits) {
  try {
    await consumeRateLimit({ db, scope, key, limits });
  } catch (err) {
    if (err instanceof RateLimitError) {
      throw new HttpsError("resource-exhausted", "Too many attempts. Please wait and try again.", {
        retryAfterSec: err.retryAfterSec,
      });
    }
    throw err;
  }
}

const partnerPortalInfo = onCall(callableOptions, async (request) => {
  const db = admin.firestore();
  const data = request.data || {};
  await limit(db, "portalInfo", clientKey({ uid: request.auth && request.auth.uid, rawRequest: request.rawRequest }), INFO_CLIENT_LIMITS);
  const ctx = await loadContext(db, data.companySlug, data.eventId);
  if (!ctx.slug) throw new HttpsError("invalid-argument", "companySlug or eventId is required.");
  return publicInfo(ctx);
});

const partnerPortalLogin = onCall(callableOptions, async (request) => {
  const db = admin.firestore();
  const data = request.data || {};
  const role = data.role === ROLE_BRAND || data.role === ROLE_AGENCY ? data.role : null;
  const username = str(data.username).slice(0, 200);
  const password = str(data.password).slice(0, 200);
  if (!role) throw new HttpsError("invalid-argument", "role is required.");
  if (!username || !password) throw new HttpsError("invalid-argument", "username and password are required.");

  await limit(db, "portalLogin", clientKey({ uid: request.auth && request.auth.uid, rawRequest: request.rawRequest }), LOGIN_CLIENT_LIMITS);
  const ctx = await loadContext(db, data.companySlug, data.eventId);
  if (!ctx.slug) throw new HttpsError("invalid-argument", "companySlug or eventId is required.");
  await limit(db, "portalLoginAcct", `${ctx.slug}|${role}|${username.toLowerCase()}`, LOGIN_ACCOUNT_LIMITS);

  let companyEvents = [];
  if (role === ROLE_AGENCY && !(ctx.eventId && ctx.event && ctx.event.hasCustomAgencyCredentials === true)) {
    const q = await db.collection("events").where("companySlug", "==", ctx.slug).get();
    companyEvents = q.docs.map((d) => ({ id: d.id, data: d.data() }));
  }

  const result = verifyCredentials({ ...ctx, role, username, password, companyEvents });
  const info = publicInfo(ctx);
  if (result.error) {
    console.warn("partnerPortalLogin rejected", { slug: ctx.slug, role, reason: result.error });
    return { ok: false, reason: result.error, info };
  }
  return {
    ok: true,
    info,
    session: {
      companySlug: ctx.slug,
      role: result.role,
      username: result.username,
      credentialVersion: result.credentialVersion,
      isCampaignTier: result.isCampaignTier,
      lockedEventId: result.lockedEventId,
    },
  };
});

module.exports = {
  partnerPortalInfo,
  partnerPortalLogin,
  _test: { verifyCredentials, publicInfo, defaults, deterministicPin },
};
