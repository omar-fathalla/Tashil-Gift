const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("./admin_sdk");
const { verifyReceiptImage } = require("./receipt_verification");
const { applyCampaignPrizeClaim } = require("./security_functions");
const { handleWahaWebhook } = require("./waha_webhook");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");
const {
  updateWhatsappWebhookConfig,
  manageWhatsappSenderLink,
} = require("./whatsapp_webhook_admin");

// Firebase Secrets (set via: firebase functions:secrets:set NAME)
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const wahaApiKey = defineSecret("WAHA_API_KEY");
const wahaWebhookSecret = defineSecret("WAHA_WEBHOOK_SECRET");

// Production functions are already 2nd gen in us-central1 with 256MiB.
// These options keep a deploy as an in-place update of the same Cloud Run services.
const httpsOptions = {
  region: "us-central1",
  memory: "256MiB",
};
const callableOptions = {
  ...httpsOptions,
  enforceAppCheck: true,
};

admin.initializeApp();
const db = admin.firestore();

/**
 * Escapes HTML entities to prevent XSS in dynamic meta tags
 */
function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

// In-memory TTL cache (5 minutes) to eliminate repeated Firestore round-trips on hot paths
const eventPreviewCache = new Map();
const PREVIEW_CACHE_TTL_MS = 5 * 60 * 1000;

/**
 * Resolves event document from Firestore by eventId or companySlug with in-memory caching
 */
async function resolveEvent(db, eventIdParam, routeIdentifier) {
  const cacheKey = `${eventIdParam || ""}:${routeIdentifier || ""}`.toLowerCase();
  const cached = eventPreviewCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < PREVIEW_CACHE_TTL_MS) {
    return cached.data;
  }

  let result = null;
  if (eventIdParam) {
    const eventDoc = await db.collection("events").doc(eventIdParam).get();
    if (eventDoc.exists) result = eventDoc.data();
  }

  if (!result && routeIdentifier) {
    const directDoc = await db.collection("events").doc(routeIdentifier).get();
    if (directDoc.exists) {
      result = directDoc.data();
    } else {
      const cleanSlug = routeIdentifier.toLowerCase();
      const slugQuery = await db
        .collection("events")
        .where("companySlug", "==", cleanSlug)
        .limit(1)
        .get();

      if (!slugQuery.empty) result = slugQuery.docs[0].data();
    }
  }

  eventPreviewCache.set(cacheKey, { data: result, timestamp: Date.now() });
  return result;
}

/**
 * Extracts and formats metadata for social share preview
 */
function extractPreviewMetadata(resolvedEvent, query, isManagerPortal) {
  let companyName = "تسهيل جيفت";
  let eventName = "منظومة إدارة العروض والهدايا الترويجية";
  let companyLogoUrl = "https://tashil-gift.web.app/icons/Icon-512.png";
  let welcomeDesc = "Tashil Gift - Smart Multi-Company Promotion & Validation Platform by Switch Point";

  if (resolvedEvent) {
    companyName = resolvedEvent.targetCompany || resolvedEvent.companyName || companyName;
    eventName = resolvedEvent.eventName || eventName;
    if (resolvedEvent.companyLogoUrl?.trim()) {
      companyLogoUrl = resolvedEvent.companyLogoUrl.trim();
    }
    const welcome = resolvedEvent.welcomeMessage?.trim() || resolvedEvent.welcomeTitle?.trim();
    if (welcome) {
      welcomeDesc = welcome;
    }
  } else if (query.companyName) {
    companyName = query.companyName;
  }

  if (query.logo) {
    companyLogoUrl = query.logo;
  }

  let pageTitle = "";
  let pageDescription = "";

  if (isManagerPortal) {
    pageTitle = `${companyName} • بوابة الشريك | Tashil Gift`;
    pageDescription = `منظومة إدارة ومتابعة الحملات الترويجية والهدايا لشركة ${companyName}`;
  } else {
    pageTitle = `${eventName} (${companyName}) | Tashil Gift`;
    pageDescription = welcomeDesc;
  }

  return {
    pageTitle,
    pageDescription,
    companyLogoUrl,
  };
}

/**
 * Builds HTML page template with rich OpenGraph / Twitter meta tags and Instant M3 Splash Loader
 */
