const { HttpsError } = require("firebase-functions/v2/https");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");

/**
 * listBranchReceipts (callable, Admin SDK): a field rep's branch history for
 * one campaign, independent of the anonymous uid (which changes with a new
 * device, private tab or cleared storage). Firestore rules are unchanged:
 * anonymous clients still only read their own docs; this returns a minimal,
 * non-personal projection (no images, no customer name, masked phone).
 *
 * Access: App Check + signed-in caller, campaign must be active and open to
 * promoters, and the branch must be one of the campaign's branches.
 */
const MAX_RESULTS = 300;
const QUERY_LIMIT = 500;

function str(v, max) {
  if (v == null) return null;
  const s = String(v).trim();
  return s && s !== "null" ? s.slice(0, max) : null;
}

function toIso(v) {
  if (!v) return null;
  if (typeof v.toDate === "function") return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  return null;
}

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function maskPhone(v) {
  const s = String(v == null ? "" : v).replace(/\D/g, "");
  if (s.length < 4) return null;
  return `${"*".repeat(Math.max(0, s.length - 3))}${s.slice(-3)}`;
}

function normBranch(s) {
  return String(s == null ? "" : s).trim().toLowerCase();
}

/** Resolves {branchId, branchName} against the event's own branch list. */
function resolveEventBranch(ev, branchName, branchId) {
  const names = Array.isArray(ev.branchNames) ? ev.branchNames.map((b) => String(b || "").trim()) : [];
  const ids = Array.isArray(ev.branchIds) ? ev.branchIds.map((b) => String(b || "").trim()) : [];
  let idx = -1;
  if (branchName) idx = names.findIndex((n) => normBranch(n) === normBranch(branchName));
  if (idx < 0 && branchId) idx = ids.findIndex((i) => normBranch(i) === normBranch(branchId));
  const allBranches = ev.isAllBranches === true || (names.length === 0 && ids.length === 0);
  if (idx < 0 && !allBranches) return null;
  const name = idx >= 0 && names[idx] ? names[idx] : (branchName || null);
  const id = (idx >= 0 && names.length === ids.length && ids[idx]) ? ids[idx] : (branchId || null);
  if (!name && !id) return null;
  return { branchName: name, branchId: id };
}

function projectReceipt(id, d, callerUid) {
  const unfulfilled = Array.isArray(d.unfulfilled_conditions)
    ? d.unfulfilled_conditions.slice(0, 5).map((c) => str(c, 200)).filter(Boolean) : [];
  return {
    id,
    campaignId: str(d.campaignId, 128),
    companySlug: str(d.companySlug, 128),
    receipt_number: str(d.receipt_number, 80),
    receipt_date: str(d.receipt_date, 40),
    timestamp: toIso(d.timestamp),
    branch_detected: str(d.branch_detected, 160),
    branch_id: str(d.branch_id, 128),
    store_chain_detected: str(d.store_chain_detected, 160),
    status: str(d.status, 32),
    is_valid: d.is_valid === true ? true : (d.is_valid === false ? false : null),
    claim_status: str(d.claim_status, 32),
    game_played: d.game_played === true,
    target_company_total: num(d.target_company_total),
    total_value: num(d.total_value),
    matched_reward_value: str(d.matched_reward_value, 160),
    prize_won: str(d.prize_won, 160),
    rejection_reason: str(d.rejection_reason, 300),
    unfulfilled_conditions: unfulfilled,
    customer_phone_masked: maskPhone(d.customerPhone),
    same_session: !!callerUid && d.submittedByUid === callerUid,
  };
}

async function listBranchReceiptsHandler(db, request) {
  if (!request.app) {
    throw new HttpsError("failed-precondition", "App Check token is required.");
  }
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const data = request.data || {};
  const campaignId = typeof data.campaignId === "string" ? data.campaignId.trim() : "";
  const branchName = typeof data.branchName === "string" ? data.branchName.trim() : "";
  const branchId = typeof data.branchId === "string" ? data.branchId.trim() : "";
  if (!campaignId || campaignId.length > 128 || branchName.length > 200 || branchId.length > 128
      || (!branchName && !branchId)) {
    throw new HttpsError("invalid-argument", "campaignId and branch are required.");
  }

  try {
    await consumeRateLimit({
      db,
      scope: "branchReceipts",
      key: clientKey({ uid: request.auth.uid, rawRequest: request.rawRequest }),
    });
  } catch (err) {
    if (err instanceof RateLimitError) throw new HttpsError("resource-exhausted", err.message);
    throw new HttpsError("unavailable", "Rate limit check unavailable.");
  }

  const evSnap = await db.collection("events").doc(campaignId).get();
  if (!evSnap.exists) throw new HttpsError("not-found", "Campaign not found.");
  const ev = evSnap.data() || {};
  const promoterOpen = ev.isActive === true && ev.isPromoterActive !== false;
  if (!promoterOpen) throw new HttpsError("permission-denied", "Campaign is not open to reps.");

  const branch = resolveEventBranch(ev, branchName, branchId);
  if (!branch) throw new HttpsError("permission-denied", "Branch is not part of this campaign.");

  const col = db.collection("receipts_transactions");
  const queries = [];
  if (branch.branchId) {
    queries.push(col.where("campaignId", "==", campaignId)
      .where("branch_id", "==", branch.branchId).limit(QUERY_LIMIT).get());
  }
  if (branch.branchName) {
    queries.push(col.where("campaignId", "==", campaignId)
      .where("branch_detected", "==", branch.branchName).limit(QUERY_LIMIT).get());
  }
  const snaps = await Promise.all(queries);
  const byId = new Map();
  for (const s of snaps) {
    for (const doc of s.docs) {
      if (!byId.has(doc.id)) byId.set(doc.id, projectReceipt(doc.id, doc.data() || {}, request.auth.uid));
    }
  }
  const receipts = [...byId.values()]
    .sort((a, b) => String(b.timestamp || "").localeCompare(String(a.timestamp || "")))
    .slice(0, MAX_RESULTS);
  return {
    branchName: branch.branchName,
    branchId: branch.branchId,
    receipts,
    otherSessionCount: receipts.filter((r) => !r.same_session).length,
  };
}

module.exports = { listBranchReceiptsHandler, resolveEventBranch, projectReceipt, maskPhone };
