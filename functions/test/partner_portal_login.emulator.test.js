/**
 * partnerPortalLogin brute-force protection against the local emulators.
 * Run from functions/: npm run test:emulator (demo-tashil project only).
 */
const test = require("node:test");
const assert = require("node:assert");
const admin = require("../admin_sdk");
const { COLLECTION, throttleKey, throttleKeys } = require("../login_throttle");

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && PROJECT.startsWith("demo-");
const URL = `http://127.0.0.1:5001/${PROJECT}/us-central1/partnerPortalLogin`;

let db;
let ipSeq = 0;
const freshIp = () => `203.0.${(++ipSeq >> 8) & 255}.${ipSeq & 255}`;

/** `ip` is what Google's front end would append; `spoof` is a client-sent leading hop. */
async function login({ username, password, ip, spoof = "10.0.0.1", companySlug = "acme", role = "brand_manager" }) {
  const res = await fetch(URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Forwarded-For": `${spoof}, ${ip}` },
    body: JSON.stringify({ data: { companySlug, role, username, password } }),
  });
  return { status: res.status, retryAfter: res.headers.get("retry-after"), body: await res.json() };
}

function assertThrottled(r) {
  assert.strictEqual(r.status, 429, JSON.stringify(r.body));
  assert.ok(Number(r.retryAfter) > 0, `Retry-After ${r.retryAfter}`);
  assert.strictEqual(r.body.error.status, "RESOURCE_EXHAUSTED");
  assert.strictEqual(r.body.error.message, "Too many attempts. Please wait and try again.");
  assert.strictEqual(r.body.error.details.retryAfterSec, Number(r.retryAfter));
  assert.strictEqual(r.body.result, undefined);
}

const throttleDoc = async (key) => (await db.collection(COLLECTION).doc(key).get()).data();

test.before(async () => {
  if (!RUN) return;
  admin.initializeApp({ projectId: PROJECT });
  db = admin.firestore();
  await db.collection("companies").doc("acme").set({
    name: "Acme", brandManagerUsername: "boss", brandManagerPassword: "Secret#1",
    agencyOpsUsername: "opsuser", agencyOpsPassword: "Ops#1",
  });
  await db.collection("companies").doc("beta").set({ name: "Beta", brandManagerUsername: "Resetter", brandManagerPassword: "Reset#1" });
  await db.collection("companies").doc("gamma").set({ name: "Gamma", brandManagerUsername: "locked", brandManagerPassword: "Lock#1" });
  await db.collection("companies").doc("delta").set({ name: "Delta", brandManagerUsername: "popular", brandManagerPassword: "Pop#1" });
});

test("5 failures from one IP lock username+IP (429 + Retry-After); other IPs still get in", { skip: !RUN }, async () => {
  const ip = freshIp();
  for (let i = 0; i < 5; i++) {
    const r = await login({ username: "boss", password: `bad${i}`, ip, spoof: `1.1.1.${i}` });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.result.ok, false);
  }
  const r = await login({ username: " BOSS ", password: "bad", ip, spoof: "9.9.9.9" });
  assertThrottled(r);
  assert.ok(Number(r.retryAfter) > 14 * 60 && Number(r.retryAfter) <= 15 * 60, r.retryAfter);

  const d = await throttleDoc(throttleKeys("boss", ip).userIpKey);
  assert.strictEqual(d.level, 1);
  assert.ok(d.expireAt instanceof admin.firestore.Timestamp);
  assert.ok(!JSON.stringify(d).includes("boss") && !JSON.stringify(d).includes(ip));

  const elsewhere = await login({ username: "boss", password: "Secret#1", ip: freshIp() });
  assert.strictEqual(elsewhere.status, 200);
  assert.strictEqual(elsewhere.body.result.ok, true);
});

test("lockout blocks the correct password too, before any account lookup", { skip: !RUN }, async () => {
  const ip = freshIp();
  for (let i = 0; i < 5; i++) await login({ username: "locked", password: "nope", companySlug: "gamma", ip });
  const r = await login({ username: "locked", password: "Lock#1", companySlug: "gamma", ip });
  assertThrottled(r);
  assert.ok(!JSON.stringify(r.body).includes("customToken"));
  // No companySlug: a lookup would answer invalid-argument; the lock answers first.
  assertThrottled(await login({ username: "locked", password: "Lock#1", companySlug: "", ip }));
});

