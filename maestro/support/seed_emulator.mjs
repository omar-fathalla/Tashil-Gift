// Seeds the local emulators for the Maestro emulator smoke (TAG-82 PR 3).
//
// Local only: every URL is checked to be 127.0.0.1/localhost and the project
// is demo-tashil-branch. The account and password are fixtures that exist
// only inside the Auth emulator; they are not secrets. The campaign has
// WhatsApp winner messages off. Nothing here reaches tashil-gift-dev,
// tashil-gift, Gemini or WAHA.
//
// Usage: node maestro/support/seed_emulator.mjs   (inside emulators:exec)

export const projectId = 'demo-tashil-branch';
const host = '127.0.0.1';
export const adminEmail = 'maestro-admin@demo.local';
export const adminPassword = 'fixture-pass-maestro';
export const eventId = 'maestro-smoke-campaign';
export const eventName = 'حملة Maestro التجريبية';

function assertLocal(url) {
  const { hostname } = new URL(url);
  if (hostname !== '127.0.0.1' && hostname !== 'localhost') {
    throw new Error(`Refusing non-local URL ${url}`);
  }
}

async function post(url, body, headers = {}) {
  assertLocal(url);
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok && !text.includes('EMAIL_EXISTS')) {
    throw new Error(`${res.status} ${url}\n${text.slice(0, 400)}`);
  }
  return text ? JSON.parse(text) : {};
}

async function seedAdmin() {
  const auth = `http://${host}:9099/identitytoolkit.googleapis.com/v1`;
  await post(`${auth}/accounts:signUp?key=demo`, { email: adminEmail, password: adminPassword, returnSecureToken: true });
  const signed = await post(`${auth}/accounts:signInWithPassword?key=demo`, {
    email: adminEmail,
    password: adminPassword,
    returnSecureToken: true,
  });
  await post(
    `${auth}/accounts:update?key=demo`,
    { localId: signed.localId, customAttributes: JSON.stringify({ role: 'super_admin' }) },
    { authorization: 'Bearer owner' },
  );
}

const str = (v) => ({ stringValue: v });
const bool = (v) => ({ booleanValue: v });
const num = (v) => ({ doubleValue: v });
const list = (values) => ({ arrayValue: { values } });

async function seedCampaign() {
  const url = `http://${host}:8080/v1/projects/${projectId}/databases/(default)/documents/events/${eventId}`;
  assertLocal(url);
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', authorization: 'Bearer owner' },
    body: JSON.stringify({
      fields: {
        eventName: str(eventName),
        targetCompany: str('كادبري'),
        companySlug: str('fixture-co'),
        minimumSpend: num(200),
        isActive: bool(true),
        gameType: str('chooseGift'),
        retailChainName: str('سلسلة الاختبار'),
        branchNames: list([str('فرع الاختبار')]),
        isAllBranches: bool(true),
        enableWhatsAppWinnerNotification: bool(false),
      },
    }),
  });
  if (!res.ok) throw new Error(`${res.status} events/${eventId}\n${(await res.text()).slice(0, 400)}`);
}

if (!projectId.startsWith('demo-')) throw new Error('project must be demo-*');
await seedAdmin();
await seedCampaign();
console.log(`seed_emulator: admin ${adminEmail} and campaign ${eventId} on ${projectId}`);