function buildPreviewHtml({ pageTitle, pageDescription, companyLogoUrl }) {
  const escapedTitle = escapeHtml(pageTitle);
  const escapedDesc = escapeHtml(pageDescription);
  const escapedLogo = escapeHtml(companyLogoUrl);

  return `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapedTitle}</title>
  <meta name="description" content="${escapedDesc}">

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="preconnect" href="https://firestore.googleapis.com">

  <!-- iOS meta tags & icons -->
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="${escapedTitle}">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">

  <!-- Favicon -->
  <link rel="icon" type="image/svg+xml" href="/favicon.svg"/>
  <link rel="icon" type="image/png" href="/favicon.png"/>

  <!-- Open Graph / WhatsApp / Facebook -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Tashil Gift">
  <meta property="og:title" content="${escapedTitle}">
  <meta property="og:description" content="${escapedDesc}">
  <meta property="og:image" content="${escapedLogo}">
  <meta property="og:image:secure_url" content="${escapedLogo}">
  <meta property="og:image:alt" content="${escapedTitle}">
  <meta property="og:image:width" content="600">
  <meta property="og:image:height" content="600">

  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapedTitle}">
  <meta name="twitter:description" content="${escapedDesc}">
  <meta name="twitter:image" content="${escapedLogo}">

  <link rel="manifest" href="/manifest.json">

  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      background-color: #F8FAF3;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      overflow: hidden;
    }

    #app-splash-loader {
      position: fixed;
      inset: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background-color: #F8FAF3;
      z-index: 999999;
      transition: opacity 0.28s cubic-bezier(0.4, 0, 0.2, 1), visibility 0.28s;
    }

    #app-splash-loader.loaded {
      opacity: 0;
      visibility: hidden;
      pointer-events: none;
    }

    .splash-card {
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 32px 40px;
      border-radius: 24px;
      background: #FFFFFF;
      border: 1px solid rgba(74, 93, 35, 0.14);
      box-shadow: 0 12px 32px rgba(74, 93, 35, 0.06);
      max-width: 320px;
      width: 85%;
      text-align: center;
    }

    .splash-logo-badge {
      width: 64px;
      height: 64px;
      border-radius: 18px;
      background: linear-gradient(135deg, #4A5D23 0%, #637B30 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      color: #FFFFFF;
      font-size: 28px;
      font-weight: 900;
      box-shadow: 0 6px 16px rgba(74, 93, 35, 0.25);
      margin-bottom: 16px;
      animation: pulseBadge 1.8s infinite ease-in-out;
    }

    .splash-title {
      font-size: 17px;
      font-weight: 800;
      color: #1B1C18;
      margin: 0 0 6px 0;
    }

    .splash-subtitle {
      font-size: 13px;
      color: #5C5F52;
      margin: 0 0 20px 0;
    }

    .m3-linear-progress {
      width: 100%;
      height: 6px;
      background-color: #E3E8D8;
      border-radius: 999px;
      overflow: hidden;
      position: relative;
    }

    .m3-linear-progress-bar {
      position: absolute;
      top: 0;
      bottom: 0;
      width: 45%;
      background-color: #4A5D23;
      border-radius: 999px;
      animation: m3Indeterminate 1.25s infinite cubic-bezier(0.4, 0, 0.2, 1);
    }

    @keyframes m3Indeterminate {
      0% { right: -45%; width: 35%; }
      50% { width: 55%; }
      100% { right: 100%; width: 35%; }
    }

    @keyframes pulseBadge {
      0%, 100% { transform: scale(1); }
      50% { transform: scale(1.05); }
    }
  </style>
</head>
<body>
  <div id="app-splash-loader">
    <div class="splash-card">
      <div class="splash-logo-badge">G</div>
      <h1 class="splash-title">${escapedTitle}</h1>
      <p class="splash-subtitle">جاري تهيئة البوابة الذكية...</p>
      <div class="m3-linear-progress">
        <div class="m3-linear-progress-bar"></div>
      </div>
    </div>
  </div>

  <script>
    (function() {
      var hash = window.location.hash;
      if (hash && (hash.startsWith('#/') || hash.startsWith('#!/'))) {
        var cleanPath = hash.replace(/^#[!]?/, '');
        if (cleanPath.startsWith('/')) {
          window.history.replaceState(null, '', cleanPath);
        }
      }
    })();

    function dismissSplashLoader() {
      var loader = document.getElementById('app-splash-loader');
      if (loader && !loader.classList.contains('loaded')) {
        loader.classList.add('loaded');
        setTimeout(function() { loader.remove(); }, 350);
      }
    }

    window.addEventListener('flutter-first-frame', dismissSplashLoader);
    var observer = new MutationObserver(function() {
      if (document.querySelector('flutter-view') || document.querySelector('flt-glass-pane')) {
        dismissSplashLoader();
        observer.disconnect();
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
  </script>
  <!-- Flutter Web Bootstrap -->
  <script src="/flutter_bootstrap.js" async></script>
</body>
</html>`;
}

