const test = require("node:test");
const assert = require("node:assert");
const { consumeRateLimit, clientKey, RateLimitError, LIMITS } = require("../rate_limit");

function fakeDb() {
  const store = new Map();
  let chain = Promise.resolve();
  const db = {
    store,
    collection: (c) => ({ doc: (id) => ({ path: `${c}/${id}` }) }),
    runTransaction(fn) {
      // serialize like Firestore's optimistic retries would
      const run = chain.then(async () => {
        const writes = [];
        const tx = {
          get: async (ref) => ({ exists: store.has(ref.path), data: () => store.get(ref.path) }),
          set: (ref, v) => writes.push([ref.path, v]),
        };
        const r = await fn(tx);
        writes.forEach(([p, v]) => store.set(p, v));
        return r;
      });
      chain = run.catch(() => {});
      return run;
    },
  };
  return db;
}

test("limits are the agreed values", () => {
  assert.deepStrictEqual(LIMITS.gemini.map((w) => w.max), [20, 200]);
  assert.deepStrictEqual(LIMITS.waha.map((w) => w.max), [30, 500]);
});

test("gemini: 20 per minute then resource exhausted, no extra increment", async () => {
  const db = fakeDb();
  const now = Date.UTC(2026, 9, 27, 19, 0, 5);
  for (let i = 0; i < 20; i++) await consumeRateLimit({ db, scope: "gemini", key: "uid:a", now });
  await assert.rejects(consumeRateLimit({ db, scope: "gemini", key: "uid:a", now }), (e) => {
    assert(e instanceof RateLimitError); assert.strictEqual(e.code, 429);
    assert.strictEqual(e.window, "min"); assert.strictEqual(e.retryAfterSec, 55); return true;
  });
  const counts = [...db.store.values()].map((v) => v.count).sort();
  assert.deepStrictEqual(counts, [20, 20]);
});

test("clients are isolated and the minute window resets", async () => {
  const db = fakeDb();
  const now = Date.UTC(2026, 9, 27, 19, 0, 0);
  for (let i = 0; i < 20; i++) await consumeRateLimit({ db, scope: "gemini", key: "uid:a", now });
  await consumeRateLimit({ db, scope: "gemini", key: "uid:b", now });
  await consumeRateLimit({ db, scope: "waha", key: "uid:a", now });
  await consumeRateLimit({ db, scope: "gemini", key: "uid:a", now: now + 60000 });
});

test("daily cap applies across minutes", async () => {
  const db = fakeDb();
  const limits = [{ name: "min", windowMs: 60000, max: 2 }, { name: "day", windowMs: 86400000, max: 3 }];
  const t = Date.UTC(2026, 9, 27, 10, 0, 0);
  await consumeRateLimit({ db, scope: "x", key: "k", now: t, limits });
  await consumeRateLimit({ db, scope: "x", key: "k", now: t, limits });
  await consumeRateLimit({ db, scope: "x", key: "k", now: t + 60000, limits });
  await assert.rejects(consumeRateLimit({ db, scope: "x", key: "k", now: t + 120000, limits }), /x\/day/);
});

test("concurrent requests never exceed the max", async () => {
  const db = fakeDb();
  const now = Date.now();
  const results = await Promise.allSettled(
    Array.from({ length: 40 }, () => consumeRateLimit({ db, scope: "waha", key: "uid:z", now })));
  assert.strictEqual(results.filter((r) => r.status === "fulfilled").length, 30);
});

test("docs carry a TTL expireAt and hashed ids (no raw uid/ip)", async () => {
  const db = fakeDb();
  await consumeRateLimit({ db, scope: "gemini", key: "uid:secret-uid", now: 0 });
  for (const [path, v] of db.store) {
    assert(path.startsWith("rateLimits/gemini_")); assert(!path.includes("secret-uid"));
    assert(v.expireAt instanceof Date);
  }
});

test("clientKey prefers uid, falls back to hashed first X-Forwarded-For IP", () => {
  assert.strictEqual(clientKey({ uid: "u1" }), "uid:u1");
  const a = clientKey({ rawRequest: { headers: { "x-forwarded-for": "1.2.3.4, 10.0.0.1" } } });
  const b = clientKey({ rawRequest: { headers: {}, ip: "1.2.3.4" } });
  assert.strictEqual(a, b); assert(a.startsWith("ip:")); assert(!a.includes("1.2.3.4"));
});
