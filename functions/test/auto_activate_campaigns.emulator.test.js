/**
 * TAG-18 auto-activate against the Firestore emulator (demo- projects only).
 * Uses a fixed "now" in 2030 so fixtures from other emulator tests never match.
 *
 * Run from functions/: npm run test:emulator
 */
const test = require("node:test");
const assert = require("node:assert");
const admin = require("../admin_sdk");
const { autoActivateCampaigns } = require("../auto_activate_campaigns");

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && PROJECT.startsWith("demo-");
const ts = (iso) => admin.firestore.Timestamp.fromMillis(Date.parse(iso));

// Cairo 10/03/2030 .. 20/03/2030 (UTC+2), stored at Cairo 00:00.
const base = (extra = {}) => Object.assign({
  eventName: "Auto-activate fixture", companySlug: "aa", isActive: false,
  startDate: ts("2030-03-09T22:00:00Z"), endDate: ts("2030-03-19T22:00:00Z"),
}, extra);

test.before(() => {
  if (RUN) admin.initializeApp({ projectId: PROJECT });
});

test("autoActivateCampaigns on real Firestore: activates eligible, skips paused/active/ended/undated, idempotent", { skip: !RUN }, async () => {
  const db = admin.firestore();
  const fixtures = {
    AA_eligible: base(),
    AA_paused: base({ pausedManually: true }),
    AA_active: base({ isActive: true }),
    AA_ended: base({ startDate: ts("2030-02-01T22:00:00Z"), endDate: ts("2030-03-01T22:00:00Z") }),
    AA_future: base({ startDate: ts("2030-03-20T22:00:00Z"), endDate: ts("2030-03-30T22:00:00Z") }),
    AA_undated: base({ endDate: null }),
  };
  for (const [id, data] of Object.entries(fixtures)) await db.collection("events").doc(id).set(data);

  const nowMs = Date.parse("2030-03-09T22:10:00Z"); // Cairo 10/03 00:10, the scheduled tick
  const logs = [];
  const first = await autoActivateCampaigns(db, { nowMs, log: (l) => logs.push(l) });
  const ids = first.activated.map((c) => c.eventId);
  assert.ok(ids.includes("AA_eligible"));
  for (const id of ["AA_paused", "AA_active", "AA_ended", "AA_future", "AA_undated"]) assert.ok(!ids.includes(id), id);

  const on = (await db.collection("events").doc("AA_eligible").get()).data();
  assert.strictEqual(on.isActive, true);
  assert.strictEqual(on.statusUpdatedBy, "system:auto-activate");
  assert.ok(on.statusUpdatedAt instanceof admin.firestore.Timestamp);
  assert.strictEqual(on.pausedManually, undefined);
  for (const id of ["AA_paused", "AA_ended", "AA_future", "AA_undated"]) {
    const off = (await db.collection("events").doc(id).get()).data();
    assert.strictEqual(off.isActive, false, id);
    assert.strictEqual(off.statusUpdatedBy, undefined, id);
  }
  assert.ok(logs.some((l) => l.action === "activated" && l.eventId === "AA_eligible"));

  const second = await autoActivateCampaigns(db, { nowMs, log: () => {} });
  assert.ok(!second.activated.some((c) => c.eventId === "AA_eligible"));

  // After the end day it is not eligible any more (auto-close itself is
  // covered by claim_eligibility.emulator.test.js; running it here with a 2030
  // clock would close the other files' fixtures).
  await db.collection("events").doc("AA_eligible").update({ isActive: false });
  const third = await autoActivateCampaigns(db, { nowMs: Date.parse("2030-03-20T22:10:00Z"), log: () => {} });
  assert.ok(!third.activated.some((c) => c.eventId === "AA_eligible"));
});
