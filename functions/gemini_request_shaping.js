/**
 * Request shaping and usage logging shared by every server-side Gemini call
 * (geminiGenerate proxy and the receipt verifier).
 *
 * Gemini 4 migration rules (https://ai.google.dev/gemini-api/docs/whats-new-gemini-4-hydrogen):
 *  - temperature / topP / topK must be removed (out-of-range values return 400).
 *  - output cap is per model (65,536 Hydrogen/Neon, 32,768 Carbon/Argon); low
 *    caps truncate because thinking tokens count toward it.
 *  - thinking is controlled by `thinkingLevel` (low | medium | high, plus xhigh
 *    on Hydrogen/Neon); `minimal` returns an error. A request without a usable
 *    level gets `low` (the API default is `high`).
 * Requests for every other model are returned untouched (same object).
 */
const { isGemini4 } = require("./ai_models");

const SAMPLING_KEYS = Object.freeze(["temperature", "topP", "topK", "top_p", "top_k"]);

/** Thinking level sent when a Gemini 4 request does not carry a usable one (the API default is `high`). */
const GEMINI_4_DEFAULT_THINKING_LEVEL = "low";

const HYDROGEN_NEON_LIMITS = Object.freeze({
  maxOutputTokens: 65536,
  thinkingLevels: Object.freeze(["low", "medium", "high", "xhigh"]),
});

const CARBON_ARGON_LIMITS = Object.freeze({
  maxOutputTokens: 32768,
  thinkingLevels: Object.freeze(["low", "medium", "high"]),
});

/**
 * Per-model Gemini 4 limits. Hydrogen and Neon: 65,536 output tokens and
 * `xhigh` allowed. Carbon and Argon: 32,768 and `high` is the maximum level.
 * Any other gemini-4-* id gets the conservative Carbon/Argon limits.
 */
function gemini4Limits(model) {
  const id = String(model || "").trim();
  if (/^gemini-4-(hydrogen|neon)$/.test(id)) return HYDROGEN_NEON_LIMITS;
  return CARBON_ARGON_LIMITS;
}

/** thinkingBudget (tokens, 2.x/3.x style) -> thinkingLevel. 0 means "off", which Gemini 4 cannot do. */
function thinkingLevelForBudget(budget) {
  if (!Number.isFinite(budget) || budget <= 1024) return "low";
  if (budget <= 8192) return "medium";
  return "high";
}

function shapeThinkingConfig(thinkingConfig, limits) {
  const shaped = thinkingConfig && typeof thinkingConfig === "object" ? { ...thinkingConfig } : {};
  const hasBudget = Object.prototype.hasOwnProperty.call(shaped, "thinkingBudget");
  const budget = shaped.thinkingBudget;
  delete shaped.thinkingBudget;

  let level = typeof shaped.thinkingLevel === "string" ? shaped.thinkingLevel.trim().toLowerCase() : undefined;
  if (level === "minimal") level = "low";
  if (level === "xhigh" && !limits.thinkingLevels.includes("xhigh")) level = "high";
  if (level !== undefined && !limits.thinkingLevels.includes(level)) level = undefined;
  if (level === undefined && hasBudget) level = thinkingLevelForBudget(Number(budget));

  shaped.thinkingLevel = level === undefined ? GEMINI_4_DEFAULT_THINKING_LEVEL : level;
  return shaped;
}

/**
 * @param {string} model normalized model id
 * @param {object|undefined} generationConfig request generationConfig
 * @returns {object|undefined} the same value for non-Gemini-4 models. For Gemini 4 a shaped
 *   copy that always carries an explicit thinkingLevel, even when the request had no
 *   generationConfig or no thinkingConfig.
 */
function shapeGenerationConfig(model, generationConfig) {
  if (!isGemini4(model)) return generationConfig;
  const limits = gemini4Limits(model);

  const shaped = generationConfig && typeof generationConfig === "object" ? { ...generationConfig } : {};
  for (const key of SAMPLING_KEYS) delete shaped[key];

  const cap = Number(shaped.maxOutputTokens);
  if (shaped.maxOutputTokens !== undefined && Number.isFinite(cap)) {
    shaped.maxOutputTokens = limits.maxOutputTokens;
  }

  shaped.thinkingConfig = shapeThinkingConfig(shaped.thinkingConfig, limits);
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
  GEMINI_4_DEFAULT_THINKING_LEVEL,
  gemini4Limits,
  shapeGenerationConfig,
  summarizeUsage,
  logGeminiUsage,
};
