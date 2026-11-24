/**
 * Auth claims and server-side gift stock mutations.
 *
 * setUserRole: super_admin only. Grants or clears role claims.
 * decrementCampaignPrize: staff, partner ops, or the anonymous receipt owner.
 * Inventory remainingQuantity is changed here with the Admin SDK so clients
 * cannot write stock counters directly.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { planConsumingClaim } = require("./consuming_spend_ladder");
const { exclusiveLadderUnits } = require("./exclusive_spend_ladder");
const { evaluateClaimEligibility, ELIGIBILITY_REASONS, REASONS } = require("./campaign_eligibility");
const admin = require("./admin_sdk");

const callableOptions = {
  region: "us-central1",
  memory: "256MiB",
  enforceAppCheck: true,
};

const ALLOWED_ROLES = new Set(["super_admin", "admin", "partner"]);
const CLAIM_PATCH_KEYS = new Set([
  "game_played",
  "game_type",
  "prize_won",
  "prizes_won",
  "claimed_gifts",
  "voucher_serials",
  "voucher_serial",
  "event_id",
  "branch_id",
  "remaining_chances",
  "claim_status",
  "claimed_at",
  "matched_reward_value",
  "linked_gifts",
  "unit_value",
  "is_voucher",
  "chosen_reward_option",
  "chosen_reward_options",
  "handed_over_confirmed",
]);

// 2.0.163: claiming is automatic; the rep's handover tap only confirms. A
// confirm-only patch (no decrements) may touch these keys after the claim.
const CONFIRM_PATCH_KEYS = new Set(["handed_over_confirmed", "voucher_serials", "voucher_serial"]);

// The claim state of a receipt is written only by the claim transaction.
// The client still sends remaining_chances and claimed_gifts; they are taken
// out of the patch and only used as hints (gift labels, an earlier close).
const CLAIM_STATE_KEYS = ["remaining_chances", "claimed_gifts"];
const ALREADY_CLAIMED = "already_claimed";

function assertAppCheck(request) {
  if (!request || request.app == null) {
    throw new HttpsError(
      "failed-precondition",
      "App Check token is required.",
    );
  }
}

function assertSignedIn(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
}

function callerRole(request) {
  return (request.auth && request.auth.token && request.auth.token.role) || "";
}

function isStaffRole(role) {
  return role === "super_admin" || role === "admin";
}

function normalizePrizeText(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/[\u064B-\u065F\u0670]/g, "")
    .replace(/[أإآ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)))
    .replace(/[^\w\s\d\u0600-\u06FF]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extractNumbers(text) {
  const matches = String(text || "").match(/\d+/g) || [];
  return matches.map((n) => parseInt(n, 10)).filter((n) => n > 0);
}

function findBestPrizeMatchIndex(prizes, prizeIdentifier, options) {
  const branchId = options.branchId || "";
  const unitValue = options.unitValue;
  const isVoucher = options.isVoucher;
  if (!Array.isArray(prizes) || !prizeIdentifier || !String(prizeIdentifier).trim()) {
    return -1;
  }
  const cleanTarget = normalizePrizeText(prizeIdentifier);
  const targetNums = extractNumbers(prizeIdentifier);
  const targetVal = typeof unitValue === "number"
    ? unitValue
    : (extractNumbers(prizeIdentifier)[0] || 0);
  let bestIndex = -1;
  let highestScore = -1;

  prizes.forEach((p, i) => {
    const pGiftId = String(p.giftId || "").trim();
    const pName = String(p.name || "").trim();
    const pBranchId = String(p.branchId || "").trim();
    const pBranchName = String(p.branchName || "").trim();
    const pUnitVal = Number(p.unitValue || 0);
    const pType = String(p.giftType || "");
    const cleanPName = normalizePrizeText(pName);
    const nameLower = pName.toLowerCase();
    const pIsVoucher = pType === "voucher" ||
      (pType !== "product" && pUnitVal > 0 && /فواتشر|فوتشر|قسيمة|قسائم|voucher|coupon/i.test(nameLower));
    const pRemaining = Number(p.remainingQuantity || 0);
    let score = 0;

    const branchNorm = normalizePrizeText(branchId);
    const pBranchNorm = normalizePrizeText(pBranchName);
    const isExactBranch = branchId &&
      (pBranchId === branchId ||
        pBranchName === branchId ||
        (branchNorm && pBranchNorm && (pBranchNorm === branchNorm || pBranchNorm.includes(branchNorm))));
    const isGeneralBranch = !pBranchId && !pBranchName;
    if (isExactBranch) score += 120;
    else if (isGeneralBranch) score += 60;
    else if (branchId && (pBranchId || pBranchName)) score -= 80;

    if (pGiftId && (pGiftId === prizeIdentifier || pGiftId === cleanTarget)) score += 200;
    else if (pName === prizeIdentifier) score += 160;

    if (cleanPName && cleanPName === cleanTarget) score += 140;
    else if (cleanTarget && (cleanPName.includes(cleanTarget) || cleanTarget.includes(cleanPName))) score += 95;

    if ((isVoucher === true || pIsVoucher) && targetVal > 0 && pUnitVal > 0 && Math.abs(targetVal - pUnitVal) < 0.01) {
      score += 110;
    }

    const pNums = extractNumbers(pName);
    if (targetNums.length && pNums.some((n) => targetNums.includes(n))) score += 50;
    if (pRemaining > 0) score += 15;

    if (score > highestScore && score > 30) {
      highestScore = score;
      bestIndex = i;
    }
  });

  return bestIndex;
}

/**
 * Picks the stock row for one decrement. When the client sent no branch, the
 * receipt's branch_id / branch_detected is used. If the gift is still held by
 * several branch-specific rows and no general row exists, refuse instead of
 * silently taking the first branch's stock.
 */
/**
 * 2.0.153+214: store code printed in the receipt number (segment before a
 * trailing 6-8 digit date, e.g. Fathalla 145/10/224/301026 -> 224).
 */
function storeCodeFromReceiptNumber(raw) {
  const ar = "٠١٢٣٤٥٦٧٨٩";
  const s = String(raw || "").replace(/[٠-٩]/g, (d) => String(ar.indexOf(d))).trim();
  const segs = s.split(/[\/\-\\\s]+/).filter(Boolean);
  if (segs.length < 3 || !/^\d{6,8}$/.test(segs[segs.length - 1])) return "";
  const code = segs[segs.length - 2];
  return /^\d{1,6}$/.test(code) ? code : "";
}

