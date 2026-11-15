const test = require("node:test");
const assert = require("node:assert");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;

function fakeDb(docs) {
  const store = new Map(Object.entries(docs).map(([k, v]) => [k, JSON.parse(JSON.stringify(v))]));
  const ref = (path) => ({ path, id: path.split("/").pop() });
  const snapOf = (r) => ({ exists: store.has(r.path), data: () => store.get(r.path), id: r.id, ref: r });
  const collection = (name) => {
    const q = { doc: (id) => ref(`${name}/${id}`), where: () => q, _query: true, _run: () => [] };
    return q;
  };
  return {
    store, collection,
    runTransaction: async (fn) => fn({
      get: async (r) => (r._query ? { docs: r._run() } : snapOf(r)),
      update: (r, d) => store.set(r.path, Object.assign({}, store.get(r.path), d)),
      set: (r, d) => store.set(r.path, Object.assign({}, store.get(r.path) || {}, d)),
    }),
  };
}

const row = (giftId, rem) => ({ giftId, name: `هدية ${giftId}`, giftType: "voucher", unitValue: 100, branchId: "b1", remainingQuantity: rem });
const event = (extra = {}) => Object.assign({ companySlug: "x", isActive: true, allowMultipleChances: false, maxChancesPerReceipt: 1,
  balanceMode: "campaign_only", allocatedPrizes: [row("g100", 5)] }, extra);
const receipt = (extra = {}) => Object.assign({ campaignId: "E", submittedByUid: "u1", branch_id: "b1", chances_earned: 1 }, extra);
const rep = { anonymous: true, uid: "u1" };
const stock = (db) => db.store.get("events/E").allocatedPrizes[0].remainingQuantity;
const stored = (db) => db.store.get("receipts_transactions/r1");
const claim = (db, receiptPatch, extra = {}) => applyCampaignPrizeClaim(db, Object.assign({
  eventId: "E", receiptId: "r1", actor: rep, decrements: [{ prizeIdentifier: "g100", branchId: "b1", count: 1 }], receiptPatch,
}, extra));
const alreadyClaimed = (err) => {
  assert.strictEqual(err.code, "failed-precondition");
  assert.strictEqual(err.details.reason, "already_claimed");
  return true;
};

test("game_played-only patch: the server stamps the claim and rejects the second claim", async () => {
  const db = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt() });
  await claim(db, { game_played: true });
  const r = stored(db);
  assert.strictEqual(r.remaining_chances, 0);
  assert.deepStrictEqual(r.claimed_gifts.map((g) => [g.giftId, g.quantity]), [["g100", 1]]);
  assert.ok(r.claimedAt);
  assert.strictEqual(r.claimedBy, "u1");
  assert.strictEqual(r.game_played, true);
  const before = JSON.stringify([...db.store]);
  await assert.rejects(claim(db, { game_played: true }), alreadyClaimed);
  assert.strictEqual(JSON.stringify([...db.store]), before);
  assert.strictEqual(stock(db), 4);
});

test("client claim-state fields are ignored: a forged open count cannot keep the receipt open", async () => {
  const db = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt() });
  await claim(db, { game_played: true, remaining_chances: 9, claimed_gifts: [], claimedAt: null, claimedBy: "x", claim_trimmed_to_limit: false });
  const r = stored(db);
  assert.strictEqual(r.remaining_chances, 0);
  assert.strictEqual(r.claimed_gifts.length, 1);
  assert.strictEqual(r.claimedBy, "u1");
  assert.strictEqual(r.claim_trimmed_to_limit, undefined);
  await assert.rejects(claim(db, { game_played: true, remaining_chances: 9 }), alreadyClaimed);
  assert.strictEqual(stock(db), 4);
});

test("current direct-gift patch still works and keeps the client labels", async () => {
  const db = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt() });
  await claim(db, {
    game_played: true, game_type: "directGift", prize_won: "قسيمة 100", prizes_won: ["قسيمة 100"], remaining_chances: 0,
    claimed_gifts: [{ giftId: "g100", giftName: "قسيمة 100", quantity: 1, unitValue: 100, isVoucher: true }],
    claim_status: "handed_over", event_id: "E", branch_id: "b1",
  });
  const r = stored(db);
  assert.deepStrictEqual(r.claimed_gifts, [{ giftId: "g100", giftName: "قسيمة 100", quantity: 1, unitValue: 100, isVoucher: true }]);
  assert.strictEqual(r.remaining_chances, 0);
  assert.strictEqual(r.claim_status, "handed_over");
  assert.strictEqual(r.prize_won, "قسيمة 100");
  await assert.rejects(claim(db, { game_played: true, remaining_chances: 0 }), alreadyClaimed);
  assert.strictEqual(stock(db), 4);
});

