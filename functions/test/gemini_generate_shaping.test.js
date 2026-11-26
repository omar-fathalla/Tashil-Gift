const test = require("node:test");
const assert = require("node:assert/strict");
const { defineSecret } = require("firebase-functions/params");
const { createGeminiGenerate } = require("../gemini_generate");
const { MODELS, ALLOWED_MODEL_IDS, isGemini4 } = require("../ai_models");
const {
  GEMINI_4_MAX_OUTPUT_TOKENS,
  shapeGenerationConfig,
  summarizeUsage,
  logGeminiUsage,
} = require("../gemini_request_shaping");

const HYDROGEN = "gemini-4-hydrogen";

test("isGemini4 matches only the real gemini-4-* ids", () => {
  for (const id of ["gemini-4-hydrogen", "gemini-4-neon", "gemini-4-carbon", "gemini-4-argon"]) {
    assert.equal(isGemini4(id), true, id);
  }
  for (const id of ["gemini-4.0", "gemini-3.8-flash", "gemini-2.5-flash", "", null, undefined]) {
    assert.equal(isGemini4(id), false, String(id));
  }
});

test("gemini-4.0 is not a registered model id", () => {
  assert.equal(MODELS.GEMINI_40, undefined);
  assert.equal(ALLOWED_MODEL_IDS.includes("gemini-4.0"), false);
  assert.equal(MODELS.GEMINI_4_HYDROGEN, HYDROGEN);
  assert.ok(ALLOWED_MODEL_IDS.includes(HYDROGEN));
  assert.equal(MODELS.GEMINI_36_FLASH, "gemini-3.6-flash");
  assert.equal(MODELS.GEMINI_38_FLASH, "gemini-3.8-flash");
});

test("Gemini 4: sampling params are removed and the token cap is raised", () => {
  const input = {
    temperature: 0.0,
    topP: 0.9,
    topK: 40,
    top_p: 0.9,
    top_k: 40,
    maxOutputTokens: 8192,
    responseMimeType: "application/json",
    responseSchema: { type: "OBJECT" },
  };
  const snapshot = JSON.parse(JSON.stringify(input));
  const out = shapeGenerationConfig(HYDROGEN, input);
  for (const key of ["temperature", "topP", "topK", "top_p", "top_k"]) {
    assert.equal(key in out, false, key);
  }
  assert.equal(out.maxOutputTokens, GEMINI_4_MAX_OUTPUT_TOKENS);
  assert.equal(GEMINI_4_MAX_OUTPUT_TOKENS, 65536);
  assert.equal(out.responseMimeType, "application/json");
  assert.deepEqual(out.responseSchema, { type: "OBJECT" });
  assert.deepEqual(input, snapshot, "input must not be mutated");
});

test("Gemini 4: an absent maxOutputTokens stays absent and an over-cap value is clamped", () => {
  assert.equal("maxOutputTokens" in shapeGenerationConfig(HYDROGEN, { temperature: 0 }), false);
  assert.equal(shapeGenerationConfig(HYDROGEN, { maxOutputTokens: 100000 }).maxOutputTokens, 65536);
  assert.equal(shapeGenerationConfig("gemini-4-neon", { maxOutputTokens: 1024 }).maxOutputTokens, 65536);
});

test("Gemini 4: thinkingLevel minimal becomes low and thinkingBudget maps to a level", () => {
  const shape = (thinkingConfig) => shapeGenerationConfig(HYDROGEN, { thinkingConfig }).thinkingConfig;
  assert.deepEqual(shape({ thinkingLevel: "minimal" }), { thinkingLevel: "low" });
  assert.deepEqual(shape({ thinkingLevel: "MINIMAL" }), { thinkingLevel: "low" });
  assert.deepEqual(shape({ thinkingLevel: "low" }), { thinkingLevel: "low" });
  assert.deepEqual(shape({ thinkingLevel: "medium" }), { thinkingLevel: "medium" });
  assert.deepEqual(shape({ thinkingLevel: "xhigh" }), { thinkingLevel: "xhigh" });
  assert.deepEqual(shape({ thinkingBudget: 0 }), { thinkingLevel: "low" });
  assert.deepEqual(shape({ thinkingBudget: 1024 }), { thinkingLevel: "low" });
  assert.deepEqual(shape({ thinkingBudget: 4096 }), { thinkingLevel: "medium" });
  assert.deepEqual(shape({ thinkingBudget: 24576 }), { thinkingLevel: "high" });
  assert.deepEqual(shape({ thinkingLevel: "bogus" }), {});
  assert.deepEqual(shape({ thinkingLevel: "medium", thinkingBudget: 1024 }), { thinkingLevel: "medium" });
  assert.deepEqual(shape({ includeThoughts: true, thinkingBudget: 1024 }), { includeThoughts: true, thinkingLevel: "low" });
});

test("3.x and 2.x requests are returned untouched (same object)", () => {
  for (const model of ["gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.6-flash", "gemini-2.5-flash", "gemini-3.8-pro"]) {
    const input = {
      temperature: 0.0,
      topP: 0.95,
      topK: 40,
      maxOutputTokens: 8192,
      thinkingConfig: { thinkingLevel: "minimal", thinkingBudget: 0 },
    };
    const snapshot = JSON.stringify(input);
    const out = shapeGenerationConfig(model, input);
    assert.equal(out, input, model);
    assert.equal(JSON.stringify(out), snapshot, model);
  }
  assert.equal(shapeGenerationConfig("gemini-3.8-flash", undefined), undefined);
});

