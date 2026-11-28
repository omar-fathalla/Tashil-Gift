/**
 * C-05 "try with receipt": evaluates receipt data against a campaign with the
 * same pure eligibility check decrementCampaignPrize runs before any stock is
 * touched (evaluateClaimEligibility). Staff only. It NEVER writes: no stock,
 * no claim, no receipt. The only Firestore access is an optional read of an
 * existing receipt (receiptId) or campaign (eventId).
 */
const { HttpsError } = require("firebase-functions/v2/https");
const { evaluateClaimEligibility } = require("./campaign_eligibility");
const { withCampaignContent, CampaignContentUnavailable } = require("./campaign_content");

const STAFF_ROLES = new Set(["super_admin", "admin"]);
const MAX_LINES = 200;
const MAX_PAYLOAD_CHARS = 300000;
const LINE_KEYS = ["name", "barcode", "price", "quantity", "isTargetCompany", "discountAmount", "originalPrice"];

function assertStaff(auth) {
  const provider = auth && auth.token && auth.token.firebase && auth.token.firebase.sign_in_provider;
  const role = auth && auth.token ? auth.token.role : null;
  if (!auth || provider === "anonymous" || !STAFF_ROLES.has(role)) {
    throw new HttpsError("permission-denied", "تجربة الحملة على فاتورة متاحة للإدارة فقط.");
  }
}

function plainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function cleanLine(line) {
  const out = {};
  for (const key of LINE_KEYS) {
    if (line[key] === undefined || line[key] === null) continue;
    if (key === "name" || key === "barcode") out[key] = String(line[key]).slice(0, 300);
    else if (key === "isTargetCompany") out[key] = line[key] === true;
    else if (Number.isFinite(Number(line[key]))) out[key] = Number(line[key]);
  }
  return out;
}

/** Receipt fields the eligibility check reads, from client input. */
function receiptFromInput(input, nowMs) {
  const lines = Array.isArray(input.extracted_products) ? input.extracted_products : [];
  if (lines.length > MAX_LINES) {
    throw new HttpsError("invalid-argument", `عدد الأصناف أكبر من ${MAX_LINES}.`);
  }
  const ts = Number(input.timestamp);
  return {
    receipt_date: input.receipt_date == null ? null : String(input.receipt_date).slice(0, 40),
    timestamp: Number.isFinite(ts) && ts > 0 ? ts : nowMs,
    extracted_products: lines.filter(plainObject).map(cleanLine),
  };
}

/**
 * @param {object} db  Firestore (only .collection().doc().get() is used)
 * @param {{auth: object, data: object}} request
 */
async function dryRunCampaignEligibilityHandler(db, request, nowMs = Date.now()) {
  assertStaff(request.auth);
  const data = request.data || {};
  if (JSON.stringify(data).length > MAX_PAYLOAD_CHARS) {
    throw new HttpsError("invalid-argument", "بيانات التجربة كبيرة جدًا.");
  }

  let campaign;
  try {
    if (plainObject(data.campaign)) {
      campaign = data.campaign;
      // TAG-62: a large product list is not sent; use the stored one.
      const contentEventId = typeof data.contentEventId === "string" ? data.contentEventId.trim() : "";
      if (contentEventId && !Array.isArray(campaign.requiredProducts)) {
        const snap = await db.collection("events").doc(contentEventId).get();
        if (!snap.exists) throw new HttpsError("not-found", "الحملة غير موجودة.");
        const stored = await withCampaignContent(db, contentEventId, snap.data() || {}, { prompt: false });
        campaign = Object.assign({}, campaign, { requiredProducts: stored.requiredProducts || [] });
      }
    } else if (typeof data.eventId === "string" && data.eventId.trim()) {
      const eventId = data.eventId.trim();
      const snap = await db.collection("events").doc(eventId).get();
      if (!snap.exists) throw new HttpsError("not-found", "الحملة غير موجودة.");
      campaign = await withCampaignContent(db, eventId, snap.data() || {}, { prompt: false });
    } else {
      throw new HttpsError("invalid-argument", "لازم تبعت بيانات الحملة.");
    }
  } catch (e) {
    if (e instanceof CampaignContentUnavailable) {
      throw new HttpsError("failed-precondition", "تعذر قراءة منتجات الحملة المحفوظة.");
    }
    throw e;
  }

  let receipt;
  let receiptSource = "input";
  if (typeof data.receiptId === "string" && data.receiptId.trim()) {
    const snap = await db.collection("receipts_transactions").doc(data.receiptId.trim()).get();
    if (!snap.exists) throw new HttpsError("not-found", "الفاتورة غير موجودة.");
    const stored = snap.data() || {};
    receipt = { receipt_date: stored.receipt_date, timestamp: stored.timestamp, extracted_products: stored.extracted_products };
    receiptSource = "stored";
  } else if (plainObject(data.receipt)) {
    receipt = receiptFromInput(data.receipt, nowMs);
  } else {
    throw new HttpsError("invalid-argument", "لازم تبعت بيانات الفاتورة.");
  }

  // The admin tests the conditions as if the campaign were live; whether it is
  // live today is reported separately.
  const campaignActive = campaign.isActive === true;
  const event = Object.assign({}, campaign, { isActive: true });
  const verdict = evaluateClaimEligibility({ event, receipt, nowMs, system: false });
  const mode = event.spendLadderMode === "consuming" ? "consuming" : "exclusive";
  return {
    dryRun: true,
    ok: verdict.ok === true,
    code: verdict.ok ? null : verdict.code,
    message: verdict.ok ? null : verdict.message,
    details: verdict.ok ? {} : verdict.details || {},
    serverUnits: verdict.ok ? verdict.serverUnits : null,
    mode,
    campaignActive,
    receiptSource,
    lineCount: Array.isArray(receipt.extracted_products) ? receipt.extracted_products.length : 0,
  };
}

module.exports = { dryRunCampaignEligibilityHandler, _testing: { receiptFromInput, cleanLine, assertStaff } };
