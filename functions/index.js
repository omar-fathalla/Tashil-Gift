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
const { handleSharePreview, SHARE_PREVIEW_MAX_INSTANCES } = require("./share_preview");

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

// firebase.json rewrites /c/** and the other preview prefixes to this
// function with the original path intact (it is not stripped to "/").
// Only /c/<digits> is served. maxInstances bounds a path-fuzzing flood.
exports.sharePreview = onRequest(
  { ...httpsOptions, maxInstances: SHARE_PREVIEW_MAX_INSTANCES },
  (req, res) => handleSharePreview(req, res, db),
);

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