test("success resets username+IP; global counter keeps other attempts", { skip: !RUN }, async () => {
  const ip = freshIp();
  const keys = throttleKeys("resetter", ip);
  await login({ username: "resetter", password: "bad", companySlug: "beta", ip: freshIp() });
  for (let i = 0; i < 4; i++) await login({ username: "resetter", password: "bad", companySlug: "beta", ip });
  assert.strictEqual((await throttleDoc(keys.userIpKey)).failures, 4);
  assert.strictEqual((await throttleDoc(keys.userKey)).failures, 5);
  const ok = await login({ username: "Resetter", password: "Reset#1", companySlug: "beta", ip });
  assert.strictEqual(ok.status, 200);
  assert.strictEqual(ok.body.result.ok, true);
  assert.ok(ok.body.result.customToken);
  assert.strictEqual(await throttleDoc(keys.userIpKey), undefined);
  assert.strictEqual((await throttleDoc(keys.userKey)).failures, 5);
  for (let i = 0; i < 4; i++) {
    const r = await login({ username: "resetter", password: "bad", companySlug: "beta", ip });
    assert.strictEqual(r.status, 200);
  }
});

test("global username cap: 30 attempts across IPs lock the username for 15 min", { skip: !RUN }, async () => {
  for (let i = 0; i < 30; i++) {
    const r = await login({ username: "popular", password: "bad", companySlug: "delta", ip: freshIp() });
    assert.strictEqual(r.status, 200, `attempt ${i + 1}`);
  }
  const r = await login({ username: "popular", password: "Pop#1", companySlug: "delta", ip: freshIp() });
  assertThrottled(r);
  assert.ok(Number(r.retryAfter) > 14 * 60 && Number(r.retryAfter) <= 15 * 60, r.retryAfter);
  const d = await throttleDoc(throttleKey("id", "popular"));
  assert.strictEqual(d.level, undefined);
});

test("per-IP cap (20/10 min) holds even with a different spoofed leading XFF hop each time", { skip: !RUN }, async () => {
  const ip = freshIp();
  for (let i = 0; i < 20; i++) {
    const r = await login({ username: `spray${i}`, password: "bad", ip, spoof: `198.51.100.${i}` });
    assert.strictEqual(r.status, 200, `attempt ${i + 1}`);
  }
  const r = await login({ username: "spray-new", password: "bad", ip, spoof: "198.51.100.250" });
  assertThrottled(r);
  assert.ok(Number(r.retryAfter) <= 10 * 60);
  assert.strictEqual((await login({ username: "spray-new", password: "bad", ip: freshIp() })).status, 200);
  const ipDoc = await throttleDoc(throttleKey("ip", ip));
  assert.strictEqual(ipDoc.count, 20);
  assert.ok(!JSON.stringify(ipDoc).includes(ip));
});

test("daily per-IP cap (300/24 h) applies even in a fresh 10 min window", { skip: !RUN }, async () => {
  const ip = freshIp();
  const now = Date.now();
  // The emulator cannot fast-forward time, so seed a doc that already holds a full day.
  await db.collection(COLLECTION).doc(throttleKey("ip", ip)).set({
    kind: "ip", count: 0, windowStart: new Date(now - 11 * 60 * 1000),
    dayCount: 300, dayStart: new Date(now - 60 * 60 * 1000), expireAt: new Date(now + 23 * 60 * 60 * 1000),
  });
  const r = await login({ username: "daily", password: "bad", ip });
  assertThrottled(r);
  assert.ok(Number(r.retryAfter) > 22 * 3600 && Number(r.retryAfter) <= 23 * 3600, r.retryAfter);
});

test("unknown and known users get identical responses (failure 200 and 429)", { skip: !RUN }, async () => {
  const known = await login({ username: "opsuser", password: "wrong", role: "agency_ops", ip: freshIp() });
  const unknown = await login({ username: "ghost", password: "wrong", role: "agency_ops", ip: freshIp() });
  assert.strictEqual(known.status, unknown.status);
  assert.deepStrictEqual(known.body, unknown.body);
  assert.strictEqual(known.body.result.reason, "invalid_agency");

  const ipA = freshIp();
  const ipB = freshIp();
  for (let i = 0; i < 5; i++) {
    await login({ username: "opsuser", password: "wrong", role: "agency_ops", ip: ipA });
    await login({ username: "ghost", password: "wrong", role: "agency_ops", ip: ipB });
  }
  const lockedKnown = await login({ username: "opsuser", password: "Ops#1", role: "agency_ops", ip: ipA });
  const lockedUnknown = await login({ username: "ghost", password: "wrong", role: "agency_ops", ip: ipB });
  assertThrottled(lockedKnown);
  assertThrottled(lockedUnknown);
  const shape = (r) => ({ status: r.status, message: r.body.error.message, code: r.body.error.status, keys: Object.keys(r.body.error.details) });
  assert.deepStrictEqual(shape(lockedKnown), shape(lockedUnknown));
});
