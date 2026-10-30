const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");
const { deterministicDocId, normalizeReceiptNumber, isTransactionClaimed, isAdminCaller, redeemedSummary, LOCKED_MESSAGE_AR } = require("./receipt_duplicate_check");

/**
 * replaceReceipt (callable, Admin SDK, 2.0.149): a rep re-uploads a receipt
 * whose deterministic doc rcpt_{campaignId}_{receiptNo} already exists.
 *
 * - Existing doc rejected and never claimed -> "reupload": the doc is
 *   overwritten with the new scan; the rep continues to the normal game/claim.
 * - Existing doc accepted, or any claim evidence -> "replace": the new scan
 *   fields overwrite the doc but every claim/prize/WhatsApp/customer field is
 *   kept from the old version; no new game, no stock movement, no WhatsApp.
 * In both cases the previous version is copied to .../history/{autoId} first.
 * 2.0.152: "replace" is disabled for every role; any caller gets
 * failed-precondition {locked:true, summary} and nothing is written.
 * Nothing is deleted. Firestore rules are unchanged (Admin SDK).
 */
const PRESERVE_ON_REPLACE = [
  "timestamp", "submittedByUid", "customerPhone", "customerName",
  "game_played", "prize_won", "claim_status", "claimed_gifts", "linked_gifts",
  "claim_stock_sources", "claimed_at", "whatsapp_winner", "chances_earned",
  "status", "is_valid", "rejection_reason", "campaignId", "companySlug",
  "bundle_group_id", "is_multi_campaign_bundle", "handed_over_at", "handed_over_by",
];
const SERVER_ONLY = new Set([
  ...PRESERVE_ON_REPLACE, "history", "replace_count", "replaced_at",
  "last_replaced_by_uid", "last_replace_mode",
]);

function hasClaimEvidence(d) {
  if (!d) return false;
  const claim = String(d.claim_status || "").trim();
  const prize = d.prize_won == null ? "" : String(d.prize_won).trim();
  return d.game_played === true || claim !== ""
    || (prize !== "" && prize !== "null")
    || (Array.isArray(d.claimed_gifts) && d.claimed_gifts.length > 0)
    || (Array.isArray(d.claim_stock_sources) && d.claim_stock_sources.length > 0)
    || (d.whatsapp_winner && typeof d.whatsapp_winner === "object")
    || isTransactionClaimed({ ...d, status: "accepted", is_valid: true });
}

function modeFor(old) {
  const rejected = old.status === "rejected" || old.is_valid === false;
  return rejected && !hasClaimEvidence(old) ? "reupload" : "replace";
}

function bounded(v, max) {
  return typeof v === "string" && v.length > 0 && v.length <= max;
}

function validatePayload(p) {
  if (!p || typeof p !== "object" || Array.isArray(p)) return "data";
  const keys = Object.keys(p);
  if (keys.length > 80 || keys.length < 4) return "keys";
  if (p.receipt_number != null && !bounded(String(p.receipt_number), 80)) return "receipt_number";
  if (p.customerPhone != null && String(p.customerPhone).length > 32) return "customerPhone";
  if (p.customerName != null && String(p.customerName).length > 160) return "customerName";
  if (p.total_value != null && !(typeof p.total_value === "number" && p.total_value >= 0 && p.total_value < 1e9)) return "total_value";
  if (p.extracted_products != null && !(Array.isArray(p.extracted_products) && p.extracted_products.length <= 80)) return "extracted_products";
  if (JSON.stringify(p).length > 200000) return "size";
  return null;
}

/** Pure merge used by the handler (exported for tests). */
function buildNewDoc(old, payload, mode, uid) {
  const clean = {};
  for (const [k, v] of Object.entries(payload)) {
    if (mode === "replace" && SERVER_ONLY.has(k)) continue;
    if (mode === "reupload" && (k === "history" || k.startsWith("replace"))) continue;
    clean[k] = v;
  }
  const out = mode === "replace" ? { ...old, ...clean } : { ...clean };
  if (mode === "replace") {
    for (const k of PRESERVE_ON_REPLACE) {
      if (k in old) out[k] = old[k]; else delete out[k];
    }
  } else {
    out.campaignId = old.campaignId;
    out.companySlug = old.companySlug;
    out.submittedByUid = uid;
    out.status = "accepted";
    out.is_valid = true;
    out.rejection_reason = null;
    out.game_played = false;
    out.prize_won = null;
    if (old.whatsapp_winner) out.whatsapp_winner = old.whatsapp_winner;
    out.previous_rejection_reason = old.rejection_reason == null ? null : String(old.rejection_reason).slice(0, 500);
  }
  out.replace_count = (Number(old.replace_count) || 0) + 1;
  out.last_replaced_by_uid = uid;
  out.last_replace_mode = mode;
  return out;
}

