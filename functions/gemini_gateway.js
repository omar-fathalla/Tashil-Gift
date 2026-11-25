const LRU = require("lru-cache");
const { consumeRateLimit } = require("./rate_limit");
const crypto = require("node:crypto");
const { withEventContent } = require("./campaign_content");

/**
 * 1. LRU Caches for Campaign Metadata & Recurring Invoices
 */
// Cache for campaign branches (TTL: 1 hour, max: 500 campaigns)
const campaignBranchesCache = new LRU({
  max: 500,
  maxAge: 1000 * 60 * 60,
});

// Cache for campaign eligible products and barcodes (TTL: 1 hour, max: 500 campaigns)
const campaignProductsCache = new LRU({
  max: 500,
  maxAge: 1000 * 60 * 60,
});

// Cache for duplicate receipt OCR analysis keyed by SHA-256 image hash (TTL: 24 hours, max: 1000)
const receiptAnalysisCache = new LRU({
  max: 1000,
  maxAge: 1000 * 60 * 60 * 24,
});

/**
 * 2. Per-client rate limiting (M3). Replaces the old shared in-memory
 * 60/min token bucket, which was global and per-instance. Uses the shared
 * "gemini" budget (20/min, 200/day per client) in Firestore.
 * @param {object} db Firestore
 * @param {string} rateLimitKey client key from rate_limit.clientKey()
 */
async function acquireRateLimitToken(db, rateLimitKey) {
  if (!db || !rateLimitKey) return null; // server-side callers without a client (webhook)
  return consumeRateLimit({ db, scope: "gemini", key: rateLimitKey });
}

/**
 * Computes a deterministic SHA-256 fingerprint hash for a string or buffer.
 * @param {string|Buffer} content
 * @returns {string} Hex hash string
 */
function computeSha256(content) {
  return crypto.createHash("sha256").update(content).digest("hex");
}

/**
 * 3. Exponential Backoff & Retry Logic
 * Retries on HTTP 429 (ResourceExhausted) and 503 (Unavailable) errors.
 *
 * @param {Function} asyncFn Async operation to execute
 * @param {Object} options Retry configuration
 * @param {number} attempt Current retry attempt index
 * @returns {Promise<any>}
 */
async function executeWithExponentialBackoff(asyncFn, options = {}, attempt = 0) {
  const maxRetries = options.maxRetries ?? 3;
  const initialDelayMs = options.initialDelayMs ?? 1000;
  const maxDelayMs = options.maxDelayMs ?? 8000;

  try {
    return await asyncFn();
  } catch (err) {
    const nextAttempt = attempt + 1;
    const isRateLimit =
      err?.code === 429 ||
      err?.status === 429 ||
      (typeof err?.message === "string" &&
        (err.message.includes("429") || err.message.includes("RESOURCE_EXHAUSTED")));
    const isUnavailable = err?.code === 503 || err?.status === 503;

    if ((isRateLimit || isUnavailable) && nextAttempt <= maxRetries) {
      const exponentialDelay = Math.min(maxDelayMs, initialDelayMs * (2 ** (nextAttempt - 1)));
      const jitter = crypto.randomInt(0, 400);
      const delay = exponentialDelay + jitter;

      console.warn(
        `[GeminiGateway] HTTP ${err?.code || 429} encountered on attempt ${nextAttempt}. Retrying in ${delay}ms with exponential backoff...`
      );
      await new Promise((resolve) => setTimeout(resolve, delay));
      return executeWithExponentialBackoff(asyncFn, options, nextAttempt);
    }
    throw err;
  }
}

/**
 * Retrieves campaign branches from cache or loads and caches from Firestore.
 */
async function getCachedCampaignBranches(db, campaignId) {
  if (!campaignId) return [];
  const cached = campaignBranchesCache.get(campaignId);
  if (cached) return cached;

  const doc = await db.collection("events").doc(campaignId).get();
  if (!doc.exists) return [];
  const data = doc.data() || {};
  const branches = data.branchNames || data.allowedBranches || [];
  campaignBranchesCache.set(campaignId, branches);
  return branches;
}

/**
 * Retrieves campaign eligible products from cache or loads and caches from Firestore.
 */
async function getCachedCampaignProducts(db, campaignId) {
  if (!campaignId) return [];
  const cached = campaignProductsCache.get(campaignId);
  if (cached) return cached;

  const doc = await db.collection("events").doc(campaignId).get();
  if (!doc.exists) return [];
  // TAG-56: products may live in events/{id}/content.
  const data = await withEventContent(db, campaignId, doc.data() || {});
  const products = data.requiredProducts || data.eligibleProducts || [];
  campaignProductsCache.set(campaignId, products);
  return products;
}

/**
 * Main Receipt Analysis Handler incorporating Caching, Rate Limiting, and Retry Logic.
 */
async function analyzeReceiptWithGateway({
  db,
  campaignId,
  imagePayload, // Base64 string or image buffer
  forceRefresh = false,
  rateLimitKey,
  callGeminiModelFn, // Callback function executing the Gemini model
}) {
  const startTime = Date.now();

  // 1. Compute Image Fingerprint
  const imageHash = computeSha256(imagePayload);

  // 2. Check LRU Cache for Duplicate Invoices
  if (!forceRefresh) {
    const cachedResult = receiptAnalysisCache.get(imageHash);
    if (cachedResult) {
      return {
        cached: true,
        cacheKey: imageHash,
        latencyMs: Date.now() - startTime,
        result: cachedResult,
      };
    }
  }

  // 3. Acquire Token from Rate Limiter
  await acquireRateLimitToken(db, rateLimitKey);

  // 4. Resolve Cached Campaign Metadata
  let branches = [];
  let products = [];
  if (db && campaignId) {
    [branches, products] = await Promise.all([
      getCachedCampaignBranches(db, campaignId),
      getCachedCampaignProducts(db, campaignId),
    ]);
  }

  // 5. Execute Gemini Analysis with Exponential Backoff Protection
  const result = await executeWithExponentialBackoff(async () => {
    return await callGeminiModelFn({
      branches,
      products,
      imageHash,
    });
  });

  // 6. Cache Valid Results in LRU Cache
  if (result?.isValid !== undefined) {
    receiptAnalysisCache.set(imageHash, result);
  }

  return {
    cached: false,
    cacheKey: imageHash,
    latencyMs: Date.now() - startTime,
    result,
  };
}

module.exports = {
  campaignBranchesCache,
  campaignProductsCache,
  receiptAnalysisCache,
  acquireRateLimitToken,
  computeSha256,
  executeWithExponentialBackoff,
  getCachedCampaignBranches,
  getCachedCampaignProducts,
  analyzeReceiptWithGateway,
};