/** Unique stock-row branch id owning the store code (`<chain>_<code>`), or "". */
function branchIdFromStoreCode(prizes, receipt, extraIds) {
  const rec = receipt || {};
  const code = storeCodeFromReceiptNumber(rec.receipt_number || rec.receiptNumber);
  if (!code) return "";
  const ids = new Set();
  const all = (prizes || []).map((p) => (p && p.branchId)).concat(extraIds || []);
  for (const raw of all) {
    const id = String(raw || "").trim();
    if (id && (id === code || id.endsWith("_" + code))) ids.add(id);
  }
  return ids.size === 1 ? [...ids][0] : "";
}

const NO_BRANCH_STOCK_MESSAGE = "مفيش رصيد للهدية دي في فرع الفاتورة، كلّم المشرف";

function resolvePrizeIndexForDecrement(prizes, decrement, receipt) {
  const rec = receipt || {};
  // Store code in the receipt number wins over client / AI branch hints.
  const codeBranch = branchIdFromStoreCode(prizes, rec);
  let branchId = codeBranch;
  if (!branchId) branchId = String(decrement.branchId || "").trim();
  if (!branchId) branchId = String(rec.branch_id || "").trim();
  if (!branchId) branchId = String(rec.branch_detected || rec.branch || "").trim();
  const options = Object.assign({}, decrement, { branchId });
  const index = findBestPrizeMatchIndex(prizes, decrement.prizeIdentifier, options);
  if (index === -1) return { index, branchId, fromStoreCode: !!codeBranch };
  const picked = prizes[index] || {};
  const pickedBranchKey = String(picked.branchId || picked.branchName || "").trim();
  const sameGift = (p) => {
    const gid = String(p.giftId || "").trim();
    if (gid && gid === String(picked.giftId || "").trim()) return true;
    return !gid && normalizePrizeText(p.name) === normalizePrizeText(picked.name);
  };
  const giftRows = prizes.filter(sameGift);
  const hasGeneral = giftRows.some((p) => !String(p.branchId || p.branchName || "").trim());
  const branchKeys = new Set(giftRows
    .map((p) => String(p.branchId || p.branchName || "").trim())
    .filter(Boolean));
  if (pickedBranchKey && !hasGeneral && branchKeys.size > 1) {
    const branchNorm = normalizePrizeText(branchId);
    const pickedIsBranch = branchId && (
      String(picked.branchId || "").trim() === branchId ||
      String(picked.branchName || "").trim() === branchId ||
      (branchNorm && normalizePrizeText(picked.branchName) === branchNorm));
    if (!pickedIsBranch && branchId) {
      // 2.0.154: the receipt branch is known but holds no row for this gift.
      // Not an ambiguity: let the caller try the shared company pool for this
      // exact branch, then report "no stock for this branch".
      return { index: -1, branchId, fromStoreCode: !!codeBranch, noBranchStock: true };
    }
    if (!pickedIsBranch) {
      throw new HttpsError(
        "failed-precondition",
        "تعذر تحديد فرع الفاتورة لخصم الهدية (أكثر من فرع يحمل نفس الهدية). يرجى اختيار الفرع ثم إعادة المحاولة.",
      );
    }
  }
  return { index, branchId, fromStoreCode: !!codeBranch };
}

const VOUCHER_NAME_RE = /فواتشر|فوتشر|فاوتشر|قسيمة|قسائم|voucher|coupon/i;

function branchLabelOf(row, fallback) {
  const r = row || {};
  return String(r.branchName || r.branchId || fallback || "").trim() || "عام";
}

/** Face value a stock row represents (unitValue, else the number in a voucher name). */
function rowVoucherValue(row) {
  const r = row || {};
  const v = Number(r.unitValue || 0);
  if (v > 0) return v;
  const name = String(r.name || "");
  if (String(r.giftType || "") === "voucher" || VOUCHER_NAME_RE.test(name)) {
    return extractNumbers(normalizePrizeText(name))[0] || 0;
  }
  return 0;
}

/**
 * True when the stock row clearly is a different gift than the ladder option
 * asked for (e.g. tier option "voucher 150" bound to the "voucher 25" giftId).
 * Only voucher face values are compared; a product row is never flagged.
 */
function ladderRowConflicts(row, decrement) {
  const rowVal = rowVoucherValue(row);
  if (!(rowVal > 0)) return false;
  let reqVal = Number(decrement.unitValue || 0);
  if (!(reqVal > 0)) {
    const label = String(decrement.giftName || "");
    if (VOUCHER_NAME_RE.test(label)) reqVal = extractNumbers(normalizePrizeText(label))[0] || 0;
  }
  return reqVal > 0 && Math.abs(reqVal - rowVal) >= 0.01;
}

function misconfiguredError(row, decrement, branchId) {
  const r = row || {};
  const giftName = String(decrement.giftName || decrement.prizeIdentifier || "").trim();
  const reqVal = Number(decrement.unitValue || 0);
  const rowVal = rowVoucherValue(r);
  const branch = branchLabelOf(r, branchId);
  return new HttpsError(
    "failed-precondition",
    `إعداد الحملة غير صحيح: الهدية "${giftName}"${reqVal > 0 ? ` (${reqVal} جنيه)` : ""} مربوطة برصيد "${String(r.name || "").trim()}"${rowVal > 0 ? ` (${rowVal} جنيه)` : ""} في فرع "${branch}". صحّح ربط الهدية في قواعد الحملة ثم أعد المحاولة، ولم يُصرف أي مخزون.`,
    {
      reason: "campaign_misconfigured",
      giftId: String(decrement.prizeIdentifier || ""),
      giftName,
      requestedValue: reqVal,
      stockRowName: String(r.name || ""),
      stockRowValue: rowVal,
      branch,
    },
  );
}

function insufficientStockError(row, decrement, branchId, remaining) {
  const r = row || {};
  const giftName = String(r.name || decrement.giftName || decrement.prizeIdentifier || "").trim();
  const branch = branchLabelOf(r, branchId || decrement.branchId);
  return new HttpsError(
    "failed-precondition",
    `Not enough prize stock remaining for "${giftName}" at branch "${branch}" (stored remaining ${remaining}, requested ${decrement.count}).`,
    { reason: "insufficient_stock", giftName, branch, remaining, requested: decrement.count },
  );
}

/**
 * Stock row for one consuming-ladder decrement. The tier option's giftId is
 * the authority: only rows with that same giftId are candidates, and the row
 * must be the receipt branch's row (or a general, branchless row). Scoring by
 * name / value is never allowed to pick a different gift, and a giftId row
 * whose voucher value contradicts the option is a misconfiguration, not an
 * empty stock. Rows stored without any giftId keep the legacy matcher.
 */
