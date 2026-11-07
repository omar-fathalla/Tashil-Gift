// Drives the real Flutter web screens against the local emulators.
// It seeds only the campaign. The receipt is created by the upload screen.
// Gemini is not called when the served build has both emulator defines and
// the uploaded file is the fixture bytes.
//
// 1. Start Auth 9099, Firestore 8080, and Functions 5001 for demo-tashil-branch.
//    Functions need FIREBASE_DEBUG_MODE=true and
//    FIREBASE_DEBUG_FEATURES={"skipTokenVerification":true}.
//    Do not set those on the deployed function.
// 2. flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357 \
//      --dart-define=FIREBASE_EMULATOR=true \
//      --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true
// 3. node tool/consuming_upload_ui_runner.mjs
//
// Screens and selectors, in order:
//   /event/fixture-consuming-upload
//   button "رفع من المعرض (الملفات)" then input[type=file]
//   button "فحص الفاتورة بالذكاء الاصطناعي"
//   back from the gift screen without confirming
//   /login  email input, password input, button "دخول الحساب"
//   /admin  "الفواتير"
//   receipt "901/1/901/071126"
//   Scroll the exact receipt card into view, then click its visible
//   "خيارات الفاتورة" control. The click is bounded and is not sent while
//   that control is offscreen.
//   "إعادة فحص OCR بالذكاء الاصطناعي"
//   "فحص سريع للقواعد الحالية"
//   "اختيار وتسليم الهدية للعميل الآن"
//   text "قسيمة شراء 150 جنيه"
//   button "تأكيد الهدية"
//
// FAULT is local only. It never writes claimed gifts or stock, and it does
// not delete the fixture receipt.
//   ledger-read            abort the server receipt GET when the gift screen opens
//   ledger-missing-fresh   a new browser context and a receipt id that Firestore
//                          REST already returns as 404. A Listen/channel 404 is
//                          not this check: a cached document 200 can still be shown.
//   offline                abort 127.0.0.1:5001 only while confirming
//   missing-rules          seed the local campaign with no spend rules, then expect
//                          the config rejection instead of a gift screen
// Wheel, scratch, direct gift, and the demo mystery box do not send a
// consuming slot. A consuming campaign is routed to the round gift screen.

import { mkdirSync, writeFileSync } from 'node:fs';
import { chromium } from 'playwright-core';

const projectId = 'demo-tashil-branch';
const host = '127.0.0.1';
const appUrl = process.env.UPLOAD_UI_URL || `http://${host}:7357`;
const eventId = 'fixture-consuming-upload';
const receiptNumber = '901/1/901/071126';
const gift500 = '4QDy4H8psECEP4AnJSON';
const gift350 = 'beGiYXcMAsW78OGevW5d';
const adminEmail = 'upload-ui-admin@demo.local';
const adminPassword = 'fixture-pass-234';
const shots = '/tmp/consuming-upload-ui';
const fixturePath = `${shots}/synthetic-receipt-1402.bin`;

function assertLocal(url) {
  const parsed = new URL(url);
  if (parsed.hostname !== '127.0.0.1' && parsed.hostname !== 'localhost') {
    throw new Error(`Refusing non-local URL ${url}`);
  }
}

async function json(url, body, headers = {}) {
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

function str(value) { return { stringValue: value }; }
function bool(value) { return { booleanValue: value }; }
function num(value) { return { doubleValue: value }; }
function integer(value) { return { integerValue: String(value) }; }
function list(values) { return { arrayValue: { values } }; }

function tier(id, min, giftId, amount) {
  return {
    mapValue: {
      fields: {
        id: str(id),
        ruleTitle: str(`شريحة ${min}`),
        conditionType: str('by_spend'),
        minSpend: num(min),
        triggerProduct: str('كادبري'),
        requiredBrands: list([str('كادبري')]),
        selectedBarcodes: list([str('6220000000011')]),
        rewardType: str('voucher'),
        rewardValue: str(`قسيمة شراء ${amount} جنيه`),
        rewardAmount: num(amount),
        allowMultipliers: bool(true),
        rewardOptions: list([{
          mapValue: {
            fields: {
              id: str(`opt-${id}`),
              kind: str('voucher'),
              giftId: str(giftId),
              giftType: str('voucher'),
              voucherAmount: num(amount),
              label: str(`قسيمة شراء ${amount} جنيه`),
            },
          },
        }]),
      },
    },
  };
}

function stock(giftId, unit) {
  return {
    mapValue: {
      fields: {
        giftId: str(giftId),
        name: str(`قسيمة شراء ${unit} جنيه`),
        giftType: str('voucher'),
        unitValue: num(unit),
        remainingQuantity: integer(5),
        allocatedQuantity: integer(5),
      },
    },
  };
}

async function putDoc(collection, id, fields) {
  const url = `http://${host}:8080/v1/projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', authorization: 'Bearer owner' },
    body: JSON.stringify({ fields }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${collection}/${id}\n${text.slice(0, 400)}`);
}

