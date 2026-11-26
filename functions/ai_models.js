/**
 * Single source of truth for Gemini model ids used by Cloud Functions.
 * Flutter-side mirror: lib/core/constants/ai_models.dart.
 */
const MODELS = Object.freeze({
  GEMINI_15_FLASH: "gemini-1.5-flash",
  GEMINI_15_PRO: "gemini-1.5-pro",
  GEMINI_20_FLASH: "gemini-2.0-flash",
  GEMINI_20_FLASH_001: "gemini-2.0-flash-001",
  GEMINI_20_FLASH_LITE: "gemini-2.0-flash-lite",
  GEMINI_25_FLASH: "gemini-2.5-flash",
  GEMINI_25_PRO: "gemini-2.5-pro",
  GEMINI_36_FLASH: "gemini-3.6-flash",
  GEMINI_37_FLASH: "gemini-3.7-flash",
  GEMINI_38_FLASH: "gemini-3.8-flash",
  GEMINI_38_PRO: "gemini-3.8-pro",
  GEMINI_38_ULTRA: "gemini-3.8-ultra",
  GEMINI_4_HYDROGEN: "gemini-4-hydrogen",
});

/** True for any Gemini 4 family id (`gemini-4-hydrogen`, `-neon`, `-carbon`, `-argon`). */
function isGemini4(model) {
  return /^gemini-4-/.test(String(model || "").trim());
}

/**
 * Code default for the server-side receipt verifier (analyzeReceipt + WhatsApp
 * webhook). The live value comes from the RECEIPT_VERIFICATION_MODEL function
 * param (see receipt_verification.js); gemini-2.0-flash was shut down on
 * 2026-06-01 so it is no longer a valid default.
 */
const RECEIPT_VERIFICATION_DEFAULT_MODEL = MODELS.GEMINI_38_FLASH;

/**
 * 2.0.150+211: hard cap for one upstream Gemini call made by a Cloud Function
 * (geminiGenerate, analyzeReceipt / WhatsApp verifier). Client waits 40s per call.
 */
const GEMINI_UPSTREAM_TIMEOUT_MS = 38000;

/** Aliases / legacy names still accepted by the geminiGenerate proxy. */
const LEGACY_ALIASES = Object.freeze([
  "gemini-flash-tier",
  "gemini-multimodal",
  "gemini-multimodal-audio",
  "gemini-pro",
  "gemini-pro-vision",
]);

const ALLOWED_MODEL_IDS = Object.freeze([
  ...Object.values(MODELS),
  ...LEGACY_ALIASES,
]);

module.exports = {
  MODELS,
  RECEIPT_VERIFICATION_DEFAULT_MODEL,
  GEMINI_UPSTREAM_TIMEOUT_MS,
  LEGACY_ALIASES,
  ALLOWED_MODEL_IDS,
  isGemini4,
};
