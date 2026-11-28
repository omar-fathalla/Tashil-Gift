const test = require("node:test");
const assert = require("node:assert");
const { autoActivateCampaigns, activationVerdict, AUTO_ACTIVATE_ACTOR } = require("../auto_activate_campaigns");
const { autoCloseExpiredCampaigns } = require("../auto_close_campaigns");
const { toMillis } = require("../campaign_eligibility");

const ts = (iso) => new Date(Date.parse(iso));
const STAMP = { serverTimestamp: true };

/** Minimal Firestore double: events with where(field ==) and where(endDate <=). */
function fakeDb(events, { beforeTransaction } = {}) {
  const store = new Map(Object.entries(events).map(([id, v]) => [`events/${id}`, structuredClone(v)]));
  const updates = [];
  const queries = [];
  const ref = (path) => ({ path, id: path.split("/").pop() });
  const queryFor = () => {
    const filters = [];
    const q = {
      where(field, op, value) { filters.push({ field, op, value }); return q; },
      async get() {
        queries.push(filters.map((f) => `${f.field}${f.op}`).join("&"));
        const docs = [...store.entries()].filter(([, data]) => filters.every((f) => {
          const have = f.field === "endDate" ? toMillis(data.endDate) : data[f.field];
          if (f.op === "==") return have === f.value;
          if (f.op === "<=") return have != null && have <= toMillis(f.value);
          throw new Error(`unsupported op ${f.op}`);
        })).map(([path, data]) => ({ id: path.split("/").pop(), ref: ref(path), data: () => structuredClone(data) }));
        return { docs, size: docs.length };
      },
    };
    return q;
  };
  return {
    store, updates, queries,
    collection: () => queryFor(),
    runTransaction: async (fn) => {
      if (beforeTransaction) beforeTransaction(store);
      return fn({
        get: async (r) => ({ exists: store.has(r.path), data: () => structuredClone(store.get(r.path)), id: r.id, ref: r }),
        update: (r, d) => { updates.push(r.path); store.set(r.path, Object.assign({}, store.get(r.path), d)); },
      });
    },
  };
}

const run = (db, nowIso, logs = [], extra = {}) =>
  autoActivateCampaigns(db, { nowMs: Date.parse(nowIso), log: (l) => logs.push(l), serverTimestamp: () => STAMP, ...extra });

// Knorr: Cairo 25/11/2026 .. 14/12/2026 inclusive, stored at Cairo 00:00 (UTC+2).
const KNORR = { eventName: "Knorr", companySlug: "512", isActive: false, startDate: ts("2026-11-24T22:00:00Z"), endDate: ts("2026-12-13T22:00:00Z"), updatedBy: "admin-uid" };
const knorrOnly = () => fakeDb({ knorr: structuredClone(KNORR) });

const EVENTS = () => ({
  knorr: structuredClone(KNORR),
  paused: { ...structuredClone(KNORR), eventName: "Paused", pausedManually: true },
  active: { ...structuredClone(KNORR), eventName: "Active", isActive: true },
  ended: { eventName: "Ended", companySlug: "x", isActive: false, startDate: ts("2026-10-01T22:00:00Z"), endDate: ts("2026-11-20T22:00:00Z") },
  future: { eventName: "Future", companySlug: "x", isActive: false, startDate: ts("2026-12-01T22:00:00Z"), endDate: ts("2026-12-20T22:00:00Z") },
  noEnd: { eventName: "No end", companySlug: "x", isActive: false, startDate: ts("2026-11-01T22:00:00Z") },
  noDates: { eventName: "No dates", companySlug: "x", isActive: false },
  resumed: { ...structuredClone(KNORR), eventName: "Resumed", pausedManually: false },
});

test("turns on only off, not manually paused campaigns whose dates cover today", async () => {
  const db = fakeDb(EVENTS());
  const logs = [];
  const out = await run(db, "2026-11-25T10:00:00Z", logs);
  assert.deepStrictEqual(out.activated.map((c) => c.eventId).sort(), ["knorr", "resumed"]);
  const knorr = db.store.get("events/knorr");
  assert.strictEqual(knorr.isActive, true);
  assert.strictEqual(knorr.statusUpdatedBy, AUTO_ACTIVATE_ACTOR);
  assert.strictEqual(knorr.statusUpdatedBy, "system:auto-activate");
  assert.deepStrictEqual(knorr.statusUpdatedAt, STAMP);
  assert.strictEqual(knorr.updatedBy, "admin-uid", "the admin's last edit stamp is kept");
  assert.ok(!("pausedManually" in knorr));
  for (const id of ["paused", "ended", "future", "noEnd", "noDates"]) {
    assert.strictEqual(db.store.get(`events/${id}`).isActive, false, id);
    assert.ok(!db.updates.includes(`events/${id}`), id);
  }
  assert.ok(!db.updates.includes("events/active"));
  const line = logs.find((l) => l.action === "activated" && l.eventId === "knorr");
  assert.strictEqual(line.companySlug, "512");
  assert.strictEqual(line.startDate, "2026-11-24T22:00:00.000Z");
  const summary = logs.find((l) => l.action === "summary");
  assert.strictEqual(summary.activated, 2);
  assert.strictEqual(summary.scanned, 7);
});

test("uses one single-field equality query (no composite index needed)", async () => {
  const db = fakeDb(EVENTS());
  await run(db, "2026-11-25T10:00:00Z");
  assert.deepStrictEqual(db.queries, ["isActive=="]);
});

