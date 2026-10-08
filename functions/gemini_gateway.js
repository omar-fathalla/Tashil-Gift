const LRU = require("lru-cache");
const { RateLimiter } = require("limiter");
const retryRequest = require("retry-request");
const crypto = require("crypto");

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
 * 2. Rate Limiting via Token Bucket (limiter)
 * 60 requests per minute with a burst allowance of 10 requests.
 */
const geminiRateLimiter = new RateLimiter(60, "minute", true);

/**
 * Acquires a token from the rate limiter.
 * @returns {Promise<number>} Remaining tokens
 */
function acquireRateLimitToken() {
  return new Promise((resolve, reject) => {
    geminiRateLimiter.removeTokens(1, (err, remaining) => {
      if (err) return reject(err);
      if (remaining < 0) {
        const error = new Error("Rate limit exceeded. Please retry after a brief pause.");
        error.code = 429;
        return reject(error);
      }
      resolve(remaining);
    });
  });
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
 * 3. Exponential Backoff & Retry Logic (retry-request / custom backoff loop)
 * Retries on HTTP 429 (ResourceExhausted) and 503 (Unavailable) errors.
 *
 * @param {Function} asyncFn Async operation to execute
 * @param {Object} options Retry configuration
 * @returns {Promise<any>}
 */
async function executeWithExponentialBackoff(asyncFn, options = {}) {
  const maxRetries = options.maxRetries || 3;
  const initialDelayMs = options.initialDelayMs || 1000;
  const maxDelayMs = options.maxDelayMs || 8000;

  let attempt = 0;
  while (true) {
    try {
      return await asyncFn();
    } catch (err) {
      attempt++;
      const isRateLimit =
        err.code === 429 ||
        err.status === 429 ||
        (err.message && (err.message.includes("429") || err.message.includes("RESOURCE_EXHAUSTED")));
      const isUnavailable = err.code === 503 || err.status === 503;

      if ((isRateLimit || isUnavailable) && attempt <= maxRetries) {
        const exponentialDelay = Math.min(maxDelayMs, initialDelayMs * Math.pow(2, attempt - 1));
        const jitter = Math.floor(Math.random() * 400);
        const delay = exponentialDelay + jitter;

        console.warn(
          `[GeminiGateway] HTTP ${err.code || 429} encountered on attempt ${attempt}. Retrying in ${delay}ms with exponential backoff...`
        );
        await new Promise((resolve) => setTimeout(resolve, delay));
      } else {
        throw err;
      }
    }
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
  const data = doc.data() || {};
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
  await acquireRateLimitToken();

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
  if (result && result.isValid !== undefined) {
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
  geminiRateLimiter,
  acquireRateLimitToken,
  computeSha256,
  executeWithExponentialBackoff,
  getCachedCampaignBranches,
  getCachedCampaignProducts,
  analyzeReceiptWithGateway,
};
