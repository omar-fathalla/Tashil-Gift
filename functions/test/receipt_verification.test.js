const test = require("node:test");
const assert = require("node:assert/strict");
const { callGeminiForReceipt, verifyReceiptImage } = require("../receipt_verification");

test("callGeminiForReceipt parses Gemini JSON and fails closed on a bad body", async () => {
  const original = global.fetch;
  try {
    global.fetch = async (url, init) => {
      assert.match(String(url), /gemini-2\.0-flash:generateContent/);
      const body = JSON.parse(init.body);
      assert.equal(body.generationConfig.temperature, 0.1);
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
