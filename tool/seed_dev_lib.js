/**
 * Pure parts of tool/seed_dev.js: the project guard and the fake data set.
 * No Firebase imports here, so functions/test/seed_dev_guard.test.js can test
 * them without credentials or emulators.
 *
 * EVERYTHING below is invented: company, chain and branch names say "تجربة",
 * barcodes start with 999, phone numbers are 0100000000x, e-mails use the
 * reserved example.com domain. No real customer, receipt or partner data.
 */
"use strict";

const DEV_PROJECT_ID = "tashil-gift-dev";
const PROD_PROJECT_ID = "tashil-gift";
const DEMO_PROJECT_RE = /^demo-[a-z0-9-]{1,40}$/;
const EMULATOR_VARS = ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"];

class SeedRefused extends Error {}

function argValue(argv, name) {
  const i = argv.indexOf(name);
  if (i !== -1) return argv[i + 1];
  const eq = argv.find((a) => a.startsWith(`${name}=`));
  return eq ? eq.slice(name.length + 1) : undefined;
}

/**
 * Decides where the seed may write, or throws SeedRefused.
 *
 * - `--project` is mandatory (no default, no .firebaserc, no ADC guessing).
 * - Only `tashil-gift-dev` or a `demo-*` emulator project is accepted;
 *   `tashil-gift` (production) and anything else is refused.
 * - `demo-*` requires all three emulator hosts, so it never leaves localhost.
 * - `tashil-gift-dev` requires `--confirm tashil-gift-dev`, no emulator hosts,
 *   and every project id visible in the environment / credentials file must be
 *   tashil-gift-dev too.
 */
