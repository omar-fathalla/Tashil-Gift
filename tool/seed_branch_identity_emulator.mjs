// Seeds the local Firebase emulators only. Project ids that start with demo-
// are rejected by production, and every request goes to 127.0.0.1.
const projectId = 'demo-tashil-branch';
const authHost = 'http://127.0.0.1:9099';
const firestoreHost = 'http://127.0.0.1:8080';
const email = 'fixture-admin@demo.local';
const password = 'fixture-pass-234';

const shortName = 'فرع طنطا (الغربية)';
const outletName = 'فرع طنطا اوت ليت (الغربية)';
const receipt = '137/4/243/061126';

async function json(url, body, headers = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${url}\n${text.slice(0, 500)}`);
  }
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
function strings(values) {
  return { arrayValue: { values: values.map(str) } };
}
function ts(date) {
  return { timestampValue: date.toISOString() };
}

async function putDoc(collection, id, fields) {
  const url =
    `${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents/` +
    `${collection}/${id}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      'content-type': 'application/json',
      authorization: 'Bearer owner',
    },
    body: JSON.stringify({ fields }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${collection}/${id}\n${text.slice(0, 500)}`);
}

function integer(value) {
  return { integerValue: String(value) };
}

function prize(entry) {
  return {
    mapValue: {
      fields: {
        giftId: str(entry.giftId),
        name: str(entry.name),
        allocatedQuantity: integer(entry.allocated),
        remainingQuantity: integer(entry.remaining),
        branchId: str(entry.branchId),
        branchName: str(entry.branchName),
        giftType: str('product'),
        unitValue: num(0),
      },
    },
  };
}

const outletGift = {
  giftId: 'gift-outlet-243',
  name: 'هدية أوتليت طنطا',
  allocated: 7,
  remaining: 7,
  branchId: 'fathalla_243',
  branchName: outletName,
};
const shortGift = {
  giftId: 'gift-short-231',
  name: 'هدية طنطا القصيرة',
  allocated: 3,
  remaining: 3,
  branchId: 'fathalla_231',
  branchName: shortName,
};

function eventDoc(ids, names, { withGifts = false } = {}) {
  return {
    eventName: str('Synthetic branch fixture'),
    targetCompany: str('Fixture Company'),
    companySlug: str('fixture-co'),
    minimumSpend: num(140),
    isActive: bool(true),
    isAllBranches: bool(false),
    branchIds: strings(ids),
    branchNames: strings(names),
    retailChainName: str('Synthetic chain'),
    gameType: str(withGifts ? 'directGift' : ''),
    enableWhatsAppWinnerNotification: bool(false),
    enable_whatsapp_winner_notification: bool(false),
    requireVoucherSerials: bool(false),
    createdAt: ts(new Date()),
    ...(withGifts
      ? { allocatedPrizes: { arrayValue: { values: [prize(outletGift), prize(shortGift)] } } }
      : {}),
  };
}

function receiptDoc({ id, campaignId, branchId, branchDetected, receiptNumber }) {
  return putDoc('receipts_transactions', id, {
    receipt_number: str(receiptNumber),
    campaignId: str(campaignId),
    companySlug: str('fixture-co'),
    targetCompany: str('Fixture Company'),
    store_chain_detected: str('Synthetic chain'),
    branch_id: str(branchId),
    branch_detected: str(branchDetected),
    is_valid: bool(true),
    status: str('accepted'),
    target_company_total: num(185.5),
    total_value: num(185.5),
    timestamp: ts(new Date()),
    customerName: str('Synthetic Customer'),
    customerPhone: str('01000000000'),
    game_played: bool(false),
  });
}

let localId;
try {
  const signedUp = await json(
    `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`,
    { email, password, returnSecureToken: true },
  );
  localId = signedUp.localId;
} catch (error) {
  const message = String(error);
  if (!message.includes('EMAIL_EXISTS')) throw error;
  const signedIn = await json(
    `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo`,
    { email, password, returnSecureToken: true },
  );
  localId = signedIn.localId;
}
await json(
  `${authHost}/identitytoolkit.googleapis.com/v1/accounts:update?key=demo`,
  {
    localId,
    customAttributes: JSON.stringify({ role: 'super_admin' }),
  },
  { authorization: 'Bearer owner' },
);

await putDoc(
  'events',
  'fixture-order-a',
  eventDoc(['fathalla_231', 'fathalla_243'], [shortName, outletName], { withGifts: true }),
);
await putDoc(
  'events',
  'fixture-order-b',
  eventDoc(['fathalla_243', 'fathalla_231'], [outletName, shortName]),
);
await putDoc(
  'events',
  'fixture-two-chains',
  eventDoc(['fathalla_243', 'gomla_243'], [outletName, 'جملة ماركت 243']),
);

const rows = [
  ['a-code-243', 'fixture-order-a', 'fathalla_243', shortName, receipt],
  ['b-code-243', 'fixture-order-b', 'fathalla_243', shortName, receipt],
  ['a-no-id-code', 'fixture-order-a', '', shortName, receipt],
  ['a-exact-short', 'fixture-order-a', '', shortName, ''],
  ['a-partial', 'fixture-order-a', '', 'طنطا اوت', ''],
  ['a-unknown-code', 'fixture-order-a', '', 'فرع غير معروف', '10/1/999/061126'],
  ['a-foreign-id', 'fixture-order-a', 'gomla_418', shortName, receipt],
  ['a-stored-231', 'fixture-order-a', 'fathalla_231', outletName, receipt],
  ['chains-code-only', 'fixture-two-chains', '', 'فرع غير محدد', receipt],
];
for (const [id, campaignId, branchId, branchDetected, receiptNumber] of rows) {
  await receiptDoc({ id, campaignId, branchId, branchDetected, receiptNumber });
}

async function readDoc(collection, id) {
  const url =
    `${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents/` +
    `${collection}/${id}`;
  const res = await fetch(url, { headers: { authorization: 'Bearer owner' } });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${collection}/${id}\n${text.slice(0, 500)}`);
  return JSON.parse(text);
}

const event = await readDoc('events', 'fixture-order-a');
const prizes = event.fields.allocatedPrizes.arrayValue.values;
const outlet = prizes[0].mapValue.fields;
const shortPrize = prizes[1].mapValue.fields;
if (outlet.giftId.stringValue !== outletGift.giftId) {
  throw new Error('outlet gift id was not stored');
}
if (outlet.branchId.stringValue !== 'fathalla_243' || outlet.remainingQuantity.integerValue !== '7') {
  throw new Error(`outlet stock is not 7 on fathalla_243: ${JSON.stringify(outlet)}`);
}
if (shortPrize.giftId.stringValue !== shortGift.giftId || shortPrize.remainingQuantity.integerValue !== '3') {
  throw new Error('short-branch gift was not stored at remaining 3');
}
if (shortPrize.branchId.stringValue !== 'fathalla_231') {
  throw new Error('short gift is not on fathalla_231');
}

const foreign = await readDoc('receipts_transactions', 'a-foreign-id');
if (foreign.fields.branch_id.stringValue !== 'gomla_418') {
  throw new Error('gomla_418 was rewritten');
}
if (foreign.fields.branch_detected.stringValue !== shortName) {
  throw new Error('foreign-id receipt lost its stored name');
}

console.log(`Seeded demo-tashil-branch. Sign in as ${email}`);
console.log('Gift route: http://127.0.0.1:7357/fixture-gift');
console.log('Before claim: gift-outlet-243 remaining 7, gift-short-231 remaining 3');
console.log('After one claim: outlet remaining 6, short remaining 3, a-foreign-id branch_id stays gomla_418');