function resolveLadderStockRow(prizes, decrement, receipt) {
  const rec = receipt || {};
  const rows = Array.isArray(prizes) ? prizes : [];
  const gid = String(decrement.prizeIdentifier || "").trim();
  const codeBranch = branchIdFromStoreCode(rows, rec);
  let branchId = codeBranch;
  if (!branchId) branchId = String(decrement.branchId || "").trim();
  if (!branchId) branchId = String(rec.branch_id || "").trim();
  if (!branchId) branchId = String(rec.branch_detected || rec.branch || "").trim();
  const fromStoreCode = !!codeBranch;

  const same = [];
  rows.forEach((p, i) => {
    if (gid && String((p && p.giftId) || "").trim() === gid) same.push(i);
  });
  if (same.length === 0) {
    // No row carries this giftId. Only legacy rows without a giftId may still
    // match by name/value; rows of other gifts are never candidates.
    const legacyIdx = [];
    rows.forEach((p, i) => { if (p && !String(p.giftId || "").trim()) legacyIdx.push(i); });
    if (legacyIdx.length === 0) return { index: -1, branchId, fromStoreCode };
    const res = resolvePrizeIndexForDecrement(legacyIdx.map((i) => rows[i]), decrement, rec);
    if (res.index === -1) return res;
    const index = legacyIdx[res.index];
    if (ladderRowConflicts(rows[index], decrement)) throw misconfiguredError(rows[index], decrement, res.branchId);
    return Object.assign({}, res, { index });
  }

  const branchNorm = normalizePrizeText(branchId);
  const isExact = (p) => !!branchId && (
    String(p.branchId || "").trim() === branchId ||
    String(p.branchName || "").trim() === branchId ||
    (!!branchNorm && normalizePrizeText(p.branchName) === branchNorm));
  const isGeneral = (p) => !String(p.branchId || "").trim() && !String(p.branchName || "").trim();
  // A row whose value agrees with the option wins over a contradicting one,
  // then the row with more stock (duplicate rows of one gift + branch).
  const byStock = (a, b) => (ladderRowConflicts(rows[a], decrement) ? 1 : 0) - (ladderRowConflicts(rows[b], decrement) ? 1 : 0) ||
    Number(rows[b].remainingQuantity || 0) - Number(rows[a].remainingQuantity || 0);

  let index = -1;
  if (branchId) {
    const exact = same.filter((i) => isExact(rows[i])).sort(byStock);
    // Same tolerance the legacy scorer gave branch names ("فرع X (القاهرة)").
    const loose = same.filter((i) => {
      const n = normalizePrizeText(rows[i].branchName);
      return !!branchNorm && !!n && n.includes(branchNorm);
    }).sort(byStock);
    const general = same.filter((i) => isGeneral(rows[i])).sort(byStock);
    if (exact.length) index = exact[0];
    else if (loose.length === 1) index = loose[0];
    else if (general.length) index = general[0];
  } else {
    const general = same.filter((i) => isGeneral(rows[i])).sort(byStock);
    const branchKeys = new Set(same.map((i) => String(rows[i].branchId || rows[i].branchName || "").trim()).filter(Boolean));
    if (general.length) index = general[0];
    else if (branchKeys.size === 1) index = same.slice().sort(byStock)[0];
    else {
      throw new HttpsError(
        "failed-precondition",
        "تعذر تحديد فرع الفاتورة لخصم الهدية (أكثر من فرع يحمل نفس الهدية). يرجى اختيار الفرع ثم إعادة المحاولة.",
      );
    }
  }

  if (index === -1) {
    // The receipt branch has no row of this gift. If the gift's rows elsewhere
    // already contradict the option, say so instead of "no branch stock".
    if (same.every((i) => ladderRowConflicts(rows[i], decrement))) {
      throw misconfiguredError(rows[same[0]], decrement, branchId);
    }
    return { index: -1, branchId, fromStoreCode, noBranchStock: true };
  }
  if (ladderRowConflicts(rows[index], decrement)) {
    throw misconfiguredError(rows[index], decrement, branchId);
  }
  return { index, branchId, fromStoreCode };
}

/**
 * Company-shared stock pool (2.0.148+206).
 * When a campaign has no stock row for a gift, the claim draws from a row of
 * the SAME gift in a sibling active campaign of the SAME company (same
 * events.allocatedPrizes rows the balances screen feeds), so a new campaign
 * shares the company+branch balance. Strict matching only: same giftId (or
 * exact normalized name when the row has no giftId), and the row's branch is
 * the receipt branch or a general (no-branch) row. One row is decremented,
 * so nothing is counted twice. events.balanceMode === "campaign_only" opts
 * a campaign out of the pool.
 */
function sharedPoolEnabled(event) {
  return String((event && event.balanceMode) || "").trim() !== "campaign_only";
}

function findSharedPoolRow(siblings, decrement, branchId) {
  const target = String(decrement.prizeIdentifier || "").trim();
  const targetNorm = normalizePrizeText(target);
  const branch = String(branchId || "").trim();
  const branchNorm = normalizePrizeText(branch);
  let best = null;
  for (const sib of siblings || []) {
    const prizes = Array.isArray(sib.prizes) ? sib.prizes : [];
    prizes.forEach((p, index) => {
      const gid = String(p.giftId || "").trim();
      const sameGift = gid ? gid === target : (targetNorm && normalizePrizeText(p.name) === targetNorm);
      if (!sameGift) return;
      const pBranchId = String(p.branchId || "").trim();
      const pBranchName = String(p.branchName || "").trim();
      const general = !pBranchId && !pBranchName;
      const exact = !!branch && (pBranchId === branch || pBranchName === branch ||
        (!!branchNorm && normalizePrizeText(pBranchName) === branchNorm));
      if (!exact && !general) return;
      const remaining = Number(p.remainingQuantity || 0);
      const score = (exact ? 1000 : 0) + (remaining >= decrement.count ? 500 : 0) + Math.min(remaining, 499);
      if (!best || score > best.score || (score === best.score && sib.eventId < best.eventId)) {
        best = { eventId: sib.eventId, index, score };
      }
    });
  }
  return best ? { eventId: best.eventId, index: best.index } : null;
}

