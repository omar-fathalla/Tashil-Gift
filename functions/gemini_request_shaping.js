/**
 * Request shaping and usage logging shared by every server-side Gemini call
 * (geminiGenerate proxy and the receipt verifier).
 *
 * Gemini 4 migration rules (https://ai.google.dev/gemini-api/docs/whats-new-gemini-4-hydrogen):
 *  - temperature / topP / topK must be removed (out-of-range values return 400).
 *  - output cap is 65,536 per request; low caps truncate because thinking
 *    tokens count toward it.
 *  - thinking is controlled by `thinkingLevel` (low | medium | high | xhigh);
 *    `minimal` returns an error.
 * Requests for every other model are returned untouched (same object).
 */
const { isGemini4 } = require("./ai_models");

/** Output token cap for Gemini 4. Lower to 32768 if eval cost per call grows too much. */
const GEMINI_4_MAX_OUTPUT_TOKENS = 65536;

const GEMINI_4_THINKING_LEVELS = Object.freeze(["low", "medium", "high", "xhigh"]);

const SAMPLING_KEYS = Object.freeze(["temperature", "topP", "topK", "top_p", "top_k"]);

/** thinkingBudget (tokens, 2.x/3.x style) -> thinkingLevel. 0 means "off", which Gemini 4 cannot do. */
function thinkingLevelForBudget(budget) {
  if (!Number.isFinite(budget) || budget <= 1024) return "low";
  if (budget <= 8192) return "medium";
  return "high";
}

function shapeThinkingConfig(thinkingConfig) {
  if (!thinkingConfig || typeof thinkingConfig !== "object") return thinkingConfig;
  const shaped = { ...thinkingConfig };
  const hasBudget = Object.prototype.hasOwnProperty.call(shaped, "thinkingBudget");
  const budget = shaped.thinkingBudget;
  delete shaped.thinkingBudget;

  let level = typeof shaped.thinkingLevel === "string" ? shaped.thinkingLevel.trim().toLowerCase() : undefined;
  if (level === "minimal") level = "low";
  if (level !== undefined && !GEMINI_4_THINKING_LEVELS.includes(level)) level = undefined;
  if (level === undefined && hasBudget) level = thinkingLevelForBudget(Number(budget));

  if (level === undefined) {
    delete shaped.thinkingLevel;
  } else {
    shaped.thinkingLevel = level;
  }
  return shaped;
}

/**
 * @param {string} model normalized model id
 * @param {object|undefined} generationConfig request generationConfig
 * @returns {object|undefined} the same object for non-Gemini-4 models, a shaped copy otherwise
 */
function shapeGenerationConfig(model, generationConfig) {
  if (!isGemini4(model)) return generationConfig;
  if (!generationConfig || typeof generationConfig !== "object") return generationConfig;

  const shaped = { ...generationConfig };
  for (const key of SAMPLING_KEYS) delete shaped[key];

  const cap = Number(shaped.maxOutputTokens);
  if (shaped.maxOutputTokens !== undefined && Number.isFinite(cap)) {
    shaped.maxOutputTokens = GEMINI_4_MAX_OUTPUT_TOKENS;
  }

  if (shaped.thinkingConfig !== undefined) {
    shaped.thinkingConfig = shapeThinkingConfig(shaped.thinkingConfig);
  }
  return shaped;
}

/** Counts only. Never includes prompt text, image data or keys. */
function summarizeUsage(payload) {
  const usage = (payload && typeof payload === "object" && payload.usageMetadata) || {};
  const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  return {
    promptTokens: num(usage.promptTokenCount),
    candidatesTokens: num(usage.candidatesTokenCount),
    thoughtsTokens: num(usage.thoughtsTokenCount),
    totalTokens: num(usage.totalTokenCount),
  };
}

function logGeminiUsage({ source, model, latencyMs, payload, status }) {
  const line = {
    source,
    model,
    latencyMs,
    status: status === undefined ? 200 : status,
    ...summarizeUsage(payload),
  };
  console.log("gemini_usage " + JSON.stringify(line));
  return line;
}

module.exports = {
  GEMINI_4_MAX_OUTPUT_TOKENS,
  GEMINI_4_THINKING_LEVELS,
  shapeGenerationConfig,
  summarizeUsage,
  logGeminiUsage,
};
