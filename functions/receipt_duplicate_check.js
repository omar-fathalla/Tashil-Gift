const { HttpsError } = require("firebase-functions/v2/https");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");

/**
 * Server-side receipt duplicate check (Admin SDK). Clients (anonymous reps)
 * cannot read other users' receipts under firestore.rules, so the cross-user
 * lookup happens here. Mirrors ReceiptDeduplicationHelper (Dart):
 * deterministic id rcpt_{campaignId}_{sanitizedReceipt} plus receipt_number
 * query, then every component of a combined " + " upload against single
 * receipts and earlier combined receipts. Returns only {duplicate,
 * existingStatus} - never other users' data.
 */
const UNSAFE = /[/\\?%*:|"<>\s]/g;

function normalizeReceiptNumber(raw) {
  return String(raw == null ? "" : raw).trim().replace(/\s+/g, "");
}

const MAX_COMPONENTS = 10;
const LEGACY_COMBINED_SCAN_LIMIT = 300;

/**
 * Physical receipt numbers inside one upload. Combined uploads
 * (allowComplementaryReceipts) store them joined with " + ".
 */
function componentReceiptNumbers(raw) {
  const out = [];
  for (const part of normalizeReceiptNumber(raw).split("+")) {
    if (part && !out.includes(part)) out.push(part);
  }
  return out.slice(0, MAX_COMPONENTS);
}

/** Stored components; records without the array split their joined receipt_number. */
function storedComponents(d) {
  const arr = d && d.component_receipt_numbers;
  if (Array.isArray(arr) && arr.length) {
    const out = [];
    for (const v of arr) {
      const n = normalizeReceiptNumber(v);
      if (n && !out.includes(n)) out.push(n);
    }
    if (out.length) return out;
  }
  return componentReceiptNumbers(d && d.receipt_number);
}

function sharedComponent(components, d) {
  const existing = storedComponents(d);
  return components.find((c) => existing.includes(c)) || null;
}

function deterministicDocId(campaignId, receiptNumber) {
  const clean = normalizeReceiptNumber(receiptNumber);
  const safe = clean ? clean.replace(UNSAFE, "_") : "UNKNOWN";
  return `rcpt_${String(campaignId).trim().replace(UNSAFE, "_")}_${safe}`;
}

function isTransactionClaimed(d) {
  if (!d) return false;
  if (d.status === "rejected" || d.is_valid === false) return false;
  const claim = String(d.claim_status || "").toLowerCase();
  const handed = claim === "handed_over";
  const prize = d.prize_won == null ? "" : String(d.prize_won).trim();
  const hasPrize = prize !== "" && prize !== "null";
  const hasClaimed = Array.isArray(d.claimed_gifts) && d.claimed_gifts.length > 0;
  const hasLinked = Array.isArray(d.linked_gifts) && d.linked_gifts.length > 0 && handed;
  return d.game_played === true || handed || hasPrize || hasClaimed || hasLinked;
}

/** Accepted/stored (or gift claimed) receipts may not be re-used; rejected ones may be re-uploaded. */
function isRedeemed(d) {
  if (!d) return false;
  if (d.status === "rejected" || d.is_valid === false) return false;
  return d.status === "accepted" || d.is_valid === true || isTransactionClaimed(d);
}

function toIso(v) {
  if (!v) return null;
  if (typeof v.toDate === "function") return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  if (typeof v === "string") return v.slice(0, 40);
  return null;
}

function str(v, max) {
  if (v == null) return null;
  const s = String(v).trim();
  return s && s !== "null" ? s.slice(0, max) : null;
}

/** Gift/voucher label for a redeemed receipt (no personal data). */
function giftLabel(d, ev) {
  const direct = str(d.prize_won, 120) || str(d.matched_reward_value, 120);
  if (direct) return direct;
  const rules = Array.isArray(ev && ev.promotionalRules) ? ev.promotionalRules : [];
  let rule = null;
  if (d.matched_rule_id) rule = rules.find((r) => r && r.id === d.matched_rule_id) || null;
  if (!rule) {
    // Older docs: highest spend tier reached by the stored company total.
    const total = Number(d.target_company_total != null ? d.target_company_total : d.total_value) || 0;
    rules.filter((r) => r && r.conditionType !== "by_quantity" && Number(r.minSpend) > 0)
      .forEach((r) => {
        const need = Number(r.minSpend) - (Number(r.discountTolerance) || 0);
        if (total >= need && (!rule || Number(r.minSpend) > Number(rule.minSpend))) rule = r;
      });
  }
  if (!rule) return null;
  const amount = Number(rule.rewardAmount) || 0;
  return str(rule.rewardValue, 120) || str(rule.linkedGiftName, 120)
    || (amount > 0 ? `${amount}` : null) || str(rule.ruleTitle, 120);
}

async function redeemedSummary(db, d, cache) {
  let ev = null;
  if (d.campaignId) {
    if (!cache.has(d.campaignId)) {
      const s = await db.collection("events").doc(String(d.campaignId)).get();
      cache.set(d.campaignId, s.exists ? s.data() : null);
    }
    ev = cache.get(d.campaignId);
  }
  return {
    redeemedAt: toIso(d.claimed_at) || toIso(d.timestamp),
    campaignName: str(ev && ev.eventName, 120) || str(d.targetCompany, 120),
    giftValue: giftLabel(d, ev),
    branch: str(d.branch_detected, 120),
    receiptDate: str(d.receipt_date, 40),
    uploadedAt: toIso(d.timestamp),
    status: statusOf(d),
    approvedAt: toIso(d.approved_at) || toIso(d.timestamp),
    total: totalOf(d),
  };
}

function totalOf(d) {
  const v = d.target_company_total != null ? d.target_company_total : d.total_value;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

/** 2.0.152: only admin/super_admin (server-verified custom claim, non-anonymous) may replace an approved receipt. */
function isAdminCaller(auth) {
  const token = (auth && auth.token) || {};
  const provider = token.firebase && token.firebase.sign_in_provider;
  if (provider === "anonymous") return false;
  return token.role === "admin" || token.role === "super_admin";
}

/** Approved (or ever claimed) receipts are locked for normal uploads. */
function isLockedForUpload(d) {
  if (!d) return false;
  const rejected = d.status === "rejected" || d.is_valid === false;
  if (!rejected) return isRedeemed(d);
  return d.game_played === true || String(d.claim_status || "").trim() !== ""
    || (d.prize_won != null && String(d.prize_won).trim() !== "" && String(d.prize_won).trim() !== "null")
    || (Array.isArray(d.claimed_gifts) && d.claimed_gifts.length > 0);
}

const LOCKED_MESSAGE_AR = "الفاتورة دي اتعمدت قبل كده";

function statusOf(d) {
  if (!d) return null;
  if (isTransactionClaimed(d)) return "claimed";
  if (d.status === "rejected" || d.is_valid === false) return "rejected";
  return typeof d.status === "string" ? d.status.slice(0, 32) : "pending";
}

function boundedString(v, max) {
  return typeof v === "string" && v.length > 0 && v.length <= max;
}

async function checkReceiptDuplicateHandler(db, request) {
  if (!request.app) {
    throw new HttpsError("failed-precondition", "App Check token is required.");
  }
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const data = request.data || {};
  const receiptNumber = normalizeReceiptNumber(data.receiptNumber);
  const companySlug = data.companySlug;
  const campaignId = data.campaignId == null || data.campaignId === "" ? null : data.campaignId;
  const isMultiScan = data.isMultiScan === true;
  if (!receiptNumber) return { duplicate: false, existingStatus: null };
  if (receiptNumber.length > 80 || !boundedString(companySlug, 128)
      || (campaignId !== null && !boundedString(campaignId, 128))) {
    throw new HttpsError("invalid-argument", "Invalid receipt check arguments.");
  }

  try {
    await consumeRateLimit({
      db,
      scope: "receiptCheck",
      key: clientKey({ uid: request.auth.uid, rawRequest: request.rawRequest }),
    });
  } catch (err) {
    if (err instanceof RateLimitError) throw new HttpsError("resource-exhausted", err.message);
    throw new HttpsError("unavailable", "Rate limit check unavailable.");
  }

  // Campaign must exist and belong to the claimed company (no probing other companies).
  const eventId = campaignId;
  let eventData = null;
  if (eventId) {
    const ev = await db.collection("events").doc(eventId).get();
    eventData = ev.exists ? (ev.data() || {}) : null;
    if (!eventData || eventData.companySlug !== companySlug) {
      throw new HttpsError("permission-denied", "Campaign/company mismatch.");
    }
  }

  let existingStatus = null;
  const evCache = new Map();
  // 2.0.152: approved receipts are locked for everyone, admins included.
  const hit = async (d) => ({
    duplicate: true,
    locked: isLockedForUpload(d),
    ...(isLockedForUpload(d) ? { message: LOCKED_MESSAGE_AR } : {}),
    existingStatus: statusOf(d),
    summary: await redeemedSummary(db, d, evCache),
  });
  if (campaignId) {
    const direct = await db.collection("receipts_transactions")
      .doc(deterministicDocId(campaignId, receiptNumber)).get();
    if (direct.exists) {
      const d = direct.data();
      existingStatus = statusOf(d);
      // 2.0.147: any doc at the exact id blocks the rep's create under the
      // rules (create-only), so report it as already uploaded whatever its status.
      if (isRedeemed(d) || isLockedForUpload(d) || data.exactDocId === true) return { ...(await hit(d)), exactDocExists: true };
    }
  }

  const inScope = (d) => {
    const isBundle = d.is_multi_campaign_bundle === true || d.bundle_group_id != null;
    if (isMultiScan && (d.companySlug === companySlug || isBundle)) return true;
    return !!campaignId && (d.campaignId === campaignId || (isBundle && d.companySlug === companySlug));
  };
  const firstHit = async (docs, components) => {
    for (const doc of docs) {
      const d = doc.data() || {};
      if (!isRedeemed(d) || !inScope(d)) continue;
      if (components && !sharedComponent(components, d)) continue;
      return hit(d);
    }
    return null;
  };
  const receipts = db.collection("receipts_transactions");

  const snap = await receipts.where("receipt_number", "==", receiptNumber).limit(20).get();
  const exact = await firstHit(snap.docs, null);
  if (exact) return exact;

  // Each physical receipt of a combined upload may be used once, whether it
  // was stored alone or as part of an earlier combined upload.
  const components = componentReceiptNumbers(receiptNumber);
  if (components.length > 1) {
    const singles = await receipts.where("receipt_number", "in", components).limit(20).get();
    const single = await firstHit(singles.docs, components);
    if (single) return single;
  }
  const tagged = await receipts
    .where("component_receipt_numbers", "array-contains-any", components).limit(20).get();
  const taggedHit = await firstHit(tagged.docs, components);
  if (taggedHit) return taggedHit;

  // Combined receipts saved before component_receipt_numbers existed only
  // carry the joined string; they can exist only where combining is allowed.
  if (isMultiScan || (eventData && eventData.allowComplementaryReceipts === true)) {
    const legacy = await receipts
      .where("companySlug", "==", companySlug)
      .where("parts_count", ">", 1)
      .limit(LEGACY_COMBINED_SCAN_LIMIT).get();
    const legacyDocs = legacy.docs.filter((doc) => {
      const d = doc.data() || {};
      const hasArray = Array.isArray(d.component_receipt_numbers) && d.component_receipt_numbers.length > 0;
      return !hasArray && String(d.receipt_number || "").includes("+");
    });
    const legacyHit = await firstHit(legacyDocs, components);
    if (legacyHit) return legacyHit;
  }
  return { duplicate: false, existingStatus };
}

module.exports = {
  checkReceiptDuplicateHandler,
  deterministicDocId,
  isTransactionClaimed,
  isRedeemed,
  giftLabel,
  normalizeReceiptNumber,
  componentReceiptNumbers,
  storedComponents,
  sharedComponent,
  isAdminCaller,
  isLockedForUpload,
  redeemedSummary,
  LOCKED_MESSAGE_AR,
};