async function deleteDoc(collection, id) {
  const url = `http://${host}:8080/v1/projects/${projectId}/databases/(default)/documents/${collection}/${id}`;
  await fetch(url, { method: 'DELETE', headers: { authorization: 'Bearer owner' } });
}

async function seedCampaign() {
  await json(`http://${host}:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
    email: adminEmail,
    password: adminPassword,
    returnSecureToken: true,
  });
  const signed = await json(
    `http://${host}:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo`,
    { email: adminEmail, password: adminPassword, returnSecureToken: true },
  );
  await json(
    `http://${host}:9099/identitytoolkit.googleapis.com/v1/accounts:update?key=demo`,
    { localId: signed.localId, customAttributes: JSON.stringify({ role: 'super_admin' }) },
    { authorization: 'Bearer owner' },
  );
  await putDoc('events', eventId, {
    eventName: str('اختبار سلم الإنفاق'),
    targetCompany: str('كادبري'),
    companySlug: str('fixture-co'),
    minimumSpend: num(200),
    isActive: bool(true),
    gameType: str('chooseGift'),
    spendLadderMode: str('consuming'),
    allowMultipleChances: bool(true),
    maxChancesPerReceipt: integer(3),
    retailChainName: str('سلسلة الاختبار'),
    branchNames: list([str('فرع الاختبار')]),
    isAllBranches: bool(true),
    enableWhatsAppWinnerNotification: bool(false),
    promotionalRules: process.env.FAULT === 'missing-rules'
      ? list([])
      : list([
      tier('tier-200', 200, 'gift-200', 50),
      tier('tier-350', 350, gift350, 100),
      tier('tier-500', 500, gift500, 150),
    ]),
    allocatedPrizes: list([
      stock(gift500, 150),
      stock(gift500, 100),
      stock(gift350, 100),
    ]),
  });
  if (process.env.SKIP_UPLOAD !== '1') {
    await deleteDoc('receipts_transactions', `rcpt_${eventId}_901_1_901_071126`);
  }
}

async function shot(page, name) {
  await page.screenshot({ path: `${shots}/${name}.png`, fullPage: true });
}

async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { timeout: 20000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
}

async function fillFlutterField(page, ariaLabel, value, { tabInto = false } = {}) {
  const field = page.locator(`input[aria-label="${ariaLabel}"]`);
  await field.waitFor({ timeout: 15000 });
  if (tabInto) {
    await page.keyboard.press('Tab');
    const focused = await page.evaluate((label) => {
      const el = document.activeElement;
      return !!(el && el.getAttribute('aria-label') === label);
    }, ariaLabel);
    if (!focused) {
      throw new Error(`Tab did not move Flutter focus to "${ariaLabel}". Stopped before submit.`);
    }
  } else {
    await field.click();
    if ((await field.inputValue()).length > 0) await page.keyboard.press('Control+A');
  }
  await page.keyboard.insertText(value);
  const actual = await field.inputValue();
  const focusedLength = await page.evaluate((label) => {
    const el = document.activeElement;
    if (!el || el.getAttribute('aria-label') !== label) return -1;
    return (el.value || '').length;
  }, ariaLabel);
  if (actual !== value || focusedLength !== value.length) {
    throw new Error(
      `Login field "${ariaLabel}" length ${actual.length}, focused length ${focusedLength}, expected ${value.length}. Stopped before submit.`,
    );
  }
}

const faults = new Set(['', 'ledger-read', 'ledger-missing-fresh', 'offline', 'missing-rules']);
const missingProbeId = 'rcpt_demo_missing_ledger_probe';

