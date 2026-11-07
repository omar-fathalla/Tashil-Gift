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

function eventDoc(ids, names) {
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
    createdAt: ts(new Date()),
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
  });
}

const signedUp = await json(
  `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`,
  { email, password, returnSecureToken: true },
);
await json(
  `${authHost}/identitytoolkit.googleapis.com/v1/accounts:update?key=demo`,
  {
    localId: signedUp.localId,
    customAttributes: JSON.stringify({ role: 'super_admin' }),
  },
  { authorization: 'Bearer owner' },
);

await putDoc(
  'events',
  'fixture-order-a',
  eventDoc(['fathalla_231', 'fathalla_243'], [shortName, outletName]),
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

console.log(`Seeded demo-tashil-branch. Sign in as ${email}`);
