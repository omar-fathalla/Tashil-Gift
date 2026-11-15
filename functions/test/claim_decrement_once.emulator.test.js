/**
 * Decrement-once for a receipt claim against the local emulators (demo-tashil only).
 * The receipt's claim state is stamped by the server transaction, so the
 * client receiptPatch cannot leave a claimed receipt open.
 *
 * Run from functions/: npm run test:emulator
 * The App Check skip is for the emulator only; never set it on a deployed function.
 */
const test = require("node:test");
const assert = require("node:assert");
const admin = require("../admin_sdk");
const { applyCampaignPrizeClaim } = require("../security_functions")._testing;

const PROJECT = process.env.GCLOUD_PROJECT || "";
const RUN = !!process.env.FIRESTORE_EMULATOR_HOST && PROJECT.startsWith("demo-");
const CALLABLE = RUN && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099"}`;

const DAY = 24 * 3600 * 1000;
const BARCODE = "6221134031478";
const DECREMENTS = [{ prizeIdentifier: "g150", branchId: "b1", count: 1 }];
const GAME_PLAYED_ONLY = { game_played: true };
const CURRENT_CLIENT = {
  game_played: true, game_type: "directGift", prize_won: "قسيمة 150", prizes_won: ["قسيمة 150"],
  claimed_gifts: [{ giftId: "g150", giftName: "قسيمة 150", quantity: 1, unitValue: 150, isVoucher: true }],
  event_id: "", branch_id: "b1", remaining_chances: 0, claim_status: "handed_over",
};
let db;

function campaign() {
  const now = Date.now();
  return {
    eventName: "Decrement-once fixture", companySlug: "once", isActive: true,
    startDate: admin.firestore.Timestamp.fromMillis(now - 10 * DAY),
    endDate: admin.firestore.Timestamp.fromMillis(now + 10 * DAY),
    balanceMode: "campaign_only", allowMultipleChances: false, maxChancesPerReceipt: 1,
    promotionalRules: [{
      id: "t150", conditionType: "by_spend", minSpend: 150, selectedBarcodes: [BARCODE],
      linkedGifts: [{ giftId: "g150", giftName: "قسيمة 150", quantity: 1 }],
    }],
    allocatedPrizes: [{ giftId: "g150", name: "قسيمة 150", giftType: "voucher", unitValue: 150, branchId: "b1", remainingQuantity: 5 }],
  };
}

async function seed(id, uid) {
  await db.collection("events").doc(`E_${id}`).set(campaign());
  await db.collection("receipts_transactions").doc(`R_${id}`).set({
    campaignId: `E_${id}`, submittedByUid: uid, branch_id: "b1", chances_earned: 1,
    timestamp: admin.firestore.Timestamp.now(), game_played: false,
    extracted_products: [{ name: "جلاكسي شوكولاتة", price: 200, quantity: 1, barcode: BARCODE, isTargetCompany: true }],
  });
}

async function stock(id) {
  return (await db.collection("events").doc(`E_${id}`).get()).data().allocatedPrizes[0].remainingQuantity;
}

async function receipt(id) {
  return (await db.collection("receipts_transactions").doc(`R_${id}`).get()).data();
}

const claim = (id, uid, receiptPatch) => applyCampaignPrizeClaim(db, {
  eventId: `E_${id}`, receiptId: `R_${id}`, actor: { anonymous: true, uid },
  decrements: DECREMENTS, receiptPatch,
});

function assertAlreadyClaimed(err) {
  assert.strictEqual(err.code, "failed-precondition", String(err && err.message));
  assert.strictEqual(err.details.reason, "already_claimed");
  return true;
}

function assertStamped(r) {
  assert.strictEqual(r.remaining_chances, 0);
  assert.strictEqual(r.game_played, true);
  assert.deepStrictEqual(r.claimed_gifts.map((g) => [g.giftId, g.quantity]), [["g150", 1]]);
  assert.ok(r.claimedAt instanceof admin.firestore.Timestamp);
  assert.ok(r.claimedBy);
}

test.before(() => {
  if (!RUN) return;
  admin.initializeApp({ projectId: PROJECT });
  db = admin.firestore();
});

