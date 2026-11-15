const test = require("node:test");
const assert = require("node:assert");
const { autoCloseExpiredCampaigns, AUTO_CLOSE_ACTOR } = require("../auto_close_campaigns");
const { toMillis } = require("../campaign_eligibility");

const ts = (iso) => new Date(Date.parse(iso));
const STAMP = { serverTimestamp: true };

/** Minimal Firestore double: events collection with where(isActive ==) and where(endDate <=). */
function fakeDb(events, { beforeTransaction } = {}) {
  const store = new Map(Object.entries(events).map(([id, v]) => [`events/${id}`, structuredClone(v)]));
  const updates = [];
  const ref = (path) => ({ path, id: path.split("/").pop() });
  const queryFor = () => {
    const filters = [];
    const q = {
      where(field, op, value) { filters.push({ field, op, value }); return q; },
      async get() {
        const docs = [...store.entries()].filter(([path, data]) => path.startsWith("events/") && filters.every((f) => {
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
    store, updates,
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

const run = (db, nowIso, logs = []) =>
  autoCloseExpiredCampaigns(db, { nowMs: Date.parse(nowIso), log: (l) => logs.push(l), serverTimestamp: () => STAMP });

const EVENTS = () => ({
  knorr: { eventName: "Knorr", companySlug: "knorr", isActive: true, startDate: ts("2026-10-07T21:00:00Z"), endDate: ts("2026-11-06T22:00:00Z") },
  future: { eventName: "Future", companySlug: "x", isActive: true, startDate: ts("2026-11-10T22:00:00Z"), endDate: ts("2026-12-10T22:00:00Z") },
  openEnded: { eventName: "No end", companySlug: "x", isActive: true, startDate: ts("2026-10-01T22:00:00Z") },
  alreadyClosed: { eventName: "Closed", companySlug: "x", isActive: false, endDate: ts("2026-09-01T22:00:00Z"), updatedBy: "admin@x" },
  depleted: {
    eventName: "Depleted", companySlug: "x", isActive: true, endDate: ts("2026-12-30T22:00:00Z"),
    allocatedPrizes: [{ giftId: "g", name: "g", allocatedQuantity: 10, remainingQuantity: 0 }],
  },
});

test("closes only campaigns past their end date and records who and when", async () => {
  const db = fakeDb(EVENTS());
  const logs = [];
  const out = await run(db, "2026-11-15T10:00:00Z", logs);
  assert.deepStrictEqual(out.closed.map((c) => c.eventId), ["knorr"]);
  const knorr = db.store.get("events/knorr");
  assert.strictEqual(knorr.isActive, false);
  assert.strictEqual(knorr.updatedBy, AUTO_CLOSE_ACTOR);
  assert.strictEqual(knorr.updatedBy, "system:auto-close");
  assert.deepStrictEqual(knorr.updatedAt, STAMP);
  assert.strictEqual(db.store.get("events/future").isActive, true);
  assert.strictEqual(db.store.get("events/openEnded").isActive, true);
  assert.strictEqual(db.store.get("events/alreadyClosed").updatedBy, "admin@x");
  const closedLog = logs.find((l) => l.action === "closed");
  assert.strictEqual(closedLog.eventId, "knorr");
  assert.strictEqual(closedLog.companySlug, "knorr");
  assert.deepStrictEqual(logs.find((l) => l.action === "summary").closedIds, ["knorr"]);
});

test("a stock-depleted campaign that is still in date stays active and untouched", async () => {
  const db = fakeDb(EVENTS());
  await run(db, "2026-11-15T10:00:00Z");
  const depleted = db.store.get("events/depleted");
  assert.strictEqual(depleted.isActive, true);
  assert.strictEqual(depleted.updatedBy, undefined);
  assert.strictEqual(depleted.allocatedPrizes[0].remainingQuantity, 0);
  assert.ok(!db.updates.includes("events/depleted"));
});

test("the end day is inclusive: closes at Cairo 00:00 of the next day, not before", async () => {
  const db = fakeDb(EVENTS());
  // Knorr ends Cairo 2026-11-07; cutoff is 2026-11-07 22:00 UTC (Cairo 2026-11-08 00:00).
  assert.strictEqual((await run(fakeDb(EVENTS()), "2026-11-07T21:59:59Z")).closed.length, 0);
  assert.strictEqual((await run(db, "2026-11-07T22:00:00Z")).closed.length, 1);
});

test("idempotent: a second run closes nothing and writes nothing", async () => {
  const db = fakeDb(EVENTS());
  await run(db, "2026-11-15T10:00:00Z");
  const writes = db.updates.length;
  const logs = [];
  const second = await run(db, "2026-11-15T10:05:00Z", logs);
  assert.strictEqual(second.closed.length, 0);
  assert.strictEqual(db.updates.length, writes);
  assert.deepStrictEqual(logs.find((l) => l.action === "summary").closedIds, []);
});

test("a campaign an admin extended or re-opened after the scan is left alone", async () => {
  const db = fakeDb(EVENTS(), {
    beforeTransaction: (store) => {
      const knorr = store.get("events/knorr");
      knorr.endDate = ts("2026-12-31T22:00:00Z");
    },
  });
  const out = await run(db, "2026-11-15T10:00:00Z");
  assert.strictEqual(out.closed.length, 0);
  assert.strictEqual(out.skipped, 1);
  assert.strictEqual(db.store.get("events/knorr").isActive, true);
});
