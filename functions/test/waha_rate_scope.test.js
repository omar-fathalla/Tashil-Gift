const test = require("node:test");
const assert = require("node:assert");
const { wahaRateLimitScope } = require("../waha_rate_scope");
const { LIMITS } = require("../rate_limit");

test("session status, QR, screenshot and session control use wahaControl", () => {
  assert.strictEqual(wahaRateLimitScope("GET", "/waha/api/sessions/default"), "wahaControl");
  assert.strictEqual(wahaRateLimitScope("GET", "/api/sessions?all=true"), "wahaControl");
  assert.strictEqual(wahaRateLimitScope("GET", "/waha/api/default/auth/qr"), "wahaControl");
  assert.strictEqual(wahaRateLimitScope("GET", "/waha/api/screenshot?session=default"), "wahaControl");
  for (const a of ["restart", "start", "stop", "logout"]) {
    assert.strictEqual(wahaRateLimitScope("POST", `/waha/api/sessions/default/${a}`), "wahaControl");
  }
});

test("sending and everything else stays on the waha scope", () => {
  assert.strictEqual(wahaRateLimitScope("POST", "/waha/api/sendFile"), "waha");
  assert.strictEqual(wahaRateLimitScope("POST", "/waha/api/sendText"), "waha");
  assert.strictEqual(wahaRateLimitScope("GET", "/waha/api/contacts/check-exists?phone=1&session=default"), "waha");
  assert.strictEqual(wahaRateLimitScope("POST", "/waha/api/startTyping"), "waha");
  assert.strictEqual(wahaRateLimitScope("DELETE", "/waha/api/sessions/default"), "waha");
  assert.strictEqual(wahaRateLimitScope("POST", "/waha/api/sessions/default/../x/restart"), "waha");
});

test("wahaControl limits exist", () => {
  assert.deepStrictEqual(LIMITS.wahaControl.map((w) => w.max), [60, 3000]);
  assert.deepStrictEqual(LIMITS.waha.map((w) => w.max), [30, 500]);
});
