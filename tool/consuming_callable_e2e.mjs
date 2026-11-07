// Isolated consuming-ladder claim check. Every request stays on 127.0.0.1 and
// the project id is demo-tashil-branch, which production Firebase rejects.
// No Gemini call and no live project.
//
// The deployed function keeps enforceAppCheck: true. The functions emulator
// verifies that header unless it was started with the local debug switch
// below. Do not set those variables on a deployed function.
//
//   FIREBASE_DEBUG_MODE=true \
//   FIREBASE_DEBUG_FEATURES='{"skipTokenVerification":true}' \
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   npx -y firebase-tools@latest emulators:start \
//     --only auth,firestore,functions --project demo-tashil-branch
//
// If Auth and Firestore are already running, start Functions alone with
// firebase.e2e.json so it does not take their hub port:
//
//   FIREBASE_DEBUG_MODE=true \
//   FIREBASE_DEBUG_FEATURES='{"skipTokenVerification":true}' \
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   npx -y firebase-tools@latest emulators:start \
//     --only functions --project demo-tashil-branch --config firebase.e2e.json
//
// Then: node tool/consuming_callable_e2e.mjs

const projectId = "demo-tashil-branch";
const host = "127.0.0.1";
const authHost = `http://${host}:9099`;
const firestoreHost = `http://${host}:8080`;
const functionsHost = `http://${host}:5001`;
const email = "consuming-e2e@demo.local";
const password = "fixture-pass-234";
const gift500 = "4QDy4H8psECEP4AnJSON";
const gift350 = "beGiYXcMAsW78OGevW5d";
const eventId = "fixture-consuming-e2e";

function assertLoopback() {
  for (const value of [authHost, firestoreHost, functionsHost, projectId]) {
    if (value.includes("cloudfunctions.net") || value.includes("googleapis.com") && value.startsWith("https")) {
      throw new Error("Refusing a non-local target");
    }
  }
  if (!projectId.startsWith("demo-")) throw new Error("Refusing a non-demo project");
}

async function json(url, body, headers = {}) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${url}\n${text.slice(0, 600)}`);
  return text ? JSON.parse(text) : {};
}

function str(value) {
  return { stringValue: value };
}
function bool(value) {
  return { booleanValue: value };
}
function num(value) {
  return { doubleValue: value };
}
function integer(value) {
  return { integerValue: String(value) };
}
function list(values) {
  return { arrayValue: { values } };
}

async function putDoc(collection, id, fields) {
  const url = `${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
  const res = await fetch(url, {
    method: "PATCH",
    headers: { "content-type": "application/json", authorization: "Bearer owner" },
    body: JSON.stringify({ fields }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${collection}/${id}\n${text.slice(0, 600)}`);
}

async function readDoc(collection, id) {
  const url = `${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
  const res = await fetch(url, { headers: { authorization: "Bearer owner" } });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} read ${collection}/${id}\n${text.slice(0, 600)}`);
  return JSON.parse(text).fields || {};
}

function numberField(field) {
  if (!field) return 0;
  if (field.integerValue != null) return Number(field.integerValue);
  if (field.doubleValue != null) return Number(field.doubleValue);
  return 0;
}

function tier(id, min, giftId, amount) {
  return {
    mapValue: {
      fields: {
        id: str(id),
        conditionType: str("by_spend"),
        minSpend: num(min),
        triggerProduct: str("كادبري"),
        requiredBrands: list([str("كادبري")]),
        selectedBarcodes: list([str("6220000000011")]),
        allowMultipliers: bool(true),
        rewardOptions: list([{
          mapValue: {
            fields: {
              kind: str("voucher"),
              giftId: str(giftId),
              giftType: str("voucher"),
              voucherAmount: num(amount),
              label: str(`قسيمة شراء ${amount} جنيه`),
            },
          },
        }]),
      },
    },
  };
}

function stockRow(giftId, unit, remaining) {
  return {
    mapValue: {
      fields: {
        giftId: str(giftId),
        name: str(`قسيمة شراء ${unit} جنيه`),
        giftType: str("voucher"),
        unitValue: num(unit),
        remainingQuantity: integer(remaining),
        allocatedQuantity: integer(remaining),
      },
    },
  };
}

function product(price) {
  return {
    mapValue: {
      fields: {
        name: str("كادبري بوبل"),
        price: num(price),
        quantity: integer(1),
        barcode: str("6220000000011"),
        discountAmount: num(0),
      },
    },
  };
}

function receiptFields(extra = {}) {
  return Object.assign({
    campaignId: str(eventId),
    submittedByUid: str("pending"),
    chances_earned: integer(1),
    game_played: bool(false),
    remaining_chances: integer(3),
    extracted_products: list([492, 240, 294, 294, 82].map(product)),
  }, extra);
}

async function signIn() {
  let localId;
  let idToken;
  try {
    const signed = await json(
      `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`,
      { email, password, returnSecureToken: true },
    );
    localId = signed.localId;
    idToken = signed.idToken;
  } catch (error) {
    if (!String(error).includes("EMAIL_EXISTS")) throw error;
    const signed = await json(
      `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo`,
      { email, password, returnSecureToken: true },
    );
    localId = signed.localId;
    idToken = signed.idToken;
  }
  await json(
    `${authHost}/identitytoolkit.googleapis.com/v1/accounts:update?key=demo`,
    { localId, customAttributes: JSON.stringify({ role: "super_admin" }) },
    { authorization: "Bearer owner" },
  );
  const refreshed = await json(
    `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo`,
    { email, password, returnSecureToken: true },
  );
  return { localId, idToken: refreshed.idToken || idToken };
}

async function callClaim(idToken, receiptId, prizeIdentifier, unitValue, patch) {
  const res = await fetch(
    `${functionsHost}/${projectId}/us-central1/decrementCampaignPrize`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${idToken}`,
        "x-firebase-appcheck": "local.emulator.token",
      },
      body: JSON.stringify({
        data: {
          eventId,
          receiptId,
          decrements: [{
            prizeIdentifier,
            count: 1,
            unitValue,
            isVoucher: true,
            gameType: "chooseGift",
          }],
          receiptPatch: Object.assign({
            game_played: true,
            claimed_gifts: [{ giftId: "forged", giftName: "قسيمة شراء 100 جنيه", quantity: 9, unitValue: 100 }],
            prize_won: "قسيمة شراء 100 جنيه",
            remaining_chances: 0,
          }, patch),
        },
      }),
    },
  );
  const text = await res.text();
  let body = {};
  try {
    body = text ? JSON.parse(text) : {};
  } catch (_) {
    body = { raw: text.slice(0, 400) };
  }
  return { status: res.status, body };
}

