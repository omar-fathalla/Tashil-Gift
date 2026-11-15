/**
 * partnerPortalLogin brute-force protection against the local emulators.
 * Run from functions/: npm run test:emulator (demo-tashil project only).
 */
const test = require("node:test");
const assert = require("node:assert");
const admin = require("../admin_sdk");
const { COLLECTION, throttleKey } = require("../login_throttle");

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && PROJECT.startsWith("demo-");
const URL = `http://127.0.0.1:5001/${PROJECT}/us-central1/partnerPortalLogin`;

let db;
let ipSeq = 0;
const freshIp = () => `203.0.113.${++ipSeq}`;

async function login({ username, password, ip, companySlug = "acme", role = "brand_manager" }) {
  const res = await fetch(URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Forwarded-For": `${ip}, 10.0.0.1` },
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
});

test("5 failures lock the identifier; the 6th attempt is 429 with Retry-After", { skip: !RUN }, async () => {
  const ip = freshIp();
  for (let i = 0; i < 5; i++) {
    const r = await login({ username: "boss", password: `bad${i}`, ip });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.result.ok, false);
  }
  const r = await login({ username: " BOSS ", password: "bad", ip: freshIp() });
  assertThrottled(r);
  assert.ok(Number(r.retryAfter) > 14 * 60 && Number(r.retryAfter) <= 15 * 60, r.retryAfter);

  const snap = await db.collection(COLLECTION).doc(throttleKey("id", "boss")).get();
  const d = snap.data();
  assert.strictEqual(d.level, 1);
  assert.ok(d.expireAt instanceof admin.firestore.Timestamp);
  assert.ok(!JSON.stringify(d).includes("boss"));
});

test("lockout blocks the correct password too, before any account lookup", { skip: !RUN }, async () => {
  for (let i = 0; i < 5; i++) await login({ username: "locked", password: "nope", companySlug: "gamma", ip: freshIp() });
  const r = await login({ username: "locked", password: "Lock#1", companySlug: "gamma", ip: freshIp() });
  assertThrottled(r);
  assert.ok(!JSON.stringify(r.body).includes("customToken"));
  // No companySlug: a lookup would answer invalid-argument; the lock answers first.
  assertThrottled(await login({ username: "locked", password: "Lock#1", companySlug: "", ip: freshIp() }));
});

test("successful login resets the identifier counter", { skip: !RUN }, async () => {
  const ip = freshIp();
  const ref = db.collection(COLLECTION).doc(throttleKey("id", "resetter"));
  for (let i = 0; i < 4; i++) await login({ username: "resetter", password: "bad", companySlug: "beta", ip });
  assert.strictEqual((await ref.get()).data().failures, 4);
  const ok = await login({ username: "Resetter", password: "Reset#1", companySlug: "beta", ip });
  assert.strictEqual(ok.status, 200);
  assert.strictEqual(ok.body.result.ok, true);
  assert.ok(ok.body.result.customToken);
  assert.strictEqual((await ref.get()).exists, false);
  for (let i = 0; i < 4; i++) {
    const r = await login({ username: "resetter", password: "bad", companySlug: "beta", ip });
    assert.strictEqual(r.status, 200);
  }
});

test("per-IP cap: 20 attempts per 10 minutes, other IPs unaffected", { skip: !RUN }, async () => {
  const ip = freshIp();
  for (let i = 0; i < 20; i++) {
    const r = await login({ username: `spray${i}`, password: "bad", ip });
    assert.strictEqual(r.status, 200, `attempt ${i + 1}`);
  }
  const r = await login({ username: "spray-new", password: "bad", ip });
  assertThrottled(r);
  assert.ok(Number(r.retryAfter) <= 10 * 60);
  assert.strictEqual((await login({ username: "spray-new", password: "bad", ip: freshIp() })).status, 200);
  const ipDoc = await db.collection(COLLECTION).doc(throttleKey("ip", ip)).get();
  assert.strictEqual(ipDoc.data().count, 20);
  assert.ok(!JSON.stringify(ipDoc.data()).includes(ip));
});

test("unknown and known users get identical responses (401-equivalent and 429)", { skip: !RUN }, async () => {
  const known = await login({ username: "opsuser", password: "wrong", role: "agency_ops", ip: freshIp() });
  const unknown = await login({ username: "ghost", password: "wrong", role: "agency_ops", ip: freshIp() });
  assert.strictEqual(known.status, unknown.status);
  assert.deepStrictEqual(known.body, unknown.body);
  assert.strictEqual(known.body.result.reason, "invalid_agency");

  for (let i = 0; i < 4; i++) {
    await login({ username: "opsuser", password: "wrong", role: "agency_ops", ip: freshIp() });
    await login({ username: "ghost", password: "wrong", role: "agency_ops", ip: freshIp() });
  }
  const lockedKnown = await login({ username: "opsuser", password: "Ops#1", role: "agency_ops", ip: freshIp() });
  const lockedUnknown = await login({ username: "ghost", password: "wrong", role: "agency_ops", ip: freshIp() });
  assertThrottled(lockedKnown);
  assertThrottled(lockedUnknown);
  const shape = (r) => ({ status: r.status, message: r.body.error.message, code: r.body.error.status, keys: Object.keys(r.body.error.details) });
  assert.deepStrictEqual(shape(lockedKnown), shape(lockedUnknown));
});
