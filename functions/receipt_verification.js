const { defineString } = require("firebase-functions/params");
const { analyzeReceiptWithGateway } = require("./gemini_gateway");
const {
  RECEIPT_VERIFICATION_DEFAULT_MODEL,
  GEMINI_UPSTREAM_TIMEOUT_MS,
  isGemini4,
} = require("./ai_models");
const { shapeGenerationConfig, logGeminiUsage } = require("./gemini_request_shaping");

/**
 * Model for the server-side verifier. Set per project in functions/.env.<projectId>;
 * projects without a value (prod) keep the code default.
 */
const receiptVerificationModel = defineString("RECEIPT_VERIFICATION_MODEL", {
  default: RECEIPT_VERIFICATION_DEFAULT_MODEL,
});

function resolveReceiptVerificationModel() {
  const value = String(receiptVerificationModel.value() || "").trim();
  return value || RECEIPT_VERIFICATION_DEFAULT_MODEL;
}

const RECEIPT_MAX_OUTPUT_TOKENS = 4096;

const RECEIPT_RESPONSE_SCHEMA = Object.freeze({
  type: "OBJECT",
  properties: {
    isValid: { type: "BOOLEAN" },
    receiptNumber: { type: "STRING" },
    storeChainDetected: { type: "STRING" },
    branchDetected: { type: "STRING" },
    isBranchMatched: { type: "BOOLEAN" },
    confidence: { type: "NUMBER" },
    message: { type: "STRING" },
  },
  required: [
    "isValid",
    "receiptNumber",
    "storeChainDetected",
    "branchDetected",
    "isBranchMatched",
    "message",
  ],
  propertyOrdering: [
    "isValid",
    "receiptNumber",
    "storeChainDetected",
    "branchDetected",
    "isBranchMatched",
    "confidence",
    "message",
  ],
});

/** Builds the generateContent body. Exported so tests and the eval can reuse it. */
function buildReceiptRequest({ model, prompt, mimeType, base64Data }) {
  const generationConfig = {
    temperature: 0.1,
    maxOutputTokens: RECEIPT_MAX_OUTPUT_TOKENS,
    responseMimeType: "application/json",
    responseSchema: RECEIPT_RESPONSE_SCHEMA,
  };
  if (isGemini4(model)) {
    generationConfig.thinkingConfig = { thinkingLevel: "low" };
  }
  return {
    contents: [
      {
        role: "user",
        parts: [
          { text: prompt },
          { inline_data: { mime_type: mimeType, data: base64Data } },
        ],
      },
    ],
    generationConfig: shapeGenerationConfig(model, generationConfig),
  };
}

/**
 * Gemini callback shared by the analyzeReceipt callable and the WhatsApp webhook.
 * This is the functions-side verifier (gateway cache, rate limit, and this request).
 * Flutter prompts stay in AiReceiptService and go through geminiGenerate; they are
 * not copied here.
 */
async function callGeminiForReceipt({ apiKey, imagePayload, branches, products, imageHash }) {
  let mimeType = "image/jpeg";
  let base64Data = imagePayload;
  if (typeof imagePayload === "string" && imagePayload.startsWith("data:")) {
    const match = imagePayload.match(/^data:([^;]+);base64,(.+)$/s);
    if (match) {
      mimeType = match[1];
      base64Data = match[2];
    }
  }

  const prompt =
    "You are a retail receipt OCR assistant for Tashil Gift. " +
    "Extract structured fields and decide if the receipt is valid for the campaign. " +
    "Known branches: " + JSON.stringify(branches || []) + ". " +
    "Eligible products: " + JSON.stringify(products || []) + ". " +
    "Respond with ONLY compact JSON keys: isValid (bool), receiptNumber, storeChainDetected, " +
    "branchDetected, isBranchMatched (bool), confidence (number 0 to 1), message.";

  const model = resolveReceiptVerificationModel();
  const url =
    "https://generativelanguage.googleapis.com/v1beta/models/" +
    encodeURIComponent(model) +
    ":generateContent?key=" +
    encodeURIComponent(apiKey);

  const startedAt = Date.now();
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(buildReceiptRequest({ model, prompt, mimeType, base64Data })),
    // 2.0.150+211: never hang on a slow upstream call.
    signal: AbortSignal.timeout(GEMINI_UPSTREAM_TIMEOUT_MS),
  });

  if (!response.ok) {
    const errBody = await response.text();
    logGeminiUsage({
      source: "receiptVerification",
      model,
      latencyMs: Date.now() - startedAt,
      payload: null,
      status: response.status,
    });
    const error = new Error("Gemini HTTP " + response.status + ": " + errBody.slice(0, 300));
    error.code = response.status;
    throw error;
  }

  const payload = await response.json();
  logGeminiUsage({
    source: "receiptVerification",
    model,
    latencyMs: Date.now() - startedAt,
    payload,
  });
  const text =
    (((payload || {}).candidates || [])[0] || {}).content?.parts
      ?.map((p) => p.text || "")
      .join("") || "";
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (jsonMatch) {
    try {
      const parsed = JSON.parse(jsonMatch[0]);
      return {
        isValid: parsed.isValid === true,
        receiptNumber: String(parsed.receiptNumber || ("EXT-" + imageHash.substring(0, 8).toUpperCase())),
        storeChainDetected: String(parsed.storeChainDetected || ""),
        branchDetected: String(parsed.branchDetected || (branches[0] || "")),
        isBranchMatched: parsed.isBranchMatched === true,
        confidence: typeof parsed.confidence === "number" ? parsed.confidence : null,
        message: String(parsed.message || "تم التحليل عبر Gemini Gateway"),
      };
    } catch (_) {
      // fall through
    }
  }

  return {
    isValid: false,
    receiptNumber: "EXT-" + imageHash.substring(0, 8).toUpperCase(),
    storeChainDetected: "",
    branchDetected: branches[0] || "",
    isBranchMatched: false,
    message: "تعذر تفسير رد Gemini",
    rawText: text.slice(0, 500),
  };
}

/**
 * Same return value analyzeReceipt sends to the app:
 * { cached, cacheKey, latencyMs, result }.
 * `apiKey` is GEMINI_API_KEY. Without it the call fails closed.
 */
async function verifyReceiptImage({
  db,
  campaignId,
  imagePayload,
  forceRefresh = false,
  apiKey,
  rateLimitKey,
  callGeminiModelFn,
}) {
  const modelFn = callGeminiModelFn || (async ({ branches, products, imageHash }) => {
    if (!apiKey) {
      const error = new Error("GEMINI_API_KEY secret is not configured on the server.");
      error.code = "failed-precondition";
      throw error;
    }
    return callGeminiForReceipt({
      apiKey,
      imagePayload,
      branches,
      products,
      imageHash,
    });
  });

  return analyzeReceiptWithGateway({
    db,
    campaignId,
    imagePayload,
    forceRefresh,
    rateLimitKey,
    callGeminiModelFn: modelFn,
  });
}

module.exports = {
  RECEIPT_RESPONSE_SCHEMA,
  RECEIPT_MAX_OUTPUT_TOKENS,
  buildReceiptRequest,
  resolveReceiptVerificationModel,
  callGeminiForReceipt,
  verifyReceiptImage,
};