/**
 * Cloud Function to generate dynamic OpenGraph link previews for WhatsApp & Social Media
 */
exports.sharePreview = onRequest(httpsOptions, async (req, res) => {
  try {
    const rawPath = req.path || "/";
    const pathSegments = rawPath.split("/").filter(Boolean);
    const query = req.query || {};

    const routeType = pathSegments[0] || "portal"; // portal, c, p, event, ep, share
    const routeIdentifier = pathSegments[1] || query.event || query.company || "";
    const eventIdParam = query.event || "";
    const isManagerPortal = routeType === "portal" || routeType === "p" || routeType === "ep" || routeType === "ops" || routeType === "agency";

    const userAgent = (req.headers["user-agent"] || "").toLowerCase();
    const isSocialCrawler = /whatsapp|facebookexternalhit|facebot|twitterbot|telegrambot|linkedinbot|slackbot|discordbot|pinterest|bot|crawler|spider|preview/i.test(userAgent);

    let resolvedEvent = null;
    const cacheKey = `${eventIdParam || ""}:${routeIdentifier || ""}`.toLowerCase();
    const cached = eventPreviewCache.get(cacheKey);

    if (cached && Date.now() - cached.timestamp < PREVIEW_CACHE_TTL_MS) {
      resolvedEvent = cached.data;
    } else if (isSocialCrawler) {
      // Social crawlers wait for full Firestore OpenGraph metadata
      resolvedEvent = await resolveEvent(db, eventIdParam, routeIdentifier);
    } else {
      // Real user browsers: race Firestore with a 250ms timeout so we never block page load on slow cold-start queries, while warming cache in background
      resolvedEvent = await Promise.race([
        resolveEvent(db, eventIdParam, routeIdentifier),
        new Promise((resolve) => setTimeout(() => resolve(null), 250)),
      ]);
    }

    const meta = extractPreviewMetadata(resolvedEvent, query, isManagerPortal);

    // Set cache control for performance
    res.set("Cache-Control", "public, max-age=300, s-maxage=600, stale-while-revalidate=86400");
    res.set("Content-Type", "text/html; charset=utf-8");

    res.status(200).send(buildPreviewHtml(meta));
  } catch (error) {
    console.error("Error generating share preview:", error);
    // Graceful fallback to static Flutter web SPA
    res.redirect("/index.html");
  }
});

/**
 * Cloud Function: analyzeReceipt
 * Gateway cache, rate limit, and the shared Gemini callback in receipt_verification.js.
 * wahaWebhook calls the same verifyReceiptImage helper.
 */
exports.analyzeReceipt = onCall(
  // 2.0.150+211: not in the web scan path (WhatsApp / legacy only), so no minInstances.
  { ...callableOptions, secrets: [geminiApiKey], timeoutSeconds: 60 },
  async (request) => {
    if (!request.app) {
      throw new HttpsError("failed-precondition", "App Check token is required.");
    }
    const data = request.data || {};
    const { campaignId, imagePayload, forceRefresh } = data;
    if (!imagePayload) {
      throw new HttpsError("invalid-argument", "imagePayload is required");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "GEMINI_API_KEY secret is not configured on the server.",
      );
    }

    try {
      return await verifyReceiptImage({
        db,
        campaignId,
        imagePayload,
        forceRefresh: forceRefresh === true,
        apiKey,
        rateLimitKey: clientKey({
          uid: request.auth && request.auth.uid,
          rawRequest: request.rawRequest,
        }),
      });
    } catch (err) {
      console.error("Gemini gateway analysis failed:", err);
      if (err.code === 429) {
        throw new HttpsError("resource-exhausted", err.message);
      }
      throw new HttpsError("internal", err.message);
    }
  },
);

const { checkReceiptDuplicateHandler } = require("./receipt_duplicate_check");
/**
 * Server-side duplicate check for a scanned receipt (Admin SDK). Anonymous reps
 * cannot read other users' receipts under firestore.rules; this returns only
 * {duplicate, existingStatus}.
 */
exports.checkReceiptDuplicate = onCall(callableOptions, (request) =>
  checkReceiptDuplicateHandler(db, request));

const { replaceReceiptHandler } = require("./receipt_replace");
/**
 * Rep re-upload of an existing receipt (2.0.149): rejected -> re-upload,
 * approved -> replace keeping claim fields; old version kept in history.
 */
exports.replaceReceipt = onCall(callableOptions, (request) =>
  replaceReceiptHandler(db, request));

