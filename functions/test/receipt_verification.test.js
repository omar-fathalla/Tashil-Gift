const test = require("node:test");
const assert = require("node:assert/strict");
const {
  callGeminiForReceipt,
  verifyReceiptImage,
  buildReceiptRequest,
  resolveReceiptVerificationModel,
  RECEIPT_RESPONSE_SCHEMA,
} = require("../receipt_verification");
const { RECEIPT_VERIFICATION_DEFAULT_MODEL } = require("../ai_models");

test("callGeminiForReceipt parses Gemini JSON and fails closed on a bad body", async () => {
  const original = global.fetch;
  try {
    global.fetch = async (url, init) => {
      assert.match(String(url), /\/gemini-3\.8-flash:generateContent/);
      const body = JSON.parse(init.body);
      assert.equal(body.generationConfig.temperature, 0.1);
      assert.equal(body.generationConfig.responseMimeType, "application/json");
      assert.deepEqual(body.generationConfig.responseSchema, RECEIPT_RESPONSE_SCHEMA);
      assert.equal(body.contents[0].parts[1].inline_data.data, "abc");
      return {
        ok: true,
        json: async () => ({
          candidates: [{
            content: { parts: [{ text: '{"isValid":true,"receiptNumber":"R-9","message":"ok"}' }] },
          }],
        }),
      };
    };
    const result = await callGeminiForReceipt({
      apiKey: "k",
      imagePayload: "abc",
      branches: ["Main"],
      products: [],
      imageHash: "abcdef1234567890",
    });
    assert.equal(result.isValid, true);
    assert.equal(result.receiptNumber, "R-9");

    global.fetch = async () => ({
      ok: true,
      json: async () => ({ candidates: [{ content: { parts: [{ text: "not json" }] } }] }),
    });
    const rejected = await callGeminiForReceipt({
      apiKey: "k",
      imagePayload: "abc",
      branches: [],
      products: [],
      imageHash: "abcdef1234567890",
    });
    assert.equal(rejected.isValid, false);
    assert.equal(rejected.message, "تعذر تفسير رد Gemini");
  } finally {
    global.fetch = original;
  }
});

test("verifyReceiptImage uses the shared Gemini callback", async () => {
  const original = global.fetch;
  global.fetch = async () => ({
    ok: true,
    json: async () => ({
      candidates: [{ content: { parts: [{ text: '{"isValid":false,"message":"blurry"}' }] } }],
    }),
  });
  try {
    const verified = await verifyReceiptImage({
      db: null,
      campaignId: "",
      imagePayload: "webhook-image-bytes",
      apiKey: "secret",
    });
    assert.equal(verified.cached, false);
    assert.equal(verified.result.isValid, false);
    assert.equal(verified.result.message, "blurry");
  } finally {
    global.fetch = original;
  }
});

test("verifyReceiptImage refuses to call Gemini without an API key", async () => {
  const original = global.fetch;
  let called = false;
  global.fetch = async () => {
    called = true;
    return { ok: true, json: async () => ({}) };
  };
  try {
    await assert.rejects(
      () => verifyReceiptImage({
        db: null,
        campaignId: "",
        imagePayload: "no-key-image",
        apiKey: "",
      }),
      /GEMINI_API_KEY/,
    );
    assert.equal(called, false);
  } finally {
    global.fetch = original;
  }
});

function withModelEnv(value, fn) {
  const previous = process.env.RECEIPT_VERIFICATION_MODEL;
  if (value === undefined) delete process.env.RECEIPT_VERIFICATION_MODEL;
  else process.env.RECEIPT_VERIFICATION_MODEL = value;
  return Promise.resolve()
    .then(fn)
    .finally(() => {
      if (previous === undefined) delete process.env.RECEIPT_VERIFICATION_MODEL;
      else process.env.RECEIPT_VERIFICATION_MODEL = previous;
    });
}

test("the verifier model is the shut-down-safe default, never gemini-2.0-flash", () => {
  assert.equal(RECEIPT_VERIFICATION_DEFAULT_MODEL, "gemini-3.8-flash");
  return withModelEnv(undefined, () => {
    assert.equal(resolveReceiptVerificationModel(), "gemini-3.8-flash");
  });
});

test("the verifier model comes from the RECEIPT_VERIFICATION_MODEL param", async () => {
  const original = global.fetch;
  try {
    await withModelEnv("gemini-4-hydrogen", async () => {
      assert.equal(resolveReceiptVerificationModel(), "gemini-4-hydrogen");
      let seenUrl = "";
      let seenBody = null;
      global.fetch = async (url, init) => {
        seenUrl = String(url);
        seenBody = JSON.parse(init.body);
        return {
          ok: true,
          json: async () => ({
            candidates: [{ content: { parts: [{ text: '{"isValid":true,"message":"ok"}' }] } }],
            usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5, thoughtsTokenCount: 3, totalTokenCount: 18 },
          }),
        };
      };
      const result = await callGeminiForReceipt({
        apiKey: "k",
        imagePayload: "abc",
        branches: [],
        products: [],
        imageHash: "abcdef1234567890",
      });
      assert.equal(result.isValid, true);
      assert.match(seenUrl, /\/gemini-4-hydrogen:generateContent/);
      const cfg = seenBody.generationConfig;
      assert.equal("temperature" in cfg, false);
      assert.equal(cfg.maxOutputTokens, 65536);
      assert.deepEqual(cfg.thinkingConfig, { thinkingLevel: "low" });
      assert.equal(cfg.responseMimeType, "application/json");
    });
    await withModelEnv("   ", () => {
      assert.equal(resolveReceiptVerificationModel(), "gemini-3.8-flash");
    });
  } finally {
    global.fetch = original;
  }
});

test("the receipt response schema covers every field the verifier returns", () => {
  const keys = ["isValid", "receiptNumber", "storeChainDetected", "branchDetected", "isBranchMatched", "confidence", "message"];
  assert.deepEqual(Object.keys(RECEIPT_RESPONSE_SCHEMA.properties).sort(), [...keys].sort());
  assert.ok(RECEIPT_RESPONSE_SCHEMA.required.includes("isValid"));
  assert.equal(RECEIPT_RESPONSE_SCHEMA.required.includes("confidence"), false);
});

test("3.x verifier requests keep temperature 0.1 and send no thinkingConfig", () => {
  const body = buildReceiptRequest({ model: "gemini-3.8-flash", prompt: "p", mimeType: "image/png", base64Data: "d" });
  assert.equal(body.generationConfig.temperature, 0.1);
  assert.equal("thinkingConfig" in body.generationConfig, false);
  assert.ok(body.generationConfig.maxOutputTokens > 1024);
});

test("JSON wrapped in prose is still parsed by the regex fallback", async () => {
  const original = global.fetch;
  try {
    global.fetch = async () => ({
      ok: true,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: 'sure: {"isValid":true,"receiptNumber":"R-1","message":"ok"} done' }] } }],
      }),
    });
    const result = await callGeminiForReceipt({
      apiKey: "k",
      imagePayload: "abc",
      branches: [],
      products: [],
      imageHash: "abcdef1234567890",
    });
    assert.equal(result.isValid, true);
    assert.equal(result.receiptNumber, "R-1");
  } finally {
    global.fetch = original;
  }
});
