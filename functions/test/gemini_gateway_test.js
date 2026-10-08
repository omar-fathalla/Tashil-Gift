const assert = require("assert");
const {
  campaignBranchesCache,
  campaignProductsCache,
  receiptAnalysisCache,
  computeSha256,
  geminiRateLimiter,
  acquireRateLimitToken,
  executeWithExponentialBackoff,
  analyzeReceiptWithGateway,
} = require("../gemini_gateway");

async function runTests() {
  console.log("🧪 Starting Gemini Gateway & LRU Caching Tests...");

  // Test 1: Deterministic SHA-256 Hashing
  const hash1 = computeSha256("test_receipt_image_buffer_1");
  const hash2 = computeSha256("test_receipt_image_buffer_1");
  const hash3 = computeSha256("test_receipt_image_buffer_2");
  assert.strictEqual(hash1, hash2, "Identical inputs must produce identical SHA-256 hashes");
  assert.notStrictEqual(hash1, hash3, "Different inputs must produce different hashes");
  console.log("✅ Test 1: SHA-256 hashing is deterministic.");

  // Test 2: LRU Caching of Campaign Branches and Products
  campaignBranchesCache.set("campaign_123", ["الفرع الرئيسي", "سموحة", "ستانلي"]);
  assert.deepStrictEqual(
    campaignBranchesCache.get("campaign_123"),
    ["الفرع الرئيسي", "سموحة", "ستانلي"],
    "Branches must be retrieved accurately from LRU cache"
  );

  campaignProductsCache.set("campaign_123", ["تريزيمي 400 مل", "صانسيلك 350 مل"]);
  assert.deepStrictEqual(
    campaignProductsCache.get("campaign_123"),
    ["تريزيمي 400 مل", "صانسيلك 350 مل"],
    "Products must be retrieved accurately from LRU cache"
  );
  console.log("✅ Test 2: LRU caching for campaign metadata works.");

  // Test 3: Rate Limiter Token Acquisition
  const remainingTokens = await acquireRateLimitToken();
  assert(remainingTokens >= 0, "Token acquisition must succeed with non-negative tokens");
  console.log("✅ Test 3: RateLimiter successfully consumed token. Remaining:", remainingTokens);

  // Test 4: Exponential Backoff Retry on 429 Error
  let attempts = 0;
  const result = await executeWithExponentialBackoff(
    async () => {
      attempts++;
      if (attempts < 3) {
        const error = new Error("ResourceExhausted: 429 quota limit hit");
        error.code = 429;
        throw error;
      }
      return { success: true, attempts };
    },
    { initialDelayMs: 50, maxDelayMs: 200, maxRetries: 3 }
  );

  assert.strictEqual(result.success, true, "Operation must succeed after retry");
  assert.strictEqual(attempts, 3, "Operation must have retried twice before succeeding");
  console.log("✅ Test 4: Exponential backoff retried on 429 and succeeded on attempt 3.");

  // Test 5: End-to-End analyzeReceiptWithGateway Caching
  const testPayload = "dummy_base64_receipt_data_abc";
  let geminiCalls = 0;

  const mockGemini = async () => {
    geminiCalls++;
    return {
      isValid: true,
      receiptNumber: "TEST-001",
      targetCompanyTotal: 500,
    };
  };

  // First call: Should miss cache and call Gemini
  const response1 = await analyzeReceiptWithGateway({
    campaignId: "campaign_123",
    imagePayload: testPayload,
    callGeminiModelFn: mockGemini,
  });
  assert.strictEqual(response1.cached, false, "First call must not be cached");
  assert.strictEqual(geminiCalls, 1, "Gemini must be called once on first invocation");

  // Second call: Should hit LRU cache in 0ms!
  const response2 = await analyzeReceiptWithGateway({
    campaignId: "campaign_123",
    imagePayload: testPayload,
    callGeminiModelFn: mockGemini,
  });
  assert.strictEqual(response2.cached, true, "Second call must hit cache");
  assert.strictEqual(geminiCalls, 1, "Gemini must NOT be called on cache hit");
  assert.strictEqual(response2.result.receiptNumber, "TEST-001");
  console.log("✅ Test 5: End-to-end receipt analysis LRU cache returned in 0ms without hitting API.");

  console.log("\n🎉 All 5 Gemini Gateway & LRU Caching tests passed successfully!\n");
}

runTests().catch((err) => {
  console.error("❌ Test failed:", err);
  process.exit(1);
});