const { logReceiptSaveFailureHandler } = require("./receipt_save_failure_log");
/**
 * 2.0.155: log-only report of a failed rep receipt save (step + error code).
 * No App Check enforcement so failures caused by App Check are still logged.
 */
exports.logReceiptSaveFailure = onCall(httpsOptions, (request) =>
  logReceiptSaveFailureHandler(db, request));

const { listBranchReceiptsHandler } = require("./list_branch_receipts");
/** Rep branch history for one campaign, independent of the anonymous uid. */
exports.listBranchReceipts = onCall(callableOptions, (request) =>
  listBranchReceiptsHandler(db, request));

const { sendWinnerWhatsAppHandler } = require("./winner_whatsapp");
exports.sendWinnerWhatsApp = onCall(
  { ...callableOptions, secrets: [wahaApiKey] },
  (request) => sendWinnerWhatsAppHandler(db, request, wahaApiKey.value()),
);

const { updateBranchAllocationsHandler } = require("./branch_allocations");
/** Branch balances save + weekend settlement (company portal ops users and staff). */
exports.updateBranchAllocations = onCall(callableOptions, (request) =>
  updateBranchAllocationsHandler(db, request));

const WAHA_PROXY_ALLOWED_ORIGINS = new Set([
  "https://tashil-gift.web.app",
  "https://tashil-gift.firebaseapp.com",
  "https://gift.sw-point.com",
  "https://www.gift.sw-point.com",
]);
const WAHA_PROXY_ALLOWED_ROLES = new Set(["super_admin", "admin", "partner"]);

function applyWahaProxyCors(req, res) {
  const origin = req.headers.origin;
  if (origin && WAHA_PROXY_ALLOWED_ORIGINS.has(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
    res.set("Vary", "Origin");
  }
  res.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH");
  res.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, Accept, X-Firebase-AppCheck",
  );
  res.set("Access-Control-Max-Age", "3600");
}

async function requireWahaProxyAuth(req, res) {
  const appCheckHeader = req.headers["x-firebase-appcheck"];
  if (!appCheckHeader || typeof appCheckHeader !== "string") {
    res.status(401).json({
      error: "UNAUTHENTICATED",
      message: "Missing X-Firebase-AppCheck header.",
    });
    return null;
  }
  try {
    await admin.appCheck().verifyToken(appCheckHeader);
  } catch (err) {
    console.warn("wahaProxy App Check rejected:", err && err.message);
    res.status(401).json({
      error: "UNAUTHENTICATED",
      message: "Invalid App Check token.",
    });
    return null;
  }

  const authHeader = req.headers.authorization || "";
  const match = /^Bearer\s+(.+)$/i.exec(authHeader);
  if (!match) {
    res.status(401).json({
      error: "UNAUTHENTICATED",
      message: "Missing Authorization Bearer Firebase ID token.",
    });
    return null;
  }

  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(match[1], true);
  } catch (err) {
    console.warn("wahaProxy ID token rejected:", err && err.message);
    res.status(401).json({
      error: "UNAUTHENTICATED",
      message: "Invalid Firebase ID token.",
    });
    return null;
  }

  if (decoded.firebase && decoded.firebase.sign_in_provider === "anonymous") {
    res.status(403).json({
      error: "PERMISSION_DENIED",
      message: "Anonymous users cannot use the WhatsApp proxy.",
    });
    return null;
  }

  const role = decoded.role ? String(decoded.role) : "";
  if (!WAHA_PROXY_ALLOWED_ROLES.has(role)) {
    res.status(403).json({
      error: "PERMISSION_DENIED",
      message: "WhatsApp proxy requires role super_admin, admin, or partner.",
    });
    return null;
  }

  return decoded;
}

/**
 * Cloud Function: wahaProxy
 * Secure HTTPS Reverse Proxy for WAHA (WhatsApp HTTP API).
 * Requires Firebase ID token (role: super_admin|admin|partner) + App Check.
 * Injects WAHA_API_KEY from Firebase Secrets — never trusts a client-supplied x-api-key.
 */