test("summarizeUsage and logGeminiUsage emit counts only", () => {
  const payload = {
    candidates: [{ content: { parts: [{ text: "SECRET RECEIPT TEXT" }] } }],
    usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 20, thoughtsTokenCount: 30, totalTokenCount: 150 },
  };
  assert.deepEqual(summarizeUsage(payload), {
    promptTokens: 100,
    candidatesTokens: 20,
    thoughtsTokens: 30,
    totalTokens: 150,
  });
  assert.deepEqual(summarizeUsage(null), { promptTokens: 0, candidatesTokens: 0, thoughtsTokens: 0, totalTokens: 0 });

  const lines = [];
  const originalLog = console.log;
  console.log = (...args) => lines.push(args.join(" "));
  try {
    logGeminiUsage({ source: "test", model: HYDROGEN, latencyMs: 12, payload });
  } finally {
    console.log = originalLog;
  }
  assert.equal(lines.length, 1);
  assert.match(lines[0], /^gemini_usage /);
  assert.doesNotMatch(lines[0], /SECRET RECEIPT TEXT/);
  const logged = JSON.parse(lines[0].slice("gemini_usage ".length));
  assert.deepEqual(logged, {
    source: "test",
    model: HYDROGEN,
    latencyMs: 12,
    status: 200,
    promptTokens: 100,
    candidatesTokens: 20,
    thoughtsTokens: 30,
    totalTokens: 150,
  });
});

async function callProxy(model, generationConfig, extra = {}) {
  const previousKey = process.env.GEMINI_API_KEY;
  const originalFetch = global.fetch;
  const originalLog = console.log;
  process.env.GEMINI_API_KEY = "test-key-not-a-real-secret";
  console.log = () => {};
  let seen = null;
  global.fetch = async (url, init) => {
    seen = { url: String(url), body: JSON.parse(init.body) };
    return {
      ok: true,
      status: 200,
      text: async () => JSON.stringify({
        candidates: [{ content: { parts: [{ text: "{}" }] } }],
        usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1, totalTokenCount: 2 },
      }),
    };
  };
  try {
    const fn = createGeminiGenerate({
      geminiApiKey: defineSecret("GEMINI_API_KEY"),
      callableOptions: {},
    });
    await fn.run({
      app: { appId: "test" },
      auth: { uid: "u1" },
      rawRequest: {},
      data: { model, contents: [{ role: "user", parts: [{ text: "hi" }] }], generationConfig, ...extra },
    });
  } finally {
    global.fetch = originalFetch;
    console.log = originalLog;
    if (previousKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = previousKey;
  }
  return seen;
}

test("geminiGenerate shapes Gemini 4 requests before calling upstream", async () => {
  const seen = await callProxy(HYDROGEN, {
    temperature: 0.0,
    topP: 0.9,
    maxOutputTokens: 8192,
    responseMimeType: "application/json",
    thinkingConfig: { thinkingLevel: "minimal" },
  });
  assert.match(seen.url, /\/models\/gemini-4-hydrogen:generateContent\?key=/);
  assert.deepEqual(seen.body.generationConfig, {
    maxOutputTokens: 65536,
    responseMimeType: "application/json",
    thinkingConfig: { thinkingLevel: "low" },
  });
});

test("geminiGenerate forwards 3.x generationConfig byte-identical", async () => {
  const config = {
    temperature: 0.0,
    maxOutputTokens: 8192,
    responseMimeType: "application/json",
    thinkingConfig: { thinkingLevel: "low" },
  };
  const seen = await callProxy("gemini-3.8-flash", config);
  assert.equal(JSON.stringify(seen.body.generationConfig), JSON.stringify(config));
  assert.deepEqual(Object.keys(seen.body).sort(), ["contents", "generationConfig"]);
});

test("geminiGenerate returns prior model turns and thought signatures to Gemini unchanged", async () => {
  const history = [
    { role: "user", parts: [{ text: "first question" }] },
    {
      role: "model",
      parts: [
        { text: "thinking summary", thought: true, thoughtSignature: "c2lnbmF0dXJl" },
        { text: "answer one", thoughtSignature: "c2lnMg==" },
        { functionCall: { name: "lookup", args: { q: 1 } }, thoughtSignature: "c2lnMw==" },
      ],
    },
    { role: "user", parts: [{ text: "follow-up" }] },
  ];
  const snapshot = JSON.stringify(history);
  const previousKey = process.env.GEMINI_API_KEY;
  const originalFetch = global.fetch;
  const originalLog = console.log;
  process.env.GEMINI_API_KEY = "test-key-not-a-real-secret";
  console.log = () => {};
  let sent = null;
  global.fetch = async (_url, init) => {
    sent = JSON.parse(init.body);
    return { ok: true, status: 200, text: async () => "{}" };
  };
  try {
    const fn = createGeminiGenerate({ geminiApiKey: defineSecret("GEMINI_API_KEY"), callableOptions: {} });
    await fn.run({
      app: { appId: "test" },
      auth: { uid: "u1" },
      rawRequest: {},
      data: { model: HYDROGEN, contents: history, generationConfig: { temperature: 0 } },
    });
  } finally {
    global.fetch = originalFetch;
    console.log = originalLog;
    if (previousKey === undefined) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = previousKey;
  }
  assert.equal(JSON.stringify(sent.contents), snapshot);
});