function sanitizePatch(patch) {
  if (!patch || typeof patch !== "object" || Array.isArray(patch)) return {};
  const out = {};
  for (const [key, value] of Object.entries(patch)) {
    if (!CLAIM_PATCH_KEYS.has(key)) continue;
    if (typeof value === "string" && value.length > 2000) continue;
    if (Array.isArray(value) && value.length > 40) continue;
    out[key] = value;
  }
  return out;
}

function sanitizeClaimSlot(item) {
  if (!item || item.claimSlot == null || item.claimSlot === "") return null;
  const slot = Number(item.claimSlot);
  if (!Number.isInteger(slot) || slot < 0 || slot > 100) return null;
  return slot;
}

function sanitizeDecrements(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.slice(0, 20).map((item) => {
    const count = Number(item && item.count);
    return {
      prizeIdentifier: String((item && item.prizeIdentifier) || "").trim().slice(0, 200),
      branchId: String((item && item.branchId) || "").trim().slice(0, 160),
      count: Number.isFinite(count) ? Math.floor(count) : 0,
      claimSlot: sanitizeClaimSlot(item),
      unitValue: item && typeof item.unitValue === "number" ? item.unitValue : null,
      isVoucher: item ? item.isVoucher === true : false,
      gameType: String((item && item.gameType) || "claim").slice(0, 40),
    };
  }).filter((item) => item.prizeIdentifier && item.count > 0 && item.count <= 100);
}

