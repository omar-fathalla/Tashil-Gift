const test = require("node:test");
const assert = require("node:assert");
const env = require("../env_config");

test("unknown project (unit tests, local) defaults to production values", () => {
  assert.strictEqual(env.projectId({}), "tashil-gift");
  assert.strictEqual(env.envLabel({}), "prod");
  assert.strictEqual(env.publicSiteOrigin({}), "https://tashil-gift.web.app");
});

test("production keeps exactly the old WAHA proxy origin list", () => {
  const prod = { GCLOUD_PROJECT: "tashil-gift" };
  assert.deepStrictEqual([...env.wahaProxyAllowedOrigins(prod)].sort(), [
    "https://gift.sw-point.com",
    "https://tashil-gift.firebaseapp.com",
    "https://tashil-gift.web.app",
    "https://www.gift.sw-point.com",
  ]);
  assert.strictEqual(env.isWahaProxyOriginAllowed("https://tashil-gift-dev.web.app", prod), false);
  assert.strictEqual(env.isWahaProxyOriginAllowed("https://tashil-gift--pr-41-abc.web.app", prod), false);
  assert.strictEqual(env.isWahaProxyOriginAllowed(undefined, prod), false);
});

test("tashil-gift-dev is dev and only allows its own hosts", () => {
  const dev = { GCLOUD_PROJECT: "tashil-gift-dev" };
  assert.strictEqual(env.envLabel(dev), "dev");
  assert.strictEqual(env.isDev(dev), true);
  assert.strictEqual(env.publicSiteOrigin(dev), "https://tashil-gift-dev.web.app");
  assert.strictEqual(env.isWahaProxyOriginAllowed("https://tashil-gift-dev.web.app", dev), true);
  assert.strictEqual(env.isWahaProxyOriginAllowed("https://tashil-gift-dev--pr-7-x1y2.web.app", dev), true);
  assert.strictEqual(env.isWahaProxyOriginAllowed("https://tashil-gift.web.app", dev), false);
  assert.strictEqual(env.isWahaProxyOriginAllowed("https://evil-tashil-gift-dev--x.web.app", dev), false);
});

test("FIREBASE_CONFIG and PUBLIC_SITE_ORIGIN are honoured", () => {
  const e = { FIREBASE_CONFIG: JSON.stringify({ projectId: "tashil-gift-dev" }), PUBLIC_SITE_ORIGIN: "https://dev.example.com/" };
  assert.strictEqual(env.projectId(e), "tashil-gift-dev");
  assert.strictEqual(env.publicSiteOrigin(e), "https://dev.example.com");
  assert.strictEqual(env.publicSiteOrigin({ PUBLIC_SITE_ORIGIN: "javascript:alert(1)" }), "https://tashil-gift.web.app");
});

test("the dev env file holds no secrets and the code has no hard-coded prod URL", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const dir = path.join(__dirname, "..");
  const envFile = fs.readFileSync(path.join(dir, ".env.tashil-gift-dev"), "utf8");
  assert.doesNotMatch(envFile, /^\s*[A-Z_]*(KEY|SECRET|TOKEN|PASSWORD)[A-Z_]*\s*=/m);
  assert.doesNotMatch(envFile, /AIza[0-9A-Za-z_-]{20,}/);
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith(".js") && n !== "env_config.js")) {
    const src = fs.readFileSync(path.join(dir, f), "utf8");
    assert.doesNotMatch(src, /https:\/\/tashil-gift\.(web\.app|firebaseapp\.com)/, `${f} hard-codes a production URL`);
  }
});