for (const [label, patch] of [["game_played_only", GAME_PLAYED_ONLY], ["current_client", CURRENT_CLIENT]]) {
  test(`${label} patch: first claim stamps the receipt, sequential second claim is rejected with no writes`, { skip: !RUN }, async () => {
    const id = `seq_${label}`;
    await seed(id, "rep1");
    const out = await claim(id, "rep1", Object.assign({}, patch, { event_id: `E_${id}` }));
    assert.strictEqual(out.ok, true);
    assert.strictEqual(await stock(id), 4);
    const first = await receipt(id);
    assertStamped(first);
    assert.strictEqual(first.claimedBy, "rep1");
    if (label === "current_client") assert.strictEqual(first.claimed_gifts[0].giftName, "قسيمة 150");

    await assert.rejects(claim(id, "rep1", patch), assertAlreadyClaimed);
    assert.strictEqual(await stock(id), 4);
    assert.deepStrictEqual(await receipt(id), first);
  });
}

test("8 concurrent game_played-only claims: exactly one succeeds and stock decrements once", { skip: !RUN }, async () => {
  const id = "concurrent";
  await seed(id, "rep1");
  const results = await Promise.allSettled(Array.from({ length: 8 }, () => claim(id, "rep1", GAME_PLAYED_ONLY)));
  const ok = results.filter((r) => r.status === "fulfilled");
  assert.strictEqual(ok.length, 1, JSON.stringify(results.map((r) => r.status === "rejected" ? r.reason.message : "ok")));
  for (const r of results.filter((x) => x.status === "rejected")) assertAlreadyClaimed(r.reason);
  assert.strictEqual(await stock(id), 4);
  assertStamped(await receipt(id));
});

async function anonymousToken() {
  const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await res.json();
  assert.ok(body.idToken, JSON.stringify(body));
  return { idToken: body.idToken, uid: body.localId };
}

function callClaim(idToken, id, receiptPatch) {
  return fetch(`${FUNCTIONS}/decrementCampaignPrize`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${idToken}`, "x-firebase-appcheck": "local.emulator.token" },
    body: JSON.stringify({ data: { eventId: `E_${id}`, receiptId: `R_${id}`, receiptPatch, decrements: DECREMENTS } }),
  }).then(async (res) => ({ status: res.status, body: await res.json() }));
}

function assertCallableAlreadyClaimed(res) {
  assert.strictEqual(res.status, 400, JSON.stringify(res.body));
  assert.strictEqual(res.body.error.status, "FAILED_PRECONDITION");
  assert.strictEqual(res.body.error.details.reason, "already_claimed");
}

test("callable: game_played-only patch is rejected on the second claim", { skip: !CALLABLE }, async () => {
  const { idToken, uid } = await anonymousToken();
  await seed("callable_seq", uid);
  const first = await callClaim(idToken, "callable_seq", GAME_PLAYED_ONLY);
  assert.strictEqual(first.status, 200, JSON.stringify(first.body));
  assertCallableAlreadyClaimed(await callClaim(idToken, "callable_seq", GAME_PLAYED_ONLY));
  assert.strictEqual(await stock("callable_seq"), 4);
  assertStamped(await receipt("callable_seq"));
});

test("callable: current-client patch still claims once", { skip: !CALLABLE }, async () => {
  const { idToken, uid } = await anonymousToken();
  await seed("callable_client", uid);
  const first = await callClaim(idToken, "callable_client", CURRENT_CLIENT);
  assert.strictEqual(first.status, 200, JSON.stringify(first.body));
  assertCallableAlreadyClaimed(await callClaim(idToken, "callable_client", CURRENT_CLIENT));
  assert.strictEqual(await stock("callable_client"), 4);
});

test("callable: 8 concurrent game_played-only claims give exactly one success", { skip: !CALLABLE }, async () => {
  const { idToken, uid } = await anonymousToken();
  await seed("callable_concurrent", uid);
  const results = await Promise.all(Array.from({ length: 8 }, () => callClaim(idToken, "callable_concurrent", GAME_PLAYED_ONLY)));
  const ok = results.filter((r) => r.status === 200);
  assert.strictEqual(ok.length, 1, JSON.stringify(results.map((r) => r.status)));
  for (const r of results.filter((x) => x.status !== 200)) assertCallableAlreadyClaimed(r);
  assert.strictEqual(await stock("callable_concurrent"), 4);
  assertStamped(await receipt("callable_concurrent"));
});