async function openExactInvoiceMenu(page, number) {
  const maxSteps = 8;
  for (let step = 0; step < maxSteps; step++) {
    const placed = await page.evaluate((receiptNumber) => {
      const buttons = [...document.querySelectorAll('[role="button"]')];
      const row = buttons.find((node) => {
        const text = (node.textContent || '').trim();
        return text.includes(receiptNumber) && text.length < 80;
      });
      if (!row) return { found: false };
      row.scrollIntoView({ block: 'center', inline: 'nearest' });
      const view = { height: window.innerHeight, width: window.innerWidth };
      const rowRect = row.getBoundingClientRect();
      const menus = buttons.filter((node) => {
        const label = `${node.getAttribute('aria-label') || ''} ${node.textContent || ''}`;
        return label.includes('خيارات الفاتورة');
      });
      if (menus.length === 0) return { found: true, menu: false, rowTop: rowRect.top };
      const menu = menus.sort((a, b) => {
        return Math.abs(a.getBoundingClientRect().top - rowRect.top)
          - Math.abs(b.getBoundingClientRect().top - rowRect.top);
      })[0];
      menu.scrollIntoView({ block: 'center', inline: 'nearest' });
      const rect = menu.getBoundingClientRect();
      const aligned = Math.abs(rect.top - row.getBoundingClientRect().top) < 160;
      const visible = rect.width > 0 && rect.height > 0
        && rect.top >= 0 && rect.bottom <= view.height
        && rect.left >= 0 && rect.right <= view.width;
      return { found: true, menu: true, aligned, visible, rowTop: row.getBoundingClientRect().top };
    }, number);
    if (placed.found && placed.menu && placed.aligned && placed.visible) {
      const clicked = await page.evaluate((receiptNumber) => {
        const buttons = [...document.querySelectorAll('[role="button"]')];
        const row = buttons.find((node) => {
          const text = (node.textContent || '').trim();
          return text.includes(receiptNumber) && text.length < 80;
        });
        if (!row) return false;
        const top = row.getBoundingClientRect().top;
        const menu = buttons
          .filter((node) => `${node.getAttribute('aria-label') || ''} ${node.textContent || ''}`.includes('خيارات الفاتورة'))
          .sort((a, b) => Math.abs(a.getBoundingClientRect().top - top) - Math.abs(b.getBoundingClientRect().top - top))[0];
        if (!menu) return false;
        const rect = menu.getBoundingClientRect();
        const visible = rect.width > 0 && rect.height > 0
          && rect.top >= 0 && rect.bottom <= window.innerHeight
          && rect.left >= 0 && rect.right <= window.innerWidth
          && Math.abs(rect.top - top) < 160;
        if (!visible) return false;
        menu.click();
        return true;
      }, number);
      if (clicked) return;
    }
    await page.mouse.move(640, 450);
    const upward = placed.rowTop != null && placed.rowTop < 80;
    await page.mouse.wheel(0, upward ? -600 : 700);
    await page.waitForTimeout(350);
  }
  throw new Error(`Invoice options for #${number} stayed offscreen after ${maxSteps} scrolls`);
}

