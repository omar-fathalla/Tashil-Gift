const { HttpsError } = require("firebase-functions/v2/https");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");

/**
 * Server-side receipt duplicate check (Admin SDK). Clients (anonymous reps)
 * cannot read other users' receipts under firestore.rules, so the cross-user
 * lookup happens here. Mirrors ReceiptDeduplicationHelper (Dart):
 * deterministic id rcpt_{campaignId}_{sanitizedReceipt} plus receipt_number
 * query. Returns only {duplicate, existingStatus} - never other users' data.
 */
const UNSAFE = /[/\\?%*:|"<>\s]/g;

function normalizeReceiptNumber(raw) {
  return String(raw == null ? "" : raw).trim().replace(/\s+/g, "");
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
  if (eventId) {
    const ev = await db.collection("events").doc(eventId).get();
    if (!ev.exists || (ev.data() || {}).companySlug !== companySlug) {
      throw new HttpsError("permission-denied", "Campaign/company mismatch.");
    }
  }

  let existingStatus = null;
  if (campaignId) {
    const direct = await db.collection("receipts_transactions")
      .doc(deterministicDocId(campaignId, receiptNumber)).get();
    if (direct.exists) {
      const d = direct.data();
      existingStatus = statusOf(d);
      if (isTransactionClaimed(d)) return { duplicate: true, existingStatus: "claimed" };
    }
  }

  const snap = await db.collection("receipts_transactions")
    .where("receipt_number", "==", receiptNumber).limit(10).get();
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (!isTransactionClaimed(d)) continue;
    const isBundle = d.is_multi_campaign_bundle === true || d.bundle_group_id != null;
    if (isMultiScan && (d.companySlug === companySlug || isBundle)) {
      return { duplicate: true, existingStatus: "claimed" };
    }
    if (campaignId && (d.campaignId === campaignId || (isBundle && d.companySlug === companySlug))) {
      return { duplicate: true, existingStatus: "claimed" };
    }
  }
  return { duplicate: false, existingStatus };
}

module.exports = {
  checkReceiptDuplicateHandler,
  deterministicDocId,
  isTransactionClaimed,
  normalizeReceiptNumber,
};