async function replaceReceiptHandler(db, request) {
  if (!request.app) throw new HttpsError("failed-precondition", "App Check token is required.");
  if (!request.auth || !request.auth.uid) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const token = request.auth.token || {};
  const provider = token.firebase && token.firebase.sign_in_provider;
  const isAnon = provider === "anonymous";
  const role = token.role;
  const isAdmin = isAdminCaller(request.auth);
  const isPartnerOps = !isAnon && role === "partner" && token.partnerAccess === "ops";
  const data = request.data || {};
  const campaignId = data.campaignId;
  const receiptNumber = normalizeReceiptNumber(data.receiptNumber);
  if (!bounded(campaignId, 128) || !receiptNumber || receiptNumber.length > 80) {
    throw new HttpsError("invalid-argument", "Invalid receipt.");
  }
  const bad = validatePayload(data.receipt);
  if (bad) throw new HttpsError("invalid-argument", `Invalid receipt field: ${bad}`);
  if (normalizeReceiptNumber(data.receipt.receipt_number) !== receiptNumber) {
    throw new HttpsError("invalid-argument", "Receipt number mismatch.");
  }
  try {
    await consumeRateLimit({ db, scope: "receiptCheck", key: clientKey({ uid: request.auth.uid, rawRequest: request.rawRequest }) });
  } catch (err) {
    if (err instanceof RateLimitError) throw new HttpsError("resource-exhausted", err.message);
    throw new HttpsError("unavailable", "Rate limit check unavailable.");
  }
  const evSnap = await db.collection("events").doc(campaignId).get();
  const ev = evSnap.exists ? evSnap.data() || {} : null;
  if (!ev || ev.isActive !== true || ev.isPromoterActive === false) {
    throw new HttpsError("failed-precondition", "Campaign is not active.");
  }
  if (data.receipt.companySlug !== ev.companySlug || data.receipt.campaignId !== campaignId) {
    throw new HttpsError("permission-denied", "Campaign/company mismatch.");
  }
  if (!isAnon && !(isPartnerOps && token.companySlug === ev.companySlug) && !isAdmin) {
    throw new HttpsError("permission-denied", "Not allowed.");
  }
  const ref = db.collection("receipts_transactions").doc(deterministicDocId(campaignId, receiptNumber));
  const uid = request.auth.uid;
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { replaced: false, mode: "create", receiptId: ref.id };
    const old = snap.data() || {};
    if (old.companySlug !== ev.companySlug || old.campaignId !== campaignId) {
      throw new HttpsError("permission-denied", "Receipt belongs to another campaign.");
    }
    const mode = modeFor(old);
    // 2.0.152: approved receipts are locked for everyone (admins included).
    if (mode === "replace") {
      const summary = await redeemedSummary(db, old, new Map([[campaignId, ev]]));
      throw new HttpsError("failed-precondition", LOCKED_MESSAGE_AR, { locked: true, receiptNumber, summary });
    }
    const histRef = ref.collection("history").doc();
    tx.set(histRef, { ...old, archived_at: FieldValue.serverTimestamp(), archived_by_uid: uid, archive_reason: mode, archived_version: (Number(old.replace_count) || 0) + 1 });
    const next = buildNewDoc(old, data.receipt, mode, uid);
    next.replaced_at = FieldValue.serverTimestamp();
    if (mode === "reupload") next.timestamp = FieldValue.serverTimestamp();
    tx.set(ref, next);
    return { replaced: true, mode, receiptId: ref.id, historyId: histRef.id };
  });
}

module.exports = { replaceReceiptHandler, buildNewDoc, modeFor, hasClaimEvidence, validatePayload, PRESERVE_ON_REPLACE };