async function main() {
  const fault = process.env.FAULT || '';
  if (!faults.has(fault)) {
    throw new Error(`Unknown FAULT "${fault}". Use ledger-read, ledger-missing-fresh, offline, or missing-rules.`);
  }
  if (fault === 'missing-rules' && process.env.SKIP_UPLOAD === '1') {
    throw new Error('missing-rules uses the upload screen. Do not set SKIP_UPLOAD.');
  }
  assertLocal(appUrl);
  mkdirSync(shots, { recursive: true });
  writeFileSync(fixturePath, 'tashil-synthetic-receipt-v1:1402-ambiguous');
  if (fault !== 'ledger-missing-fresh') await seedCampaign();
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  let armLedgerFault = false;
  if (fault === 'ledger-read') {
    await page.route('**/documents/receipts_transactions/**', async (route) => {
      if (!armLedgerFault || route.request().method() !== 'GET') {
        await route.continue();
        return;
      }
      await route.abort('failed');
    });
  }
  let armOffline = false;
  if (fault === 'offline') {
    const blockFunctions = async (route) => {
      if (armOffline) await route.abort('failed');
      else await route.continue();
    };
    await page.route('http://127.0.0.1:5001/**', blockFunctions);
    await page.route('http://localhost:5001/**', blockFunctions);
  }
  const log = [];
  page.on('console', (msg) => log.push(`${msg.type()}: ${msg.text()}`));
  page.on('pageerror', (err) => log.push(`pageerror: ${err.message}`));
  try {
    if (fault === 'ledger-missing-fresh') {
      const probeUrl = `http://${host}:8080/v1/projects/${projectId}/databases/(default)/documents/receipts_transactions/${missingProbeId}`;
      const probe = await fetch(probeUrl);
      if (probe.status === 200) {
        throw new Error(
          `${missingProbeId} is present (HTTP 200). This mode does not delete it. A Listen 404 is not proof that the document is missing.`,
        );
      }
      if (probe.status !== 404) {
        throw new Error(`Expected Firestore REST 404 for ${missingProbeId}, got ${probe.status}.`);
      }
      const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
      const fresh = await context.newPage();
      await fresh.goto(`${appUrl}/login`, { waitUntil: 'domcontentloaded' });
      await enableSemantics(fresh);
      await fillFlutterField(fresh, 'البريد الإلكتروني', adminEmail);
      await fillFlutterField(fresh, 'كلمة المرور', adminPassword, { tabInto: true });
      await fresh.getByRole('button', { name: 'دخول الحساب' }).click();
      await fresh.goto(`${appUrl}/demo-ledger-missing`, { waitUntil: 'domcontentloaded' });
      await enableSemantics(fresh);
      await fresh.getByText('غير موجود على الخادم', { exact: false }).waitFor({ timeout: 20000 });
      await shot(fresh, '07-ledger-missing-fresh');
      console.log('ledger-missing-fresh saw a server miss in a cache-free session');
      return;
    }
    if (process.env.SKIP_UPLOAD !== '1') {
      await page.goto(`${appUrl}/event/${eventId}`, { waitUntil: 'domcontentloaded', timeout: 120000 });
      await enableSemantics(page);
      await page.getByRole('button', { name: 'رفع من المعرض (الملفات)' }).waitFor({ timeout: 30000 });
      await shot(page, '01-upload-screen');
      const chooserPromise = page.waitForEvent('filechooser', { timeout: 30000 });
      await page.getByRole('button', { name: 'رفع من المعرض (الملفات)' }).click();
      const chooser = await chooserPromise;
      await chooser.setFiles(fixturePath);
      await page.getByText('فحص الفاتورة بالذكاء الاصطناعي').waitFor({ timeout: 30000 });
      await shot(page, '02-file-selected');
      await page.getByText('فحص الفاتورة بالذكاء الاصطناعي').click();
      if (fault === 'missing-rules') {
        await page.getByText('لا تحتوي على قاعدة إنفاق', { exact: false }).waitFor({ timeout: 60000 });
        await shot(page, '03-missing-rules');
        console.log('missing-rules fault reached the config rejection');
        return;
      }
      await page.getByText('الفرصة الحالية', { exact: false }).waitFor({ timeout: 60000 });
      await shot(page, '03-after-upload-gift-screen');
      await page.goBack();
    }
    await page.goto(`${appUrl}/login`, { waitUntil: 'domcontentloaded' });
    await enableSemantics(page);
    await fillFlutterField(page, 'البريد الإلكتروني', adminEmail);
    await fillFlutterField(page, 'كلمة المرور', adminPassword, { tabInto: true });
    await shot(page, '04-login-values');
    await page.getByRole('button', { name: 'دخول الحساب' }).click();
    await page.getByRole('button', { name: /^الفواتير/ }).waitFor({ timeout: 60000 });
    await shot(page, '04-admin');
    await page.evaluate(() => {
      const el = [...document.querySelectorAll('[role="button"]')].find((node) =>
        (node.getAttribute('aria-label') || node.textContent || '').trim().startsWith('الفواتير'),
      );
      el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await openExactInvoiceMenu(page, receiptNumber);
    await shot(page, '05-invoice-row');
    await page.getByText(`إعادة الفحص (#${receiptNumber})`).waitFor({ timeout: 20000 });
    await page.getByText('إعادة فحص OCR بالذكاء الاصطناعي').click();
    await page.getByText('فحص سريع للقواعد الحالية').click();
    await page.getByText('شريحة 350').waitFor({ timeout: 30000 });
    await shot(page, '06-recheck-rounds');
    armLedgerFault = fault === 'ledger-read';
    await page.getByText('اختيار وتسليم الهدية للعميل الآن').click();
    if (armLedgerFault) {
      await page.getByText('إعادة قراءة السجل', { exact: false }).waitFor({ timeout: 20000 });
      await shot(page, '07-ledger-fault');
      console.log(`${fault} fault kept the gift screen closed`);
      return;
    }
    await page.getByText('قسيمة شراء 150 جنيه').click();
    armOffline = fault === 'offline';
    await page.getByText('تأكيد الهدية', { exact: false }).click();
    if (armOffline) {
      await page.getByText('لم يُحفظ صرف هذه الجولة', { exact: false }).waitFor({ timeout: 30000 });
      await shot(page, '07-offline-fault');
      console.log('offline fault refused the local stock write');
      return;
    }
    await page.getByText('جاري التأكيد', { exact: false }).waitFor({ state: 'hidden', timeout: 30000 }).catch(() => {});
    await shot(page, '07-after-claim');
    writeFileSync(`${shots}/console.txt`, log.join('\n'));
    console.log(`upload ui runner finished; screenshots in ${shots}`);
  } catch (error) {
    await shot(page, 'failure').catch(() => {});
    writeFileSync(`${shots}/console.txt`, log.join('\n'));
    console.error(error && error.stack ? error.stack : error);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

main();