exports.wahaProxy = onRequest(
  { ...httpsOptions, secrets: [wahaApiKey], cors: false },
  async (req, res) => {
    applyWahaProxyCors(req, res);

    if (req.method === "OPTIONS") {
      return res.status(204).send("");
    }

    const authed = await requireWahaProxyAuth(req, res);
    if (!authed) {
      return;
    }

    try {
      await consumeRateLimit({ db, scope: "waha", key: clientKey({ uid: authed.uid, rawRequest: req }) });
    } catch (err) {
      if (err instanceof RateLimitError) {
        res.set("Retry-After", String(err.retryAfterSec));
        return res.status(429).json({ error: "RESOURCE_EXHAUSTED", message: err.message });
      }
      console.error("wahaProxy rate limit check failed:", err);
      return res.status(503).json({ error: "RATE_LIMIT_UNAVAILABLE", message: "Try again shortly." });
    }

    try {
      let targetUrl = req.url || "/";
      // Strip leading /waha if present in the rewrite path
      if (targetUrl.startsWith("/waha")) {
        targetUrl = targetUrl.substring(5);
      }
      if (!targetUrl.startsWith("/")) {
        targetUrl = "/" + targetUrl;
      }

      // Block path traversal or non-API paths
      if (targetUrl.includes("..") || !targetUrl.startsWith("/api/")) {
        return res.status(403).json({
          error: "FORBIDDEN_PROXY_PATH",
          message: "Only /api/* WAHA endpoints are permitted through the proxy.",
        });
      }

      const secretKey = wahaApiKey.value();
      if (!secretKey) {
        return res.status(500).json({
          error: "WAHA_SECRET_MISSING",
          message: "WAHA_API_KEY secret is not configured on the server.",
        });
      }

      // Backend host may still be overridden with WAHA_BACKEND_URL env; HTTPS default after C1 hardening.
      const backendUrl = (process.env.WAHA_BACKEND_URL || "https://waha.sw-point.com") + targetUrl;

      const forwardHeaders = {
        // Server-owned secret only — never forward client X-Api-Key / Authorization.
        "x-api-key": secretKey,
      };
      if (req.headers["accept"]) {
        forwardHeaders["accept"] = req.headers["accept"];
      }

      let bodyToSend;
      if (req.method !== "GET" && req.method !== "HEAD") {
        if (req.body && typeof req.body === "object" && !Buffer.isBuffer(req.body)) {
          bodyToSend = JSON.stringify(req.body);
          forwardHeaders["content-type"] = "application/json";
        } else if (req.rawBody) {
          bodyToSend = req.rawBody;
          forwardHeaders["content-type"] = req.headers["content-type"] || "application/json";
        } else if (req.body) {
          bodyToSend = req.body;
          forwardHeaders["content-type"] = req.headers["content-type"] || "application/json";
        }
      }

      const fetchRes = await fetch(backendUrl, {
        method: req.method,
        headers: forwardHeaders,
        body: bodyToSend,
      });

      res.status(fetchRes.status);
      const contentType = fetchRes.headers.get("content-type");
      if (contentType) {
        res.set("Content-Type", contentType);
      }

      const arrayBuffer = await fetchRes.arrayBuffer();
      return res.send(Buffer.from(arrayBuffer));
    } catch (err) {
      console.error("WAHA proxy error:", err);
      return res.status(502).json({
        error: "WAHA_PROXY_UNAVAILABLE",
        message: err.message || "Failed to connect to WAHA backend",
      });
    }
  },
);

const { createGeminiGenerate } = require("./gemini_generate");
exports.geminiGenerate = createGeminiGenerate({
  geminiApiKey,
  callableOptions,
  getDb: () => db,
});

Object.assign(exports, require("./security_functions"));
const partnerPortal = require("./partner_portal");
exports.partnerPortalInfo = partnerPortal.partnerPortalInfo;
exports.partnerPortalLogin = partnerPortal.partnerPortalLogin;

/**
 * Cloud Function: wahaWebhook
 * Server-to-server WAHA receiver. Auth is WAHA_WEBHOOK_SECRET (header + HMAC), not App Check.
 * Runs on the codebase runtime (nodejs22).
 */
exports.wahaWebhook = onRequest({
  region: "us-central1",
  memory: "256MiB",
  invoker: "public",
  secrets: [wahaWebhookSecret, wahaApiKey, geminiApiKey],
}, async (req, res) => {
  return handleWahaWebhook(req, res, {
    secret: wahaWebhookSecret.value(),
    apiKey: wahaApiKey.value(),
    db: admin.firestore(),
    baseUrl: process.env.WAHA_BACKEND_URL || "https://waha.sw-point.com",
    verifyReceiptImage: (input) => verifyReceiptImage(Object.assign({}, input, {
      apiKey: geminiApiKey.value(),
    })),
    applyCampaignPrizeClaim,
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.updateWhatsappWebhookConfig = updateWhatsappWebhookConfig;
exports.manageWhatsappSenderLink = manageWhatsappSenderLink;
