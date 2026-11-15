const test = require("node:test");
const assert = require("node:assert");
const {
  COLLECTION, LOCKOUT_STEPS_MS, LoginThrottledError, beginLoginAttempt, loginClientIp, normalizeIdentifier,
  recordLoginSuccess, throttleKey, throttleKeys,
} = require("../login_throttle");

function fakeDb() {
  const store = new Map();
  let chain = Promise.resolve();
  const db = {
    store,
    collection: (c) => ({ doc: (id) => ({ path: `${c}/${id}` }) }),
    runTransaction(fn) {
      const run = chain.then(async () => {
        const writes = [];
        const tx = {
          get: async (ref) => ({ exists: store.has(ref.path), data: () => store.get(ref.path) }),
          set: (ref, v) => writes.push([ref.path, v]),
          delete: (ref) => writes.push([ref.path, undefined]),
        };
        const r = await fn(tx);
        writes.forEach(([p, v]) => (v === undefined ? store.delete(p) : store.set(p, v)));
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
let ipSeq = 0;
const freshIp = () => `10.${(++ipSeq >> 16) & 255}.${(ipSeq >> 8) & 255}.${ipSeq & 255}`;
const attempt = (db, identifier, now, ip = freshIp()) => beginLoginAttempt({ db, identifier, ip, now });
const rejectsWith = (p, sec) => assert.rejects(p, (e) => {
  assert(e instanceof LoginThrottledError);
  if (sec !== undefined) assert.strictEqual(e.retryAfterSec, sec);
  return true;
});
const doc = (db, key) => db.store.get(`${COLLECTION}/${key}`);

test("client IP is the rightmost X-Forwarded-For entry, else req.ip", () => {
  assert.strictEqual(loginClientIp({ headers: { "x-forwarded-for": "6.6.6.6, 1.2.3.4" }, ip: "9.9.9.9" }), "1.2.3.4");
  assert.strictEqual(loginClientIp({ headers: { "x-forwarded-for": " 1.2.3.4 " } }), "1.2.3.4");
  assert.strictEqual(loginClientIp({ headers: { "x-forwarded-for": "1.2.3.4, " } }), "1.2.3.4");
  assert.strictEqual(loginClientIp({ headers: {}, ip: "9.9.9.9" }), "9.9.9.9");
  assert.strictEqual(loginClientIp({ headers: { "x-forwarded-for": " , " }, ip: "9.9.9.9" }), "9.9.9.9");
});

test("spoofed leading XFF values cannot bypass the IP cap", async () => {
  const db = fakeDb();
  const req = (i) => ({ headers: { "x-forwarded-for": `${i}.${i}.${i}.${i}, 8.8.4.4` } });
  for (let i = 0; i < 20; i++) await attempt(db, `spoof${i}`, T0, loginClientIp(req(i)));
  await rejectsWith(attempt(db, "spoof-new", T0, loginClientIp(req(99))), 10 * 60);
});

test("keys are namespaced sha256 of normalized values, never raw", async () => {
  assert.strictEqual(normalizeIdentifier("  Brand_583 "), "brand_583");
  const db = fakeDb();
  const keys = await attempt(db, " Brand_583 ", T0, "9.9.9.9");
  assert.deepStrictEqual(keys, {
    userIpKey: throttleKey("idip", "brand_583|9.9.9.9"),
    userKey: throttleKey("id", "brand_583"),
    ipKey: throttleKey("ip", "9.9.9.9"),
  });
  assert.strictEqual(keys.userIpKey, throttleKeys("BRAND_583", "9.9.9.9").userIpKey);
  const ids = [...db.store.keys()].map((k) => k.slice(COLLECTION.length + 1)).sort();
  assert.deepStrictEqual(ids, Object.values(keys).sort());
  assert.ok(ids.every((k) => /^[0-9a-f]{64}$/.test(k)));
  const docs = JSON.stringify([...db.store.values()]);
  assert.ok(!docs.includes("brand_583") && !docs.includes("9.9.9.9"));
  assert.ok([...db.store.values()].every((d) => d.expireAt instanceof Date));
});

test("5 attempts from one IP lock username+IP for 15 min; other IPs are not locked out", async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) await attempt(db, i % 2 ? "USER" : " user ", T0 + i * 1000, "5.5.5.5");
  await rejectsWith(attempt(db, "user", T0 + 5000, "5.5.5.5"), 15 * 60 - 1);
  await attempt(db, "user", T0 + 5000, "7.7.7.7");
  await attempt(db, "user", T0 + 4000 + 15 * MIN, "5.5.5.5");
});

test("username+IP lockouts escalate 15m, 1h, 6h, then cap at 24h", async () => {
  const db = fakeDb();
  let t = T0;
  const expected = [15 * MIN, 60 * MIN, 6 * 60 * MIN, 24 * 60 * MIN, 24 * 60 * MIN];
  assert.deepStrictEqual(LOCKOUT_STEPS_MS, expected.slice(0, 4));
  for (const lock of expected) {
    for (let i = 0; i < 5; i++) await attempt(db, "victim", t, "4.4.4.4");
    await rejectsWith(attempt(db, "victim", t + 1000, "4.4.4.4"), lock / 1000 - 1);
    t += lock;
  }
});

test("global username cap: 30 attempts/hour across IPs, flat 15 min lock, no escalation", async () => {
  const db = fakeDb();
  for (let round = 0; round < 2; round++) {
    const t = T0 + round * 61 * MIN;
    for (let i = 0; i < 30; i++) await attempt(db, "target", t);
    await rejectsWith(attempt(db, "target", t + 1000), 15 * 60 - 1);
    await attempt(db, "other", t + 1000);
  }
});

test("global window: 29 attempts then the window rolls over after an hour", async () => {
  const db = fakeDb();
  for (let i = 0; i < 29; i++) await attempt(db, "slow", T0);
  for (let i = 0; i < 29; i++) await attempt(db, "slow", T0 + 60 * MIN);
});

test("success resets username+IP (failures and level); global counter only refunds this attempt", async () => {
  const db = fakeDb();
  const ip = "3.3.3.3";
  for (let i = 0; i < 5; i++) await attempt(db, "u", T0, ip);
  let t = T0 + 15 * MIN;
  for (let i = 0; i < 4; i++) await attempt(db, "u", t, ip);
  const keys = await attempt(db, "u", t, ip);
  assert.strictEqual(doc(db, keys.userIpKey).level, 2);
  assert.strictEqual(doc(db, keys.userKey).failures, 10);
  await recordLoginSuccess({ db, ...keys, now: t });
  assert.strictEqual(doc(db, keys.userIpKey), undefined);
  assert.strictEqual(doc(db, keys.userKey).failures, 9);
  t += 1000;
  for (let i = 0; i < 5; i++) await attempt(db, "u", t, ip);
  await rejectsWith(attempt(db, "u", t, ip), 15 * 60);
});

test("IP cap: 20 attempts per 10 min across usernames, no writes when blocked", async () => {
  const db = fakeDb();
  for (let i = 0; i < 20; i++) await attempt(db, `user${i}`, T0 + i, "6.6.6.6");
  const before = JSON.stringify([...db.store.entries()]);
  await rejectsWith(attempt(db, "fresh", T0 + 60 * 1000, "6.6.6.6"), 9 * 60);
  assert.strictEqual(JSON.stringify([...db.store.entries()]), before);
  await attempt(db, "fresh", T0 + 60 * 1000, "7.7.7.7");
  await attempt(db, "fresh2", T0 + 10 * MIN, "6.6.6.6");
});

test("daily IP cap: 300 attempts per 24h even when spread across 10 min windows", async () => {
  const db = fakeDb();
  const ip = "2.2.2.2";
  for (let w = 0; w < 15; w++) {
    for (let i = 0; i < 20; i++) await attempt(db, `d${w}_${i}`, T0 + w * 10 * MIN, ip);
  }
  const t = T0 + 15 * 10 * MIN;
  await rejectsWith(attempt(db, "late", t, ip), (24 * 60 - 150) * 60);
  await attempt(db, "late", T0 + 24 * 60 * MIN, ip);
});

test("expired docs are ignored even if TTL has not deleted them", async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) await attempt(db, "z", T0, "1.1.1.1");
  const key = `${COLLECTION}/${throttleKeys("z", "1.1.1.1").userIpKey}`;
  db.store.set(key, { ...db.store.get(key), expireAt: new Date(T0 + 1000) });
  await attempt(db, "z", T0 + 2000, "1.1.1.1");
  assert.strictEqual(db.store.get(key).level, 0);
});
