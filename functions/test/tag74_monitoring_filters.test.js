/**
 * TAG-74: the log-based metrics in tool/monitoring/setup_alerts.sh must keep
 * matching what the functions actually log. Renaming a log field without
 * updating the script would silently stop the alerts.
 */
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..");
const script = fs.readFileSync(path.join(root, "tool/monitoring/setup_alerts.sh"), "utf8");
const read = (f) => fs.readFileSync(path.join(root, "functions", f), "utf8");

test("claim failures: recordClaimFailure logs fn=decrementCampaignPrize at WARNING", () => {
  assert.match(script, /jsonPayload\.fn=\\"decrementCampaignPrize\\" AND severity>=WARNING/);
  const src = read("security_functions.js");
  const body = src.slice(src.indexOf("async function recordClaimFailure"), src.indexOf("async function recordClaimFailure") + 800);
  assert.match(body, /severity: "WARNING"/);
  assert.match(body, /fn: "decrementCampaignPrize"/);
});

test("receipt save failures: logger.warn(\"receipt_save_failure\")", () => {
  assert.match(script, /jsonPayload\.message=\\"receipt_save_failure\\"/);
  assert.match(read("receipt_save_failure_log.js"), /logger\.warn\("receipt_save_failure"/);
});

test("gemini errors: console.error lines start with geminiGenerate", () => {
  assert.match(script, /textPayload:\\"geminiGenerate\\" AND severity>=ERROR/);
  const src = read("gemini_generate.js");
  assert.match(src, /console\.error\("geminiGenerate network error:/);
  assert.match(src, /console\.error\("geminiGenerate upstream error:/);
});

test("the script never names the production project", () => {
  assert.doesNotMatch(script, /tashil-gift(?!-dev)\b/);
});
