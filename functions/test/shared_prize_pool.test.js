const test = require("node:test");
const assert = require("node:assert");
const { findSharedPoolRow, sharedPoolEnabled, applyCampaignPrizeClaim } = require("../security_functions")._testing;

const row = (giftId, branchId, rem, extra = {}) => Object.assign({
  giftId, name: `فواتشر ${giftId}`, giftType: "voucher", unitValue: 50, branchId, branchName: `فرع ${branchId}`, remainingQuantity: rem,
}, extra);

// Minimal in-memory Firestore fake: doc get, where().where() get, tx.update/set.
function fakeDb(docs) {
  const store = new Map(Object.entries(docs).map(([k, v]) => [k, JSON.parse(JSON.stringify(v))]));
  const ref = (path) => ({ path, id: path.split("/").pop() });
  const snapOf = (r) => ({ exists: store.has(r.path), data: () => store.get(r.path), id: r.id, ref: r });
  const collection = (name) => {
    const filters = [];
    const q = {
      doc: (id) => ref(`${name}/${id}`),
      where: (f, op, v) => { filters.push([f, v]); return q; },
      _query: true,
      _run: () => [...store.keys()].filter((k) => k.startsWith(`${name}/`))
        .map((k) => snapOf(ref(k))).filter((s) => filters.every(([f, v]) => s.data()[f] === v)),
    };
    return q;
  };
  const writes = [];
  return {
    store, writes,
    collection,
    runTransaction: async (fn) => fn({
      get: async (r) => (r._query ? { docs: r._run() } : snapOf(r)),
      update: (r, data) => { writes.push(["update", r.path]); store.set(r.path, Object.assign({}, store.get(r.path), data)); },
      set: (r, data) => { writes.push(["set", r.path]); store.set(r.path, Object.assign({}, store.get(r.path) || {}, data)); },
    }),
  };
}
const actor = { anonymous: true, uid: "u1" };
const receipt = { campaignId: "NEW", submittedByUid: "u1", branch_id: "b1" };

test("strict pool match: same giftId and receipt branch", () => {
  const sibs = [{ eventId: "OLD", prizes: [row("g75", "b1", 9), row("g50", "b2", 9), row("g50", "b1", 3)] }];
  assert.deepStrictEqual(findSharedPoolRow(sibs, { prizeIdentifier: "g50", count: 1 }, "b1"), { eventId: "OLD", index: 2 });
});
test("pool never uses another branch or another gift", () => {
  const sibs = [{ eventId: "OLD", prizes: [row("g75", "b1", 9), row("g50", "b2", 9)] }];
  assert.strictEqual(findSharedPoolRow(sibs, { prizeIdentifier: "g50", count: 1 }, "b1"), null);
});
test("pool falls back to a general (no-branch) row", () => {
  const sibs = [{ eventId: "OLD", prizes: [row("g50", "", 4, { branchName: "" })] }];
  assert.deepStrictEqual(findSharedPoolRow(sibs, { prizeIdentifier: "g50", count: 1 }, "b1"), { eventId: "OLD", index: 0 });
});
test("balanceMode campaign_only opts out", () => {
  assert.strictEqual(sharedPoolEnabled({ balanceMode: "campaign_only" }), false);
  assert.strictEqual(sharedPoolEnabled({}), true);
});

test("campaign without rows draws once from sibling campaign of same company", async () => {
  const db = fakeDb({
    "events/NEW": { companySlug: "583", isActive: true, allocatedPrizes: [] },
    "events/OLD": { companySlug: "583", isActive: true, allocatedPrizes: [row("g50", "b1", 5), row("g50", "b2", 5)] },
    "events/OTHERCO": { companySlug: "999", isActive: true, allocatedPrizes: [row("g50", "b1", 50)] },
    "receipts_transactions/r1": receipt,
  });
  const out = await applyCampaignPrizeClaim(db, {
    eventId: "NEW", receiptId: "r1", actor,
    decrements: [{ prizeIdentifier: "g50", count: 1 }], receiptPatch: { game_played: true },
  });
  assert.strictEqual(out.applied[0].stockEventId, "OLD");
  assert.strictEqual(db.store.get("events/OLD").allocatedPrizes[0].remainingQuantity, 4);
  assert.strictEqual(db.store.get("events/OLD").allocatedPrizes[1].remainingQuantity, 5);
  assert.strictEqual(db.store.get("events/OTHERCO").allocatedPrizes[0].remainingQuantity, 50);
  assert.ok(!db.writes.some(([, p]) => p === "events/NEW"), "no write to the empty campaign");
  assert.deepStrictEqual(db.store.get("receipts_transactions/r1").claim_stock_sources,
    [{ prizeIdentifier: "g50", count: 1, stockEventId: "OLD" }]);
});

