/**
 * Shared Gemini generateContent proxy.
 * Client never holds GEMINI_API_KEY — this Function injects it from Secrets.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");
const { ALLOWED_MODEL_IDS, GEMINI_UPSTREAM_TIMEOUT_MS } = require("./ai_models");
const { shapeGenerationConfig, logGeminiUsage } = require("./gemini_request_shaping");

const ALLOWED_MODELS = new Set(ALLOWED_MODEL_IDS);

const MODEL_PATTERN = /^gemini-[\w.\-]+$/;
const MAX_PAYLOAD_CHARS = 12 * 1024 * 1024; // ~12 MiB serialized request

function normalizeModelName(raw) {
  let name = String(raw || "").trim();
  if (name.startsWith("models/")) name = name.slice("models/".length);
  return name;
}

function assertModelAllowed(model) {
  if (!model || !MODEL_PATTERN.test(model)) {
    throw new HttpsError("invalid-argument", "Invalid Gemini model name.");
  }
  if (!ALLOWED_MODELS.has(model) && !model.startsWith("gemini-")) {
    throw new HttpsError("invalid-argument", "Model is not on the allow-list.");
  }
  // Soft allow: any gemini-* that matches pattern (project uses evolving model ids).
  if (!ALLOWED_MODELS.has(model) && !MODEL_PATTERN.test(model)) {
    throw new HttpsError("invalid-argument", `Model not allowed: ${model}`);
  }
}

function estimateInlineBytes(contents) {
  if (!Array.isArray(contents)) return 0;
  let total = 0;
  for (const content of contents) {
    const parts = content && content.parts;
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (!part || typeof part !== "object") continue;
      const inline = part.inlineData || part.inline_data;
      if (inline && typeof inline.data === "string") {
        total += inline.data.length;
      }
      if (typeof part.text === "string") {
        total += part.text.length;
      }
    }
  }
  return total;
}

/**
 * @param {object} options
 * @param {import('firebase-functions/params').SecretParam} options.geminiApiKey
 * @param {object} options.callableOptions
 */
function createGeminiGenerate({ geminiApiKey, callableOptions, getDb }) {
  return onCall(
    {
      ...callableOptions,
      secrets: [geminiApiKey],
      // 2.0.150+211: upstream call aborts at 38s; function cap 60s; one warm
      // instance so a rep's scan never waits for a cold start.
      timeoutSeconds: 60,
      memory: "256MiB",
      minInstances: 1,
    },
    async (request) => {
      if (!request.app) {
        throw new HttpsError("failed-precondition", "App Check token is required.");
      }
      if (!request.auth || !request.auth.uid) {
        throw new HttpsError(
          "unauthenticated",
          "Authentication is required (anonymous auth is OK).",
        );
      }

      if (getDb) {
        try {
          await consumeRateLimit({
            db: getDb(),
            scope: "gemini",
            key: clientKey({ uid: request.auth.uid, rawRequest: request.rawRequest }),
          });
        } catch (err) {
          if (err instanceof RateLimitError) {
            throw new HttpsError("resource-exhausted", err.message, { retryAfterSec: err.retryAfterSec });
          }
          throw err;
        }
      }

      const data = request.data || {};
      const model = normalizeModelName(data.model);
      assertModelAllowed(model);

      const contents = data.contents;
      if (!Array.isArray(contents) || contents.length === 0) {
        throw new HttpsError("invalid-argument", "contents[] is required.");
      }

      // Cap total payload size (text + base64 inline data).
      let serialized;
      try {
        serialized = JSON.stringify(data);
      } catch (_) {
        throw new HttpsError("invalid-argument", "Request payload is not serializable.");
      }
      if (serialized.length > MAX_PAYLOAD_CHARS) {
        throw new HttpsError(
          "invalid-argument",
          `Request payload too large (${serialized.length} chars, max ${MAX_PAYLOAD_CHARS}).`,
        );
      }
      const inlineBytes = estimateInlineBytes(contents);
      if (inlineBytes > MAX_PAYLOAD_CHARS) {
        throw new HttpsError("invalid-argument", "Inline media payload too large.");
      }

      const apiKey = geminiApiKey.value();
      if (!apiKey) {
        throw new HttpsError(
          "failed-precondition",
          "GEMINI_API_KEY secret is not configured on the server.",
        );
      }

      const body = {
        contents,
      };
      if (data.systemInstruction) {
        body.systemInstruction = data.systemInstruction;
      }
      if (data.generationConfig) {
        body.generationConfig = shapeGenerationConfig(model, data.generationConfig);
      }
      if (Array.isArray(data.safetySettings) && data.safetySettings.length > 0) {
        body.safetySettings = data.safetySettings;
      }
      if (data.tools) body.tools = data.tools;
      if (data.toolConfig) body.toolConfig = data.toolConfig;

      const url =
        "https://generativelanguage.googleapis.com/v1beta/models/" +
        encodeURIComponent(model) +
        ":generateContent?key=" +
        encodeURIComponent(apiKey);

      const startedAt = Date.now();
      let response;
      try {
        response = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(GEMINI_UPSTREAM_TIMEOUT_MS),
        });
      } catch (err) {
        if (err && (err.name === "TimeoutError" || err.name === "AbortError")) {
          console.warn(`geminiGenerate upstream timeout after ${GEMINI_UPSTREAM_TIMEOUT_MS}ms (model ${model})`);
          throw new HttpsError("deadline-exceeded", "Gemini did not answer in time.");
        }
        console.error("geminiGenerate network error:", err);
        throw new HttpsError("unavailable", "Failed to reach Gemini API.");
      }

      const responseText = await response.text();
      let parsed;
      try {
        parsed = JSON.parse(responseText);
      } catch (_) {
        parsed = { rawText: responseText.slice(0, 500) };
      }

      if (!response.ok) {
        const message =
          (parsed && parsed.error && parsed.error.message) ||
          `Gemini HTTP ${response.status}`;
        console.error("geminiGenerate upstream error:", response.status, message);
        logGeminiUsage({
          source: "geminiGenerate",
          model,
          latencyMs: Date.now() - startedAt,
          payload: parsed,
          status: response.status,
        });
        if (response.status === 429) {
          throw new HttpsError("resource-exhausted", message);
        }
        if (response.status === 400) {
          throw new HttpsError("invalid-argument", message);
        }
        throw new HttpsError("internal", message);
      }

      logGeminiUsage({
        source: "geminiGenerate",
        model,
        latencyMs: Date.now() - startedAt,
        payload: parsed,
      });
      return { response: parsed };
    },
  );
}

module.exports = { createGeminiGenerate, ALLOWED_MODELS, normalizeModelName };