test("opens at Cairo 00:00 of the start day, not before", async () => {
  // Cairo 25/11 00:00 = 2026-11-24T22:00Z (Egypt is UTC+2 in November).
  assert.strictEqual((await run(knorrOnly(), "2026-11-24T21:59:59Z")).activated.length, 0);
  assert.strictEqual(activationVerdict(KNORR, Date.parse("2026-11-24T21:59:59Z")), "not_started");
  assert.strictEqual((await run(knorrOnly(), "2026-11-24T22:00:00Z")).activated.length, 1);
  // The scheduled 00:10 Cairo tick on the start day.
  assert.strictEqual((await run(knorrOnly(), "2026-11-24T22:10:00Z")).activated.length, 1);
});

test("the end day is inclusive: still eligible on the last day, not from the next Cairo midnight", async () => {
  // Last day Cairo 14/12; cutoff Cairo 15/12 00:00 = 2026-12-14T22:00Z.
  assert.strictEqual(activationVerdict(KNORR, Date.parse("2026-12-14T21:59:59Z")), "eligible");
  assert.strictEqual(activationVerdict(KNORR, Date.parse("2026-12-14T22:00:00Z")), "ended");
  assert.strictEqual((await run(knorrOnly(), "2026-12-13T22:10:00Z")).activated.length, 1);
  assert.strictEqual((await run(knorrOnly(), "2026-12-14T22:10:00Z")).activated.length, 0);
});

test("Cairo summer time (UTC+3): a start day stored at Cairo 00:00 opens on time", () => {
  const summer = { isActive: false, startDate: ts("2026-07-09T21:00:00Z"), endDate: ts("2026-07-19T21:00:00Z") };
  assert.strictEqual(activationVerdict(summer, Date.parse("2026-07-09T20:59:59Z")), "not_started");
  assert.strictEqual(activationVerdict(summer, Date.parse("2026-07-09T21:00:00Z")), "eligible");
  assert.strictEqual(activationVerdict(summer, Date.parse("2026-07-20T21:00:00Z")), "ended");
});

test("verdicts for skipped campaigns", () => {
  const now = Date.parse("2026-11-25T10:00:00Z");
  const ev = EVENTS();
  assert.strictEqual(activationVerdict(ev.paused, now), "paused_manually");
  assert.strictEqual(activationVerdict(ev.active, now), "already_active");
  assert.strictEqual(activationVerdict(ev.ended, now), "ended");
  assert.strictEqual(activationVerdict(ev.future, now), "not_started");
  assert.strictEqual(activationVerdict(ev.noEnd, now), "missing_dates");
  assert.strictEqual(activationVerdict(ev.noDates, now), "missing_dates");
  assert.strictEqual(activationVerdict(null, now), "missing");
});

test("idempotent: a second run activates nothing and writes nothing", async () => {
  const db = fakeDb(EVENTS());
  await run(db, "2026-11-25T10:00:00Z");
  const writes = db.updates.length;
  const logs = [];
  const second = await run(db, "2026-11-25T10:05:00Z", logs);
  assert.strictEqual(second.activated.length, 0);
  assert.strictEqual(db.updates.length, writes);
  assert.deepStrictEqual(logs.find((l) => l.action === "summary").activatedIds, []);
});

test("a campaign an admin paused after the scan is left alone", async () => {
  const db = fakeDb({ knorr: structuredClone(KNORR) }, {
    beforeTransaction: (store) => { store.get("events/knorr").pausedManually = true; },
  });
  const out = await run(db, "2026-11-25T10:00:00Z");
  assert.strictEqual(out.activated.length, 0);
  assert.strictEqual(out.skipped, 1);
  assert.strictEqual(db.store.get("events/knorr").isActive, false);
});

test("batches: many candidates are all activated across chunks", async () => {
  const many = {};
  for (let i = 0; i < 23; i++) many[`c${i}`] = { ...structuredClone(KNORR), eventName: `C${i}` };
  const db = fakeDb(many);
  const out = await run(db, "2026-11-25T10:00:00Z", [], { batchSize: 5 });
  assert.strictEqual(out.activated.length, 23);
  assert.ok([...db.store.values()].every((d) => d.isActive === true));
});

test("auto-close then auto-activate: an ended campaign stays closed; once extended it turns on", async () => {
  const db = fakeDb({
    old: { eventName: "Old", companySlug: "x", isActive: true, startDate: ts("2026-10-01T22:00:00Z"), endDate: ts("2026-11-20T22:00:00Z") },
  });
  const opts = { nowMs: Date.parse("2026-11-25T22:10:00Z"), log: () => {}, serverTimestamp: () => STAMP };
  await autoCloseExpiredCampaigns(db, opts);
  await autoActivateCampaigns(db, opts);
  const old = db.store.get("events/old");
  assert.strictEqual(old.isActive, false);
  assert.strictEqual(old.statusUpdatedBy, "system:auto-close");
  // An admin extends the end date (the edit page never writes isActive).
  old.endDate = ts("2026-12-30T22:00:00Z");
  await autoActivateCampaigns(db, { ...opts, nowMs: Date.parse("2026-11-26T22:10:00Z") });
  assert.strictEqual(db.store.get("events/old").isActive, true);
  assert.strictEqual(db.store.get("events/old").statusUpdatedBy, "system:auto-activate");
});