test("multi-chance wheel: one claim per chance, then closed; claimed_gifts is the server ledger", async () => {
  const db = fakeDb({
    "events/E": event({ allowMultipleChances: true, maxChancesPerReceipt: 3, allocatedPrizes: [row("g100", 10)] }),
    "receipts_transactions/r1": receipt({ chances_earned: 3 }),
  });
  const won = [];
  for (const left of [2, 1, 0]) {
    won.push("g100");
    await claim(db, {
      game_played: true, game_type: "wheel", prizes_won: won.slice(), remaining_chances: left,
      claimed_gifts: won.map((p) => ({ giftId: "", giftName: p, quantity: 1, unitValue: 0, isVoucher: false })),
    }, { decrements: [{ prizeIdentifier: "g100", branchId: "b1", count: 1, gameType: "wheel" }] });
    assert.strictEqual(stored(db).remaining_chances, left);
    assert.strictEqual(stored(db).claimed_gifts.length, 3 - left);
  }
  await assert.rejects(claim(db, { game_played: true }), alreadyClaimed);
  assert.strictEqual(stock(db), 7);
});

test("multi-chance wheel with game_played-only patches still stops at the receipt's chances", async () => {
  const db = fakeDb({
    "events/E": event({ allowMultipleChances: true, maxChancesPerReceipt: 3, allocatedPrizes: [row("g100", 10)] }),
    "receipts_transactions/r1": receipt({ chances_earned: 3 }),
  });
  for (let i = 0; i < 3; i++) await claim(db, { game_played: true });
  await assert.rejects(claim(db, { game_played: true }), alreadyClaimed);
  assert.strictEqual(stock(db), 7);
  assert.strictEqual(stored(db).claimed_gifts.length, 3);
});

test("a claim that takes the whole unit limit closes the receipt even with chances left", async () => {
  const db = fakeDb({
    "events/E": event({ allowMultipleChances: true, maxChancesPerReceipt: 3, allocatedPrizes: [row("g100", 10)] }),
    "receipts_transactions/r1": receipt({ chances_earned: 3 }),
  });
  await claim(db, { game_played: true }, { decrements: [{ prizeIdentifier: "g100", branchId: "b1", count: 3 }] });
  assert.strictEqual(stored(db).remaining_chances, 0);
  await assert.rejects(claim(db, { game_played: true }), alreadyClaimed);
  assert.strictEqual(stock(db), 7);
});

test("legacy receipts: game_played without a stored chance count is claimed; a stored count above 0 stays open", async () => {
  const legacy = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt({ game_played: true, chances_earned: 3 }) });
  await assert.rejects(claim(legacy, { game_played: true }), alreadyClaimed);
  assert.strictEqual(stock(legacy), 5);

  const open = fakeDb({
    "events/E": event({ allowMultipleChances: true, maxChancesPerReceipt: 3 }),
    "receipts_transactions/r1": receipt({ game_played: true, chances_earned: 3, remaining_chances: 2, claimed_gifts: [{ giftId: "g100", quantity: 1 }] }),
  });
  await claim(open, { game_played: true });
  assert.strictEqual(stored(open).remaining_chances, 1);
  assert.strictEqual(stored(open).claimed_gifts.length, 2);
});

test("staff skip the already-claimed check; the per-receipt unit cap still binds them", async () => {
  const db = fakeDb({
    "events/E": event({ allowMultipleChances: true, maxChancesPerReceipt: 3, allocatedPrizes: [row("g100", 10)] }),
    "receipts_transactions/r1": receipt({ chances_earned: 3 }),
  });
  await claim(db, { game_played: true, remaining_chances: 0 });
  await assert.rejects(claim(db, { game_played: true }), alreadyClaimed);
  await claim(db, { game_played: true }, { actor: { staff: true, uid: "admin1" } });
  assert.strictEqual(stock(db), 8);
  assert.strictEqual(stored(db).claimedBy, "u1");
  assert.strictEqual(stored(db).claimed_gifts.length, 2);
  await assert.rejects(claim(db, {}, { actor: { staff: true, uid: "admin1" }, decrements: [{ prizeIdentifier: "g100", branchId: "b1", count: 5 }] })
    .then(() => claim(db, {}, { actor: { staff: true, uid: "admin1" } })), (e) => e.details.reason === "unit_cap_exhausted");
  assert.strictEqual(stock(db), 7);
});

test("confirm-only tap still works after a server-stamped claim", async () => {
  const db = fakeDb({ "events/E": event(), "receipts_transactions/r1": receipt() });
  await claim(db, { game_played: true });
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor: rep, decrements: [], receiptPatch: { handed_over_confirmed: true } });
  assert.strictEqual(stored(db).handed_over_confirmed, true);
  assert.strictEqual(stock(db), 4);
});