function resolveSeedTarget({ argv = [], env = {}, credentialsProjectId = "" } = {}) {
  const project = (argValue(argv, "--project") || "").trim();
  if (!project) {
    throw new SeedRefused("Missing --project. Use --project tashil-gift-dev (or a demo-* emulator project).");
  }
  if (project === PROD_PROJECT_ID) {
    throw new SeedRefused("REFUSED: tashil-gift is PRODUCTION. This seed only writes fake data to tashil-gift-dev or a demo-* emulator.");
  }
  const dryRun = argv.includes("--dry-run");
  const mentioned = [env.GCLOUD_PROJECT, env.GOOGLE_CLOUD_PROJECT, credentialsProjectId].filter(Boolean);
  for (const p of mentioned) {
    if (p !== project) {
      throw new SeedRefused(`REFUSED: --project ${project} but the environment/credentials point at ${p}.`);
    }
  }
  if (DEMO_PROJECT_RE.test(project)) {
    const missing = EMULATOR_VARS.filter((v) => !env[v]);
    if (missing.length && !dryRun) {
      throw new SeedRefused(`REFUSED: ${project} is an emulator project but ${missing.join(", ")} is not set.`);
    }
    for (const v of EMULATOR_VARS) {
      const host = String(env[v] || "");
      if (host && !/^(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(host)) {
        throw new SeedRefused(`REFUSED: ${v}=${host} is not a localhost emulator.`);
      }
    }
    return { projectId: project, emulator: true, dryRun };
  }
  if (project !== DEV_PROJECT_ID) {
    throw new SeedRefused(`REFUSED: unknown project ${project}. Only ${DEV_PROJECT_ID} or demo-* is allowed.`);
  }
  const present = EMULATOR_VARS.filter((v) => env[v]);
  if (present.length) {
    throw new SeedRefused(`REFUSED: ${present.join(", ")} is set; unset the emulator variables to seed ${DEV_PROJECT_ID}.`);
  }
  if (!dryRun && argValue(argv, "--confirm") !== DEV_PROJECT_ID) {
    throw new SeedRefused(`Add --confirm ${DEV_PROJECT_ID} to write to the dev project (or --dry-run to only print the plan).`);
  }
  return { projectId: project, emulator: false, dryRun };
}

const DAY = 24 * 3600 * 1000;

/** The fake data set. `now` is injectable for tests. Ids are fixed (idempotent). */
function buildSeedData(now = Date.now()) {
  const companies = [
    { slug: "devco-choco", name: "شركة تجربة للشوكولاتة (DEV)" },
    { slug: "devco-clean", name: "شركة تجربة للمنظفات (DEV)" },
  ];
  const chains = [
    { id: "dev-chain-a", name: "سلسلة تجربة أ", slug: "dev-chain-a" },
    { id: "dev-chain-b", name: "سلسلة تجربة ب", slug: "dev-chain-b" },
  ];
  const branches = [
    { id: "dev-chain-a_101", retailChainId: "dev-chain-a", retailChainName: "سلسلة تجربة أ", branchName: "فرع الاختبار الأول", branchCode: "101", city: "مدينة تجربة" },
    { id: "dev-chain-a_102", retailChainId: "dev-chain-a", retailChainName: "سلسلة تجربة أ", branchName: "فرع الاختبار الثاني", branchCode: "102", city: "مدينة تجربة" },
    { id: "dev-chain-b_201", retailChainId: "dev-chain-b", retailChainName: "سلسلة تجربة ب", branchName: "فرع خارج الحملة", branchCode: "201", city: "مدينة تجربة" },
  ];
  const products = [
    { id: "devco-choco_9990000000011", companySlug: "devco-choco", companyName: companies[0].name, productName: "شوكولاتة تجربة بالبندق 100 جم", barcode: "9990000000011" },
    { id: "devco-choco_9990000000028", companySlug: "devco-choco", companyName: companies[0].name, productName: "بسكويت تجربة بالشوكولاتة", barcode: "9990000000028" },
    { id: "devco-choco_9990000000035", companySlug: "devco-choco", companyName: companies[0].name, productName: "شوكولاتة تجربة كبيرة 200 جم", barcode: "9990000000035" },
    { id: "devco-clean_9990000000042", companySlug: "devco-clean", companyName: companies[1].name, productName: "منظف تجربة 1 لتر", barcode: "9990000000042" },
  ];
  const gifts = [
    { id: "dev-gift-card-100", companySlug: "devco-choco", companyName: companies[0].name, giftName: "كارت مشتريات 100 جنيه (تجربة)", giftType: "voucher", unitValue: 100, totalQuantity: 50 },
    { id: "dev-gift-mug", companySlug: "devco-choco", companyName: companies[0].name, giftName: "مج تجربة", giftType: "product", unitValue: 0, totalQuantity: 30 },
    { id: "dev-gift-clean-bag", companySlug: "devco-clean", companyName: companies[1].name, giftName: "شنطة تجربة", giftType: "product", unitValue: 0, totalQuantity: 20 },
  ];
  const chocoBarcodes = products.filter((p) => p.companySlug === "devco-choco").map((p) => p.barcode);
  const baseEvent = (over) => Object.assign({
    targetCompany: companies[0].name,
    companySlug: "devco-choco",
    retailChainId: "dev-chain-a",
    retailChainName: "سلسلة تجربة أ",
    branchIds: ["dev-chain-a_101", "dev-chain-a_102"],
    branchNames: ["فرع الاختبار الأول", "فرع الاختبار الثاني"],
    isAllBranches: false,
    gameType: "directGift",
    minimumSpend: 150,
    balanceMode: "campaign_only",
    allowMultipleChances: false,
    maxChancesPerReceipt: 1,
    requireVoucherSerials: false,
    enableWhatsAppWinnerNotification: false,
    enable_whatsapp_winner_notification: false,
    welcomeTitle: "حملة تجربة",
    welcomeMessage: "دي حملة تجربة على بيئة التطوير. مفيش هدايا حقيقية.",
    termsAndConditions: "بيانات وهمية للتجربة فقط.",
    promotionalRules: [{
      id: "dev-rule-150", ruleTitle: "اشتري بـ 150 جنيه", conditionType: "by_spend", minSpend: 150,
      selectedBarcodes: chocoBarcodes,
      linkedGifts: [{ giftId: "dev-gift-card-100", giftName: "كارت مشتريات 100 جنيه (تجربة)", quantity: 1 }],
    }],
    allocatedPrizes: [
      { giftId: "dev-gift-card-100", name: "كارت مشتريات 100 جنيه (تجربة)", giftType: "voucher", unitValue: 100, branchId: "dev-chain-a_101", branchName: "فرع الاختبار الأول", allocatedQuantity: 10, remainingQuantity: 10 },
      { giftId: "dev-gift-card-100", name: "كارت مشتريات 100 جنيه (تجربة)", giftType: "voucher", unitValue: 100, branchId: "dev-chain-a_102", branchName: "فرع الاختبار الثاني", allocatedQuantity: 5, remainingQuantity: 5 },
    ],
  }, over);
  const events = [
    { id: "dev-campaign-active", ...baseEvent({ eventName: "حملة تجربة شغالة", isActive: true, startDate: new Date(now - DAY), endDate: new Date(now + 20 * DAY) }) },
    { id: "dev-campaign-paused", ...baseEvent({ eventName: "حملة تجربة موقوفة", isActive: false, startDate: new Date(now - DAY), endDate: new Date(now + 20 * DAY) }) },
    { id: "dev-campaign-scheduled", ...baseEvent({ eventName: "حملة تجربة تبدأ بكرة", isActive: true, startDate: new Date(now + DAY), endDate: new Date(now + 15 * DAY) }) },
    { id: "dev-campaign-ended", ...baseEvent({ eventName: "حملة تجربة خلصت", isActive: false, startDate: new Date(now - 30 * DAY), endDate: new Date(now - 2 * DAY) }) },
  ];
  const drafts = [
    { id: "dev-draft-1", eventName: "مسودة حملة تجربة", companySlug: "devco-clean", targetCompany: companies[1].name, isDraft: true },
  ];
  const users = [
    { key: "admin", email: "dev-admin@example.com", displayName: "أدمن تجربة (DEV)", claims: { role: "super_admin" }, adminDoc: true },
  ];
  return { companies, chains, branches, products, gifts, events, drafts, users };
}

/** Throws if the data set contains anything that looks real (guards future edits). */
function assertFakeOnly(data) {
  const text = JSON.stringify(data);
  const phones = text.match(/01[0125]\d{8}/g) || [];
  for (const p of phones) if (!/^010000000\d\d$/.test(p)) throw new Error(`real-looking phone ${p}`);
  const emails = text.match(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g) || [];
  for (const e of emails) if (!e.endsWith("@example.com")) throw new Error(`non-example e-mail ${e}`);
  for (const p of data.products) if (!p.barcode.startsWith("999")) throw new Error(`real-looking barcode ${p.barcode}`);
  if (/tashil-gift\.(web\.app|firebasestorage\.app)|\/projects\/tashil-gift\//.test(text)) throw new Error("data references production");
  return true;
}

module.exports = { DEV_PROJECT_ID, PROD_PROJECT_ID, SeedRefused, resolveSeedTarget, buildSeedData, assertFakeOnly, argValue };