async function recordShards(db, eventId, decrement) {
  const shardId = String(Math.floor(Math.random() * 10));
  const keys = [
    "claims_total",
    `game_${decrement.gameType || "claim"}_claims`.replace(/[^\w\-]+/g, "_").slice(0, 120),
    `prize_${decrement.prizeIdentifier}`.replace(/[^\w\-]+/g, "_").slice(0, 120),
  ];
  if (decrement.branchId) {
    keys.push(`branch_${decrement.branchId}`.replace(/[^\w\-]+/g, "_").slice(0, 120));
  }
  await Promise.all(keys.map((counterName) => {
    const ref = db.collection("events").doc(eventId)
      .collection("sharded_counters").doc(counterName)
      .collection("shards").doc(shardId);
    return ref.set({
      count: admin.firestore.FieldValue.increment(decrement.count),
      counterName,
      eventId,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }));
}

exports.setUserRole = onCall(callableOptions, async (request) => {
  assertAppCheck(request);
  assertSignedIn(request);
  const data = request.data || {};
  if (callerRole(request) !== "super_admin") {
    throw new HttpsError(
      "permission-denied",
      "Only a super_admin can grant or remove roles.",
    );
  }

  const email = String((data && data.email) || "").trim().toLowerCase();
  const requestedRole = data && data.role != null ? String(data.role).trim() : "";
  const remove = requestedRole === "" || requestedRole === "none" || data.remove === true;
  if (!email || !email.includes("@")) {
    throw new HttpsError("invalid-argument", "A valid email is required.");
  }
  if (!remove && !ALLOWED_ROLES.has(requestedRole)) {
    throw new HttpsError(
      "invalid-argument",
      "role must be super_admin, admin, partner, or empty to remove.",
    );
  }

  const companySlug = String((data && data.companySlug) || "").trim().toLowerCase();
  const partnerAccess = String((data && data.partnerAccess) || "read").trim();
  if (!remove && requestedRole === "partner" && !companySlug) {
    throw new HttpsError(
      "invalid-argument",
      "companySlug is required when role is partner.",
    );
  }
  if (!remove && requestedRole === "partner" && partnerAccess !== "read" && partnerAccess !== "ops") {
    throw new HttpsError(
      "invalid-argument",
      "partnerAccess must be read or ops.",
    );
  }

  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (err) {
    throw new HttpsError(
      "not-found",
      "No Firebase Auth user exists for that email. Create the email/password user first.",
    );
  }

  if (user.uid === request.auth.uid && (remove || requestedRole !== "super_admin")) {
    throw new HttpsError(
      "failed-precondition",
      "A super_admin cannot remove their own role.",
    );
  }

  const nextClaims = Object.assign({}, user.customClaims || {});
  if (remove) {
    delete nextClaims.role;
    delete nextClaims.companySlug;
    delete nextClaims.partnerAccess;
  } else {
    nextClaims.role = requestedRole;
    if (requestedRole === "partner") {
      nextClaims.companySlug = companySlug;
      nextClaims.partnerAccess = partnerAccess;
    } else {
      delete nextClaims.companySlug;
      delete nextClaims.partnerAccess;
    }
  }

  await admin.auth().setCustomUserClaims(user.uid, nextClaims);
  await admin.firestore().collection("admins").doc(email).set({
    uid: user.uid,
    email,
    role: remove ? admin.firestore.FieldValue.delete() : requestedRole,
    companySlug: requestedRole === "partner" ? companySlug : admin.firestore.FieldValue.delete(),
    partnerAccess: requestedRole === "partner" ? partnerAccess : admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: request.auth.token.email || request.auth.uid,
  }, { merge: true });

  return {
    ok: true,
    uid: user.uid,
    email,
    role: remove ? null : requestedRole,
    companySlug: requestedRole === "partner" ? companySlug : null,
    partnerAccess: requestedRole === "partner" ? partnerAccess : null,
  };
});

/**
 * Same Firestore transaction the callable uses: events.allocatedPrizes and
 * receipts_transactions, then sharded counters. `actor.allowCreateReceipt`
 * lets the WhatsApp webhook insert the receipt inside that transaction.
 */
/**
 * Units already stored, for the exclusive receipt cap.
 * A missing quantity still counts as one. A positive quantity keeps its
 * numeric value, including a fraction, so this cap does not become looser.
 * Blank, zero, negative, and non-numeric quantities used to add nothing and
 * could slip past the cap; those now count as one. The consuming ledger uses
 * claimedEntryUnits instead and floors positive values.
 */
function claimedUnits(gifts) {
  if (!Array.isArray(gifts)) return 0;
  return gifts.reduce((sum, gift) => sum + exclusiveCapUnits(gift), 0);
}

function exclusiveCapUnits(gift) {
  if (!gift || typeof gift !== "object") return 1;
  const raw = gift.quantity;
  if (raw == null) return 1;
  if (typeof raw === "string" && raw.trim() === "") return 1;
  const count = Number(raw);
  if (Number.isFinite(count) && count > 0) return count;
  return 1;
}

/**
 * Max gift units one receipt may receive: Smart Multipliers OFF => 1,
 * ON => maxChancesPerReceipt (0 = no cap); further bounded by the receipt's
 * chances_earned when it is a positive number.
 */
// Pieces handed over per ONE offer (max over the event's rules, >= 1). An
// offer such as "6 bags" counts as one award unit, so the piece limit is
// units * piecesPerOffer.
function piecesPerOffer(event) {
  const rules = Array.isArray(event && event.promotionalRules) ? event.promotionalRules : [];
  let best = 1;
  for (const r of rules) {
    const gifts = Array.isArray(r && r.linkedGifts) ? r.linkedGifts : [];
    const sum = gifts.reduce((s, g) => s + Math.max(0, Math.floor(Number(g && g.quantity) || 0)), 0);
    if (sum > best) best = sum;
  }
  return best;
}

// Max gift PIECES this receipt may claim. A cap above 1 trims, switch on or
// off. A cap of 1 does not apply to an exclusive ladder: that ladder is the
// top tier plus one remainder tier, and the count is recomputed from the
// stored lines so chances_earned cannot raise it. Other campaigns keep
// today's cap.
// serverUnits is the gift count the stored invoice lines earn (campaign_eligibility.js);
// it only ever lowers the limit.
function receiptUnitLimit(event, receipt, patch, serverUnits) {
  const allow = event && event.allowMultipleChances === true;
  const cap = Number(event && event.maxChancesPerReceipt);
  const ladder = exclusiveLadderUnits(event, receipt);
  // A cap of 1 is the old one-gift clamp. It does not apply to an exclusive
  // ladder, so the top tier and one remainder tier both stand. A cap set
  // above 1 still binds, switch on or off. Other campaigns keep today's cap.
  let units = Infinity;
  if (ladder != null && Number.isFinite(cap) && cap > 1) units = Math.floor(cap);
  else if (ladder == null && allow && Number.isFinite(cap) && cap > 0) units = Math.floor(cap);
  const src = patch && patch.chances_earned != null ? patch.chances_earned : (receipt && receipt.chances_earned);
  const chances = Number(src);
  if (Number.isFinite(chances) && chances > 0) units = Math.min(units, Math.floor(chances));
  // 0 means the stored lines could not be read as a ladder at all; that is
  // left to chances_earned rather than blocking the claim outright.
  if (ladder != null && ladder > 0) units = Math.min(units, ladder);
  if (Number.isFinite(serverUnits) && serverUnits > 0) units = Math.min(units, Math.floor(serverUnits));
  return Number.isFinite(units) ? units * piecesPerOffer(event) : Infinity;
}


// 2.0.164: an over-limit request is trimmed (highest unit value first) instead
// of rejected, so stale clients still hand over exactly the allowed units.
function decrementUnitValue(d, prizes) {
  if (typeof d.unitValue === "number" && Number.isFinite(d.unitValue)) return d.unitValue;
  const id = String(d.prizeIdentifier || "");
  const row = (prizes || []).find((p) => p && (p.giftId === id || p.name === id || p.giftName === id));
  const v = Number(row && (row.unitValue != null ? row.unitValue : row.value));
  return Number.isFinite(v) ? v : 0;
}

function trimDecrementsToLimit(decrements, allowed, prizes) {
  const order = decrements.map((d, i) => ({ d, i, v: decrementUnitValue(d, prizes) }))
    .sort((a, b) => (b.v - a.v) || (a.i - b.i));
  let left = Math.max(0, Math.floor(allowed));
  const kept = new Map();
  for (const { d, i } of order) {
    const take = Math.min(d.count, left);
    left -= take;
    if (take > 0) kept.set(i, Object.assign({}, d, { count: take }));
  }
  return decrements.map((_, i) => kept.get(i)).filter(Boolean);
}

function giftKey(g) {
  return String((g && (g.giftId || g.giftName || g.name)) || "");
}

/**
 * Client gift entries that match what this call granted, each quantity capped
 * at the grant. `left` holds the granted units no client entry described.
 */
function grantedGiftEntries(clientGifts, granted) {
  const left = new Map();
  for (const d of granted) left.set(d.prizeIdentifier, (left.get(d.prizeIdentifier) || 0) + d.count);
  const entries = [];
  for (const g of Array.isArray(clientGifts) ? clientGifts : []) {
    if (!g || typeof g !== "object") continue;
    const key = [g.giftId, g.giftName].find((k) => k && left.has(String(k)));
    if (!key) continue;
    const q = Math.min(Number(g.quantity || 1), left.get(String(key)));
    left.set(String(key), left.get(String(key)) - q);
    if (q > 0) entries.push(Object.assign({}, g, { quantity: q }));
  }
  return { entries, left };
}

/** Rewrites the client summary fields so the receipt records only what was granted. */
function trimPatchToDecrements(patch, granted, clientGifts = patch.claimed_gifts) {
  const total = granted.reduce((s, d) => s + d.count, 0);
  const gifts = Array.isArray(clientGifts) ? grantedGiftEntries(clientGifts, granted).entries : [];
  const names = (gifts.length ? gifts : granted.map((d) => ({ giftName: d.prizeIdentifier, quantity: d.count })))
    .map((g) => {
      const n = String(g.giftName || g.name || giftKey(g));
      const q = Number(g.quantity || 1);
      return q > 1 ? `${q} × ${n}` : n;
    });
  const summary = names.join(" + ");
  patch.matched_reward_value = summary;
  if (typeof patch.prize_won === "string") patch.prize_won = summary;
  if (Array.isArray(patch.prizes_won)) patch.prizes_won = patch.prizes_won.slice(0, total);
  patch.claim_trimmed_to_limit = true;
  return patch;
}

/** Removes the claim-state fields from the client patch and returns them. */
function takeClientClaimState(patch) {
  const hints = {};
  for (const key of CLAIM_STATE_KEYS) {
    if (key in patch) hints[key] = patch[key];
    delete patch[key];
  }
  return hints;
}

function storedRemaining(receipt) {
  const raw = receipt && receipt.remaining_chances;
  if (raw == null || raw === "") return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

/** The receipt has been through a claim. A stored chance count above 0 keeps a multi-chance receipt open. */
function claimStarted(receipt) {
  return !!receipt && (receipt.claimedAt != null || receipt.game_played === true);
}

function receiptAlreadyClaimed(receipt) {
  if (!claimStarted(receipt)) return false;
  const left = storedRemaining(receipt);
  return !(left != null && left > 0);
}

/**
 * Chances left after this call. A claim call uses one chance, and the receipt
 * never stays open past its unit limit. The client's own count can only close
 * the receipt earlier, never keep it open.
 */
function remainingAfterClaim({ event, receipt, createdReceipt, limit, claimedPieces, clientRemaining }) {
  let prev = createdReceipt || !claimStarted(receipt) ? null : storedRemaining(receipt);
  if (prev == null) {
    const earned = Number(receipt && receipt.chances_earned);
    prev = Number.isFinite(earned) && earned > 0 ? Math.floor(earned) : 1;
  }
  let next = Math.max(0, Math.floor(prev) - 1);
  if (Number.isFinite(limit)) {
    next = Math.min(next, Math.ceil(Math.max(0, limit - claimedPieces) / piecesPerOffer(event)));
  }
  const hint = clientRemaining == null || clientRemaining === "" ? NaN : Number(clientRemaining);
  if (Number.isFinite(hint)) next = Math.min(next, Math.max(0, Math.floor(hint)));
  return next;
}

/**
 * claimed_gifts after this call: the gifts already on the receipt plus what
 * this call granted. Labels come from the client entries that match a grant;
 * any granted unit without one is described from its stock row.
 */
function claimedGiftsAfterClaim(receipt, createdReceipt, clientGifts, granted, stockRows) {
  const prior = !createdReceipt && claimStarted(receipt) && Array.isArray(receipt.claimed_gifts)
    ? receipt.claimed_gifts : [];
  const { entries, left } = grantedGiftEntries(clientGifts, granted);
  granted.forEach((d, i) => {
    const n = left.get(d.prizeIdentifier) || 0;
    if (n <= 0) return;
    left.set(d.prizeIdentifier, 0);
    const row = stockRows[i] || {};
    entries.push({
      giftId: String(row.giftId || ""),
      giftName: String(row.name || d.prizeIdentifier),
      quantity: n,
      unitValue: Number(d.unitValue != null ? d.unitValue : row.unitValue) || 0,
      isVoucher: d.isVoucher === true || row.giftType === "voucher",
    });
  });
  return prior.concat(entries);
}

async function applyCampaignPrizeClaim(db, input) {
  const eventId = String((input && input.eventId) || "").trim();
  const receiptId = String((input && input.receiptId) || "").trim();
  let decrements = sanitizeDecrements((input && input.decrements) || []);
  const patch = sanitizePatch(input && input.receiptPatch);
  const clientClaim = takeClientClaimState(patch);
  const actor = input.actor || {};
  const staff = actor.staff === true;
  const partner = actor.partner === true;
  const anonymous = actor.anonymous === true;
  const system = actor.system === true;
  const nowMs = Number.isFinite(input && input.nowMs) ? input.nowMs : Date.now();

  if (!eventId || eventId.length > 128) {
    throw new HttpsError("invalid-argument", "eventId is required.");
  }
  if (decrements.length === 0 && Object.keys(patch).length === 0 && Object.keys(clientClaim).length === 0 &&
      !input.receiptCreate) {
    throw new HttpsError("invalid-argument", "Nothing to claim.");
  }
  if (!staff && !partner && !anonymous && !system) {
    throw new HttpsError("permission-denied", "This account cannot dispense gifts.");
  }
  if ((anonymous || partner) && !receiptId) {
    throw new HttpsError(
      "permission-denied",
      "A receipt id is required to dispense a gift.",
    );
  }

  const patchKeys = Object.keys(patch);
  const confirmOnly = decrements.length === 0 && !input.receiptCreate && patchKeys.length > 0 &&
    Object.keys(clientClaim).length === 0 && patchKeys.every((k) => CONFIRM_PATCH_KEYS.has(k));
  if (confirmOnly) {
    if (!receiptId) throw new HttpsError("invalid-argument", "A receipt id is required.");
    if ("handed_over_confirmed" in patch) patch.handed_over_confirmed = true;
  }

  const eventRef = db.collection("events").doc(eventId);
  const receiptRef = receiptId ? db.collection("receipts_transactions").doc(receiptId) : null;

  const result = await db.runTransaction(async (tx) => {
    const eventSnap = await tx.get(eventRef);
    if (!eventSnap.exists) {
      throw new HttpsError("not-found", "Campaign not found.");
    }
    const event = eventSnap.data() || {};
    if (event.isActive !== true && !staff) {
      throw new HttpsError("failed-precondition", "Campaign is not active.", { reason: REASONS.CAMPAIGN_INACTIVE });
    }
    if (partner) {
      const slug = String((actor.token && actor.token.companySlug) || "");
      const access = String((actor.token && actor.token.partnerAccess) || "read");
      if (!slug || event.companySlug !== slug || access !== "ops") {
        throw new HttpsError("permission-denied", "Partner cannot dispense this campaign.");
      }
    }

    let receipt = null;
    let createdReceipt = false;
    if (receiptRef) {
      const receiptSnap = await tx.get(receiptRef);
      if (!receiptSnap.exists) {
        if (!(actor.allowCreateReceipt && input.receiptCreate)) {
          throw new HttpsError("not-found", "Receipt not found.");
        }
        receipt = input.receiptCreate;
        createdReceipt = true;
      } else {
        receipt = receiptSnap.data() || {};
        const receiptCampaign = String(receipt.campaignId || receipt.event_id || "");
        if (!staff && receiptCampaign && receiptCampaign !== eventId) {
          throw new HttpsError("permission-denied", "Receipt is for a different campaign.");
        }
        if (anonymous || partner) {
          if (receipt.submittedByUid !== actor.uid) {
            throw new HttpsError("permission-denied", "You can only claim your own receipt.");
          }
        }
        if (confirmOnly) {
          if (receipt.game_played !== true) {
            throw new HttpsError("failed-precondition", "لم يتم صرف هدية هذه الفاتورة بعد.");
          }
        } else if (!staff && receiptAlreadyClaimed(receipt)) {
          throw new HttpsError("failed-precondition", "This receipt was already claimed.", { reason: ALREADY_CLAIMED });
        }
      }
    }

    // Staff keep their manual override; every other actor is re-verified from
    // the stored campaign and receipt before any stock is touched.
    let serverUnits = null;
    if (receipt && decrements.length > 0 && !confirmOnly && !staff) {
      const verdict = evaluateClaimEligibility({ event, receipt, nowMs, system });
      if (!verdict.ok) {
        throw new HttpsError("failed-precondition", verdict.message, Object.assign({ reason: verdict.code }, verdict.details));
      }
      serverUnits = verdict.serverUnits;
    }

    let consumingLedger = false;
    if (receipt && decrements.length > 0 && event.spendLadderMode === "consuming") {
      const plan = planConsumingClaim(event, receipt, decrements);
      const reason = plan && plan.reason;
      if (reason === "already_claimed") {
        throw new HttpsError("failed-precondition", "This receipt was already claimed.", { reason });
      }
      if (reason === "missing_lines") {
        throw new HttpsError("failed-precondition", "لا يمكن إعادة حساب شرائح الإنفاق من هذه الفاتورة.", { reason });
      }
      if (reason === "tier_mismatch") {
        throw new HttpsError("failed-precondition", "الهدية لا تطابق شريحة هذه الجولة.", { reason });
      }
      if (reason === "extra_quantity") {
        throw new HttpsError("failed-precondition", "الكمية أكبر من الجولات المستحقة.", { reason });
      }
      if (reason === "missing_spend_rules") {
        throw new HttpsError("failed-precondition", "حملة شرائح الإنفاق لا تحتوي على قاعدة إنفاق، لذلك لا تُصرف هدية.", { reason });
      }
      if (reason === "round_unbound") {
        throw new HttpsError("failed-precondition", "تعذر تحديد الجولة المطلوبة، ولم يُصرف مخزون إضافي.", { reason });
      }
      if (reason === "round_conflict" || reason === "stale_round" || reason === "round_gap") {
        throw new HttpsError("failed-precondition", "هذه الجولة لم تَعُد مطابقة للسجل المحفوظ، ولم يُصرف مخزون إضافي.", { reason });
      }
      if (reason) {
        throw new HttpsError("failed-precondition", "تعذر اعتماد هذه الجولة.", { reason });
      }
      if (plan && !plan.skip && !reason) {
        // The stored ledger is the previous transaction snapshot plus this
        // round's canonical gift. The client array is discarded, and the
        // generic trimmer must not rebuild that array from the request.
        consumingLedger = true;
        decrements = plan.decrements;
        patch.claimed_gifts = plan.claimed_gifts;
        patch.prizes_won = plan.prizes_won;
        patch.prize_won = plan.prizes_won.join(" + ");
        patch.remaining_chances = plan.remaining_chances;
      }
    }

    // 2.0.163: max gift UNITS per receipt = min(campaign cap, receipt chances).
    // 2.0.164: over-limit requests are trimmed, highest value first, no error.
    // A consuming ladder already accepted an exact round list, so this trim
    // does not run for it and cannot replace claimed_gifts.
    let trim = null;
    let limit = Infinity;
    let already = 0;
    if (receipt && decrements.length > 0 && !consumingLedger) {
      limit = receiptUnitLimit(event, receipt, patch, serverUnits);
      already = createdReceipt ? 0 : claimedUnits(receipt.claimed_gifts);
      const requested = decrements.reduce((s, d) => s + Number(d.count || 0), 0);
      if (Number.isFinite(limit) && already + requested > limit) {
        const allowed = Math.max(0, limit - already);
        if (allowed <= 0) {
          throw new HttpsError("failed-precondition", "This receipt was already claimed.",
            { reason: "unit_cap_exhausted", limit, requested, already });
        }
        decrements = trimDecrementsToLimit(decrements, allowed, event.allocatedPrizes);
        trimPatchToDecrements(patch, decrements, clientClaim.claimed_gifts);
        trim = { limit, requested, granted: allowed, already };
      }
    }

    const prizes = Array.isArray(event.allocatedPrizes)
      ? event.allocatedPrizes.map((p) => Object.assign({}, p))
      : [];
    // Other campaigns whose rows were drawn from (shared company pool).
    const pooled = new Map();
    let siblings = null;
    const loadSiblings = async () => {
      if (siblings) return siblings;
      siblings = [];
      const slug = String(event.companySlug || "").trim();
      if (!slug) return siblings;
      const snap = await tx.get(db.collection("events")
        .where("companySlug", "==", event.companySlug)
        .where("isActive", "==", true));
      snap.docs.forEach((doc) => {
        if (doc.id === eventId) return;
        const data = doc.data() || {};
        if (!sharedPoolEnabled(data)) return;
        siblings.push({
          eventId: doc.id,
          ref: doc.ref,
          prizes: Array.isArray(data.allocatedPrizes)
            ? data.allocatedPrizes.map((p) => Object.assign({}, p))
            : [],
        });
      });
      return siblings;
    };
    // 2.0.153: the store code in the receipt number decides the branch id the
    // client writes (only when the client already writes branch_id).
    if (typeof patch.branch_id === "string") {
      const codeBranch = branchIdFromStoreCode(prizes, Object.assign({}, receipt || {}, patch),
        Array.isArray(event.branchIds) ? event.branchIds : []);
      if (codeBranch) patch.branch_id = codeBranch;
    }
    const applied = [];
    const stockRows = [];
    for (const decrement of decrements) {
      const hint = Object.assign({}, receipt || {});
      for (const k of ["branch_id", "branch_detected"]) {
        if (typeof patch[k] === "string" && patch[k].trim()) hint[k] = patch[k];
      }
      const resolved = decrement.ladder === true
        ? resolveLadderStockRow(prizes, decrement, hint)
        : resolvePrizeIndexForDecrement(prizes, decrement, hint);
      let index = resolved.index;
      let rows = prizes;
      let sourceEventId = eventId;
      if ((!decrement.branchId || resolved.fromStoreCode) && resolved.branchId) decrement.branchId = resolved.branchId;
      if (index === -1 && sharedPoolEnabled(event)) {
        const sibs = await loadSiblings();
        const hit = findSharedPoolRow(sibs, decrement, resolved.branchId);
        if (hit) {
          const sib = sibs.find((x) => x.eventId === hit.eventId);
          if (decrement.ladder === true && ladderRowConflicts(sib.prizes[hit.index], decrement)) {
            throw misconfiguredError(sib.prizes[hit.index], decrement, resolved.branchId);
          }
          rows = sib.prizes;
          index = hit.index;
          sourceEventId = sib.eventId;
          pooled.set(sib.eventId, sib);
        }
      }
      if (index === -1 && resolved.noBranchStock) {
        throw new HttpsError("failed-precondition", NO_BRANCH_STOCK_MESSAGE, { reason: "no_branch_stock" });
      }
      if (index === -1) {
        // failed-precondition (not not-found): the campaign exists but has no
        // stock row for this gift, so the client must not treat it as a
        // missing function / missing document.
        throw new HttpsError(
          "failed-precondition",
          `لا يوجد رصيد مخصص لهدية (${decrement.prizeIdentifier}) في هذه الحملة/الفرع. يرجى تغذية أرصدة الفروع من شاشة الأرصدة ثم إعادة المحاولة.`,
        );
      }
      const remaining = Number(rows[index].remainingQuantity || 0);
      if (remaining < decrement.count) {
        throw insufficientStockError(rows[index], decrement, resolved.branchId, remaining);
      }
      rows[index].remainingQuantity = remaining - decrement.count;
      stockRows.push(rows[index]);
      applied.push({
        prizeIdentifier: decrement.prizeIdentifier,
        count: decrement.count,
        remainingQuantity: rows[index].remainingQuantity,
        stockEventId: sourceEventId,
      });
    }

    if (decrements.length > 0 && applied.some((a) => a.stockEventId === eventId)) {
      tx.update(eventRef, { allocatedPrizes: prizes });
    }
    for (const sib of pooled.values()) {
      tx.update(sib.ref, { allocatedPrizes: sib.prizes });
    }
    const pooledSources = applied.filter((a) => a.stockEventId !== eventId)
      .map((a) => ({ prizeIdentifier: a.prizeIdentifier, count: a.count, stockEventId: a.stockEventId }));
    if (receipt && decrements.length > 0) {
      if (!consumingLedger) {
        const grantedPieces = decrements.reduce((s, d) => s + d.count, 0);
        patch.claimed_gifts = claimedGiftsAfterClaim(receipt, createdReceipt, clientClaim.claimed_gifts, decrements, stockRows);
        patch.remaining_chances = remainingAfterClaim({
          event, receipt, createdReceipt, limit,
          claimedPieces: already + grantedPieces,
          clientRemaining: clientClaim.remaining_chances,
        });
      }
      patch.game_played = true;
      if (createdReceipt || receipt.claimedAt == null) {
        patch.claimedAt = admin.firestore.FieldValue.serverTimestamp();
        patch.claimedBy = String(actor.uid || (staff ? "staff" : "unknown")).slice(0, 128);
      }
    }
    if (receiptRef && (createdReceipt || Object.keys(patch).length > 0)) {
      const payload = createdReceipt
        ? Object.assign({}, receipt, patch)
        : Object.assign({}, patch);
      if (confirmOnly) {
        if (payload.handed_over_confirmed) payload.handed_over_confirmed_at = admin.firestore.FieldValue.serverTimestamp();
      } else {
        payload.claim_processed_at = admin.firestore.FieldValue.serverTimestamp();
      }
      // Lets a later restock/refund return stock to the campaign it came from.
      if (pooledSources.length > 0) payload.claim_stock_sources = pooledSources;
      tx.set(receiptRef, payload, { merge: true });
    }
    return { applied, hadReceipt: !!receipt, trim };
  });

  await Promise.all(decrements.map((decrement) => recordShards(db, eventId, decrement).catch((err) => {
    console.error("Shard increment failed", err);
  })));

  return {
    ok: true, eventId, receiptId: receiptId || null, applied: result.applied,
    trimmed: !!result.trim, limit: result.trim ? result.trim.limit : null,
    grantedUnits: result.trim ? result.trim.granted : null,
    matchedRewardValue: result.trim ? patch.matched_reward_value : null,
    claimedGifts: result.trim ? (patch.claimed_gifts || null) : null,
  };
}

exports.applyCampaignPrizeClaim = applyCampaignPrizeClaim;

/** Structured log + receipt marker for a failed claim (no secrets). */
async function recordClaimFailure(db, data, uid, err) {
  const code = (err && err.code) || "internal";
  const message = String((err && err.message) || "").slice(0, 500);
  const details = err && err.details && typeof err.details === "object" ? err.details : null;
  console.warn(JSON.stringify({
    severity: "WARNING",
    fn: "decrementCampaignPrize",
    code,
    message,
    reason: details && details.reason ? String(details.reason) : null,
    eventId: String((data && data.eventId) || "").slice(0, 128),
    receiptId: String((data && data.receiptId) || "").slice(0, 200),
    uid: uid || null,
  }));
  const receiptId = String((data && data.receiptId) || "").trim();
  if (!db || !receiptId || receiptId.includes("/") || receiptId.length > 200) return;
  try {
    // update() never creates a missing receipt.
    await db.collection("receipts_transactions").doc(receiptId).update({
      claim_last_error: message,
      claim_last_error_code: code,
      claim_last_error_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // best effort
  }
}

exports.decrementCampaignPrize = onCall(callableOptions, async (request) => {
  const data = (request && request.data) || {};
  try {
    return await decrementCampaignPrizeImpl(request);
  } catch (err) {
    const isHttps = err instanceof HttpsError;
    // Only touch the receipt once the caller passed auth checks.
    const reason = isHttps && err.details && err.details.reason;
    // An eligibility rejection writes nothing at all, not even the failure marker.
    const authed = isHttps && err.code !== "unauthenticated" && err.code !== "permission-denied" &&
      !(err.message || "").includes("App Check") && !ELIGIBILITY_REASONS.has(reason);
    await recordClaimFailure(authed ? admin.firestore() : null, data,
      request && request.auth ? request.auth.uid : null, err);
    throw err;
  }
});

async function decrementCampaignPrizeImpl(request) {
  assertAppCheck(request);
  assertSignedIn(request);
  const data = request.data || {};
  const token = request.auth.token || {};
  const role = callerRole(request);
  return applyCampaignPrizeClaim(admin.firestore(), {
    eventId: data.eventId,
    receiptId: data.receiptId,
    decrements: data.decrements,
    receiptPatch: data.receiptPatch,
    actor: {
      staff: isStaffRole(role),
      partner: role === "partner",
      anonymous: !!(token.firebase && token.firebase.sign_in_provider === "anonymous"),
      system: false,
      allowCreateReceipt: false,
      uid: request.auth.uid,
      token,
    },
  });
}

// Non-enumerable so index.js Object.assign does not expose it as a function group.
Object.defineProperty(exports, "_testing", {
  value: { NO_BRANCH_STOCK_MESSAGE, findBestPrizeMatchIndex, resolvePrizeIndexForDecrement, resolveLadderStockRow, ladderRowConflicts, storeCodeFromReceiptNumber, branchIdFromStoreCode, findSharedPoolRow, sharedPoolEnabled, applyCampaignPrizeClaim, receiptUnitLimit,
    piecesPerOffer, claimedUnits, recordClaimFailure, trimDecrementsToLimit, trimPatchToDecrements, planConsumingClaim },
  enumerable: false,
});
