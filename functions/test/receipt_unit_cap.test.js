const test = require("node:test");
const assert = require("node:assert");
const { applyCampaignPrizeClaim, receiptUnitLimit, claimedUnits, piecesPerOffer } = require("../security_functions")._testing;

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
const row = (giftId, rem) => ({ giftId, name: giftId, giftType: "voucher", unitValue: 100, branchId: "b1", remainingQuantity: rem });
const actor = { anonymous: true, uid: "u1" };
const edita = (extra = {}) => Object.assign({ companySlug: "372", isActive: true, allowMultipleChances: true, maxChancesPerReceipt: 3, balanceMode: "campaign_only", allocatedPrizes: [row("g100", 48), row("g50", 48)] }, extra);
const rcpt = (extra = {}) => Object.assign({ campaignId: "E", submittedByUid: "u1", branch_id: "b1", chances_earned: 3 }, extra);

test("receiptUnitLimit: ON uses cap, OFF => chances only, bounded by chances", () => {
  assert.strictEqual(receiptUnitLimit(edita(), rcpt()), 3);
  assert.strictEqual(receiptUnitLimit(edita({ allowMultipleChances: false }), rcpt({ chances_earned: 1 })), 1);
  assert.strictEqual(receiptUnitLimit(edita({ allowMultipleChances: false }), rcpt({ chances_earned: 2 })), 2);
  assert.strictEqual(receiptUnitLimit(edita(), rcpt({ chances_earned: 2 })), 2);
  assert.strictEqual(receiptUnitLimit(edita({ maxChancesPerReceipt: 0 }), rcpt({ chances_earned: null })), Infinity);
  assert.strictEqual(claimedUnits([{ quantity: 2 }, { quantity: 1 }]), 3);
});

test("server rejects 4 units when cap is 3 (no stock change)", async () => {
  const db = fakeDb({ "events/E": edita(), "receipts_transactions/r1": rcpt() });
  await assert.rejects(
    applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 4 }], receiptPatch: { game_played: true } }),
    (e) => e.code === "failed-precondition" && e.details.reason === "unit_cap_exceeded" && e.details.limit === 3,
  );
  assert.strictEqual(db.store.get("events/E").allocatedPrizes[0].remainingQuantity, 48);
});

test("server rejects 5x100+1x50 (the 62/12/250 case)", async () => {
  const db = fakeDb({ "events/E": edita(), "receipts_transactions/r1": rcpt() });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor,
    decrements: [{ prizeIdentifier: "g100", count: 5 }, { prizeIdentifier: "g50", count: 1 }], receiptPatch: { game_played: true } }));
});

test("server accepts 3 units at cap 3", async () => {
  const db = fakeDb({ "events/E": edita(), "receipts_transactions/r1": rcpt() });
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 3 }], receiptPatch: { game_played: true } });
  assert.strictEqual(db.store.get("events/E").allocatedPrizes[0].remainingQuantity, 45);
});

test("receipt chances 1 rejects 2 units (the 293/4/218 case)", async () => {
  const db = fakeDb({ "events/E": edita(), "receipts_transactions/r1": rcpt({ chances_earned: 1 }) });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor,
    decrements: [{ prizeIdentifier: "g100", count: 2 }], receiptPatch: { game_played: true } }));
});

test("switch OFF: bounded by the receipt's chances (1 => exactly 1 unit)", async () => {
  const db = fakeDb({ "events/E": edita({ allowMultipleChances: false }), "receipts_transactions/r1": rcpt({ chances_earned: 1 }) });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 2 }], receiptPatch: {} }));
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 1 }], receiptPatch: {} });
});

test("units already claimed on a multi-chance receipt count toward the cap", async () => {
  const db = fakeDb({ "events/E": edita(), "receipts_transactions/r1": rcpt({ claimed_gifts: [{ giftId: "g100", quantity: 2 }], remaining_chances: 1 }) });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 2 }], receiptPatch: {} }));
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 1 }], receiptPatch: {} });
});

test("confirm-only tap after auto-claim: no stock change, marks confirmed", async () => {
  const db = fakeDb({ "events/E": edita(), "receipts_transactions/r1": rcpt({ game_played: true, remaining_chances: 0, claimed_gifts: [{ giftId: "g100", quantity: 3 }] }) });
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [], receiptPatch: { handed_over_confirmed: "yes", claim_status: "x" } })
    .then(() => assert.fail("mixed patch must not bypass the claimed check"), (e) => assert.strictEqual(e.code, "failed-precondition"));
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [], receiptPatch: { handed_over_confirmed: "yes" } });
  const r = db.store.get("receipts_transactions/r1");
  assert.strictEqual(r.handed_over_confirmed, true);
  assert.strictEqual(db.store.get("events/E").allocatedPrizes[0].remainingQuantity, 48);
});

test("confirm-only before any claim is rejected; second claim still blocked", async () => {
  const db = fakeDb({ "events/E": edita(), "receipts_transactions/r1": rcpt() });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [], receiptPatch: { handed_over_confirmed: true } }));
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 3 }], receiptPatch: { game_played: true, remaining_chances: 0 } });
  await assert.rejects(applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 1 }], receiptPatch: { game_played: true, remaining_chances: 0 } }),
    (e) => /already claimed/.test(e.message));
  assert.strictEqual(db.store.get("events/E").allocatedPrizes[0].remainingQuantity, 45);
});

test("multi-piece offer (6 bags per offer) counts as one unit", async () => {
  const ev = edita({ promotionalRules: [{ linkedGifts: [{ giftId: "g100", quantity: 6 }] }] });
  assert.strictEqual(piecesPerOffer(ev), 6);
  assert.strictEqual(receiptUnitLimit(ev, rcpt({ chances_earned: 2 })), 12);
  const db = fakeDb({ "events/E": ev, "receipts_transactions/r1": rcpt({ chances_earned: 2 }) });
  await applyCampaignPrizeClaim(db, { eventId: "E", receiptId: "r1", actor, decrements: [{ prizeIdentifier: "g100", count: 12 }], receiptPatch: {} });
  assert.strictEqual(db.store.get("events/E").allocatedPrizes[0].remainingQuantity, 36);
});