test("campaign with its own row keeps using it (no pool, no double count)", async () => {
  const db = fakeDb({
    "events/NEW": { companySlug: "583", isActive: true, allocatedPrizes: [row("g50", "b1", 2)] },
    "events/OLD": { companySlug: "583", isActive: true, allocatedPrizes: [row("g50", "b1", 5)] },
    "receipts_transactions/r1": receipt,
  });
  const out = await applyCampaignPrizeClaim(db, { eventId: "NEW", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g50", count: 1 }] });
  assert.strictEqual(out.applied[0].stockEventId, "NEW");
  assert.strictEqual(db.store.get("events/NEW").allocatedPrizes[0].remainingQuantity, 1);
  assert.strictEqual(db.store.get("events/OLD").allocatedPrizes[0].remainingQuantity, 5);
});

test("inactive or opted-out siblings are not used; error stays the same", async () => {
  const db = fakeDb({
    "events/NEW": { companySlug: "583", isActive: true, allocatedPrizes: [] },
    "events/OFF": { companySlug: "583", isActive: false, allocatedPrizes: [row("g50", "b1", 5)] },
    "events/OPT": { companySlug: "583", isActive: true, balanceMode: "campaign_only", allocatedPrizes: [row("g50", "b1", 5)] },
    "receipts_transactions/r1": receipt,
  });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "NEW", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g50", count: 1 }] }), /لا يوجد رصيد مخصص/);
});

test("opted-out campaign does not draw from the pool", async () => {
  const db = fakeDb({
    "events/NEW": { companySlug: "583", isActive: true, balanceMode: "campaign_only", allocatedPrizes: [] },
    "events/OLD": { companySlug: "583", isActive: true, allocatedPrizes: [row("g50", "b1", 5)] },
    "receipts_transactions/r1": receipt,
  });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "NEW", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g50", count: 1 }] }), /لا يوجد رصيد مخصص/);
});

// 2.0.154: receipt branch known, campaign has the gift only on other branches.
test("branch without a row: shared pool for that exact branch is used", async () => {
  const db = fakeDb({
    "events/NEW": { companySlug: "583", isActive: true, allocatedPrizes: [row("g50", "b2", 5), row("g50", "b3", 5)] },
    "events/OLD": { companySlug: "583", isActive: true, allocatedPrizes: [row("g50", "b1", 4)] },
    "receipts_transactions/r1": receipt,
  });
  const out = await applyCampaignPrizeClaim(db, { eventId: "NEW", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g50", count: 1 }] });
  assert.strictEqual(out.applied[0].stockEventId, "OLD");
  assert.strictEqual(db.store.get("events/OLD").allocatedPrizes[0].remainingQuantity, 3);
  assert.strictEqual(db.store.get("events/NEW").allocatedPrizes[0].remainingQuantity, 5);
});
test("branch without a row and no pool: clear no-branch-stock error, nothing written", async () => {
  const db = fakeDb({
    "events/NEW": { companySlug: "583", isActive: true, allocatedPrizes: [row("g50", "b2", 5), row("g50", "b3", 5)] },
    "receipts_transactions/r1": receipt,
  });
  await assert.rejects(
    applyCampaignPrizeClaim(db, { eventId: "NEW", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g50", count: 1 }] }),
    (e) => e.message === "مفيش رصيد للهدية دي في فرع الفاتورة، كلّم المشرف" && !/أكثر من فرع/.test(e.message));
  assert.strictEqual(db.writes.length, 0);
});
