const test = require("node:test");
const assert = require("node:assert");
const {
  COLLECTION, LOCKOUT_STEPS_MS, LoginThrottledError, beginLoginAttempt, normalizeIdentifier, recordLoginSuccess, throttleKey,
} = require("../login_throttle");

function fakeDb() {
  const store = new Map();
  let chain = Promise.resolve();
  const db = {
    store,
    collection: (c) => ({
      doc: (id) => ({ path: `${c}/${id}`, delete: async () => { store.delete(`${c}/${id}`); } }),
    }),
    runTransaction(fn) {
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

const MIN = 60 * 1000;
const T0 = Date.UTC(2026, 10, 15, 8, 0, 0);
const attempt = (db, identifier, now, ip = "1.1.1.1") => beginLoginAttempt({ db, identifier, ip, now });
const rejectsWith = (p, sec) => assert.rejects(p, (e) => {
  assert(e instanceof LoginThrottledError);
  if (sec !== undefined) assert.strictEqual(e.retryAfterSec, sec);
  return true;
});

test("keys are namespaced sha256 of the normalized value, never raw", async () => {
  assert.strictEqual(normalizeIdentifier("  Brand_583 "), "brand_583");
  const db = fakeDb();
  await attempt(db, " Brand_583 ", T0, "9.9.9.9");
  const ids = [...db.store.keys()].map((k) => k.slice(COLLECTION.length + 1)).sort();
  assert.deepStrictEqual(ids, [throttleKey("id", "brand_583"), throttleKey("ip", "9.9.9.9")].sort());
  assert.ok(ids.every((k) => /^[0-9a-f]{64}$/.test(k)));
  const docs = JSON.stringify([...db.store.values()]);
  assert.ok(!docs.includes("brand_583") && !docs.includes("9.9.9.9"));
  assert.ok([...db.store.values()].every((d) => d.expireAt instanceof Date));
});

test("5 attempts lock for 15 min; case/space variants share the lock", async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) await attempt(db, i % 2 ? "USER" : " user ", T0 + i * 1000, `10.0.0.${i}`);
  await rejectsWith(attempt(db, "user", T0 + 5000, "10.0.1.1"), 15 * 60 - 1);
  await attempt(db, "user", T0 + 4000 + 15 * MIN, "10.0.1.1");
});

test("lockouts escalate 15m, 1h, 6h, then cap at 24h", async () => {
  const db = fakeDb();
  let t = T0;
  const expected = [15 * MIN, 60 * MIN, 6 * 60 * MIN, 24 * 60 * MIN, 24 * 60 * MIN];
  assert.deepStrictEqual(LOCKOUT_STEPS_MS, expected.slice(0, 4));
  for (const lock of expected) {
    for (let i = 0; i < 5; i++) await attempt(db, "victim", t, `10.1.${i}.1`);
    await rejectsWith(attempt(db, "victim", t + 1000, "10.2.0.1"), lock / 1000 - 1);
    t += lock;
  }
});

test("success resets failures and lockout level", async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) await attempt(db, "u", T0, `10.3.${i}.1`);
  let t = T0 + 15 * MIN;
  for (let i = 0; i < 4; i++) await attempt(db, "u", t, `10.4.${i}.1`);
  const a = await attempt(db, "u", t, "10.5.0.1");
  await recordLoginSuccess({ db, idKey: a.idKey });
  t += 1000;
  for (let i = 0; i < 5; i++) await attempt(db, "u", t, `10.6.${i}.1`);
  await rejectsWith(attempt(db, "u", t, "10.7.0.1"), 15 * 60);
});

test("failure window slides: old failures expire after 15 min", async () => {
  const db = fakeDb();
  for (let i = 0; i < 4; i++) await attempt(db, "w", T0, `10.8.${i}.1`);
  for (let i = 0; i < 4; i++) await attempt(db, "w", T0 + 15 * MIN, `10.9.${i}.1`);
});

test("IP cap: 20 attempts per 10 min across identifiers, no writes when blocked", async () => {
  const db = fakeDb();
  for (let i = 0; i < 20; i++) await attempt(db, `user${i}`, T0 + i, "6.6.6.6");
  const before = JSON.stringify([...db.store.entries()]);
  await rejectsWith(attempt(db, "fresh", T0 + 60 * 1000, "6.6.6.6"), 9 * 60);
  assert.strictEqual(JSON.stringify([...db.store.entries()]), before);
  await attempt(db, "fresh", T0 + 60 * 1000, "7.7.7.7");
  await attempt(db, "fresh2", T0 + 10 * MIN, "6.6.6.6");
});

test("expired docs are ignored even if TTL has not deleted them", async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) await attempt(db, "z", T0, `10.10.${i}.1`);
  const key = `${COLLECTION}/${throttleKey("id", "z")}`;
  const doc = db.store.get(key);
  db.store.set(key, { ...doc, expireAt: new Date(T0 + 1000) });
  await attempt(db, "z", T0 + 2000, "10.11.0.1");
  assert.strictEqual(db.store.get(key).level, 0);
});