function ledger(fields) {
  const values = fields.claimed_gifts && fields.claimed_gifts.arrayValue
    ? fields.claimed_gifts.arrayValue.values || []
    : [];
  return values.map((entry) => {
    const gift = entry.mapValue.fields;
    return {
      giftId: gift.giftId && gift.giftId.stringValue,
      unitValue: numberField(gift.unitValue),
      quantity: gift.quantity ? numberField(gift.quantity) : 1,
    };
  });
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

async function main() {
  assertLoopback();
  let authUp = false;
  try {
    authUp = (await fetch(authHost)).status < 500;
  } catch (_) {
    authUp = false;
  }
  if (!authUp) {
    console.error("Local Auth emulator is not on 127.0.0.1:9099.");
    console.error("Start the demo emulators with the command at the top of this file.");
    process.exit(2);
  }
  try {
    await fetch(functionsHost);
  } catch (_) {
    console.error("Local Functions emulator is not on 127.0.0.1:5001.");
    console.error("Start it with the command at the top of this file. Do not point it at a live project.");
    process.exit(2);
  }
  const { localId, idToken } = await signIn();
  await putDoc("events", eventId, {
    companySlug: str("fixture-co"),
    isActive: bool(true),
    spendLadderMode: str("consuming"),
    allowMultipleChances: bool(true),
    maxChancesPerReceipt: integer(3),
    balanceMode: str("campaign_only"),
    promotionalRules: list([
      tier("tier-200", 200, "gift-200", 50),
      tier("tier-350", 350, gift350, 100),
      tier("tier-500", 500, gift500, 150),
    ]),
    allocatedPrizes: list([
      stockRow(gift500, 150, 5),
      stockRow(gift500, 100, 5),
      stockRow(gift350, 100, 5),
    ]),
  });
  const owner = { submittedByUid: str(localId) };
  await putDoc("receipts_transactions", "e2e-happy", receiptFields(owner));
  await putDoc("receipts_transactions", "e2e-reject", receiptFields(owner));
  await putDoc("receipts_transactions", "e2e-legacy", receiptFields(Object.assign({}, owner, {
    game_played: bool(true),
    remaining_chances: integer(2),
    claimed_gifts: list([{
      mapValue: { fields: { giftId: str(gift500), giftName: str("قسيمة شراء 150 جنيه") } },
    }]),
  })));
  await putDoc("receipts_transactions", "e2e-race-a", receiptFields(owner));
  await putDoc("receipts_transactions", "e2e-race-b", receiptFields(owner));

  const probe = await callClaim(idToken, "e2e-reject", "unknown-gift", 150);
  if (probe.status === 401 || (probe.body.error && probe.body.error.status === "UNAUTHENTICATED")) {
    console.error("Callable rejected the local App Check header.");
    console.error("Restart ONLY the local functions emulator with FIREBASE_DEBUG_MODE=true and FIREBASE_DEBUG_FEATURES={\"skipTokenVerification\":true}.");
    console.error("Leave enforceAppCheck true. Do not set those variables on the deployed function.");
    console.error(JSON.stringify(probe.body).slice(0, 500));
    process.exit(3);
  }
  if (probe.status !== 400 && !(probe.body.error && probe.body.error.status === "FAILED_PRECONDITION")) {
    fail(`Unknown gift was not rejected: ${probe.status} ${JSON.stringify(probe.body).slice(0, 500)}`);
  }
  const rejected = await readDoc("receipts_transactions", "e2e-reject");
  if (rejected.claimed_gifts) fail("Rejected claim wrote claimed_gifts");

  const nameOnly = await callClaim(idToken, "e2e-reject", "قسيمة شراء 150 جنيه", 150);
  if (!nameOnly.body.error) fail("Name-only claim was accepted");

  for (const prize of [gift500, gift500, gift350]) {
    const result = await callClaim(idToken, "e2e-happy", prize, prize === gift350 ? 150 : 100);
    if (result.body.error) fail(`Accepted round failed: ${JSON.stringify(result.body).slice(0, 500)}`);
  }
  const happy = ledger(await readDoc("receipts_transactions", "e2e-happy"));
  const happyIds = happy.map((gift) => gift.giftId).join(",");
  const happyValues = happy.map((gift) => gift.unitValue).join(",");
  if (happyIds !== `${gift500},${gift500},${gift350}`) fail(`Ledger ids ${happyIds}`);
  if (happyValues !== "150,150,100") fail(`Ledger values ${happyValues}`);
  const extra = await callClaim(idToken, "e2e-happy", gift500, 150);
  if (!extra.body.error) fail("Fourth round was accepted");

  const legacy = await callClaim(idToken, "e2e-legacy", gift500, 100, { claimed_gifts: [] });
  if (legacy.body.error) fail(`Legacy retry failed: ${JSON.stringify(legacy.body).slice(0, 500)}`);
  const legacyLedger = ledger(await readDoc("receipts_transactions", "e2e-legacy"));
  if (legacyLedger.length !== 2) fail(`Missing quantity reset the ledger: ${legacyLedger.length}`);
  if (legacyLedger[0].quantity !== 1 || legacyLedger[1].unitValue !== 150) {
    fail(`Legacy entry was replaced: ${JSON.stringify(legacyLedger)}`);
  }

  const [first, second] = await Promise.all([
    callClaim(idToken, "e2e-race-a", gift500, 100),
    callClaim(idToken, "e2e-race-a", gift500, 100),
  ]);
  if (first.body.error || second.body.error) {
    fail(`Concurrent claims rejected: ${JSON.stringify(first.body).slice(0, 240)} ${JSON.stringify(second.body).slice(0, 240)}`);
  }
  const raced = ledger(await readDoc("receipts_transactions", "e2e-race-a"));
  if (raced.length !== 2 || raced[0].unitValue !== 150 || raced[1].unitValue !== 150) {
    fail(`Concurrent ledger was replaced: ${JSON.stringify(raced)}`);
  }

  const event = await readDoc("events", eventId);
  const rows = event.allocatedPrizes.arrayValue.values;
  const canonical500 = numberField(rows[0].mapValue.fields.remainingQuantity);
  const lying100 = numberField(rows[1].mapValue.fields.remainingQuantity);
  const canonical350 = numberField(rows[2].mapValue.fields.remainingQuantity);
  // happy 2, legacy 1, race 2 => five canonical 500 decrements. lying row stays 5.
  // happy one 350 decrement.
  if (canonical500 !== 0 || lying100 !== 5 || canonical350 !== 4) {
    fail(`Stock canonical500=${canonical500} lying100=${lying100} canonical350=${canonical350}`);
  }
  if (ledger(await readDoc("receipts_transactions", "e2e-race-b")).length !== 0) {
    fail("Unused receipt changed");
  }
  console.log("consuming callable e2e passed on 127.0.0.1 demo-tashil-branch");
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
