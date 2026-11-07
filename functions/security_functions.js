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
  "claim_trimmed_to_limit",
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

function sanitizeDecrements(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.slice(0, 20).map((item) => {
    const count = Number(item && item.count);
    return {
      prizeIdentifier: String((item && item.prizeIdentifier) || "").trim().slice(0, 200),
      branchId: String((item && item.branchId) || "").trim().slice(0, 160),
      count: Number.isFinite(count) ? Math.floor(count) : 0,
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
/** Sum of quantities in a claimed_gifts array. */
function claimedUnits(gifts) {
  if (!Array.isArray(gifts)) return 0;
  return gifts.reduce((s, g) => {
    const q = Number(g && g.quantity != null ? g.quantity : 1);
    return s + (Number.isFinite(q) && q > 0 ? q : 0);
  }, 0);
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

// Max gift PIECES this receipt may claim. Switch ON with a cap: cap offers
// (highest value first on the client). Switch OFF: no cross-offer cap here
// (each rule is already limited to one offer by the client). Always bounded by
// the receipt's own chances_earned (offers).
function receiptUnitLimit(event, receipt, patch) {
  const allow = event && event.allowMultipleChances === true;
  const cap = Number(event && event.maxChancesPerReceipt);
  let units = allow && Number.isFinite(cap) && cap > 0 ? Math.floor(cap) : Infinity;
  const src = patch && patch.chances_earned != null ? patch.chances_earned : (receipt && receipt.chances_earned);
  const chances = Number(src);
  if (Number.isFinite(chances) && chances > 0) units = Math.min(units, Math.floor(chances));
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

/** Rewrites the client patch so the receipt records only what was granted. */
function trimPatchToDecrements(patch, granted) {
  const left = new Map();
  for (const d of granted) left.set(d.prizeIdentifier, (left.get(d.prizeIdentifier) || 0) + d.count);
  const total = granted.reduce((s, d) => s + d.count, 0);
  let gifts = Array.isArray(patch.claimed_gifts) ? patch.claimed_gifts : null;
  if (gifts) {
    gifts = gifts.map((g) => {
      const key = [g && g.giftId, g && g.giftName].find((k) => k && left.has(String(k)));
      if (!key) return null;
      const q = Math.min(Number(g.quantity || 1), left.get(String(key)));
      left.set(String(key), left.get(String(key)) - q);
      return q > 0 ? Object.assign({}, g, { quantity: q }) : null;
    }).filter(Boolean);
    if (gifts.length === 0 && granted.length > 0) {
      gifts = granted.map((d) => ({ giftId: "", giftName: d.prizeIdentifier, quantity: d.count,
        unitValue: d.unitValue || 0, isVoucher: d.isVoucher === true }));
    }
    patch.claimed_gifts = gifts;
  }
  const names = (gifts || granted.map((d) => ({ giftName: d.prizeIdentifier, quantity: d.count })))
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

async function applyCampaignPrizeClaim(db, input) {
  const eventId = String((input && input.eventId) || "").trim();
  const receiptId = String((input && input.receiptId) || "").trim();
  let decrements = sanitizeDecrements((input && input.decrements) || []);
  const patch = sanitizePatch(input && input.receiptPatch);
  const actor = input.actor || {};
  const staff = actor.staff === true;
  const partner = actor.partner === true;
  const anonymous = actor.anonymous === true;
  const system = actor.system === true;

  if (!eventId || eventId.length > 128) {
    throw new HttpsError("invalid-argument", "eventId is required.");
  }
  if (decrements.length === 0 && Object.keys(patch).length === 0 && !input.receiptCreate) {
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
    patchKeys.every((k) => CONFIRM_PATCH_KEYS.has(k));
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
      throw new HttpsError("failed-precondition", "Campaign is not active.");
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
        } else if (anonymous || partner || system) {
          const played = receipt.game_played === true;
          const remaining = Number(
            receipt.remaining_chances != null ? receipt.remaining_chances : (receipt.chances_earned || 1),
          );
          if (played && remaining <= 0) {
            throw new HttpsError("failed-precondition", "This receipt was already claimed.");
          }
        }
      }
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
    if (receipt && decrements.length > 0 && !consumingLedger) {
      const limit = receiptUnitLimit(event, receipt, patch);
      const already = createdReceipt ? 0 : claimedUnits(receipt.claimed_gifts);
      const requested = decrements.reduce((s, d) => s + Number(d.count || 0), 0);
      if (Number.isFinite(limit) && already + requested > limit) {
        const allowed = Math.max(0, limit - already);
        if (allowed <= 0) {
          throw new HttpsError("failed-precondition", "This receipt was already claimed.",
            { reason: "unit_cap_exhausted", limit, requested, already });
        }
        decrements = trimDecrementsToLimit(decrements, allowed, event.allocatedPrizes);
        trimPatchToDecrements(patch, decrements);
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
    for (const decrement of decrements) {
      const hint = Object.assign({}, receipt || {});
      for (const k of ["branch_id", "branch_detected"]) {
        if (typeof patch[k] === "string" && patch[k].trim()) hint[k] = patch[k];
      }
      const resolved = resolvePrizeIndexForDecrement(prizes, decrement, hint);
      let index = resolved.index;
      let rows = prizes;
      let sourceEventId = eventId;
      if ((!decrement.branchId || resolved.fromStoreCode) && resolved.branchId) decrement.branchId = resolved.branchId;
      if (index === -1 && sharedPoolEnabled(event)) {
        const sibs = await loadSiblings();
        const hit = findSharedPoolRow(sibs, decrement, resolved.branchId);
        if (hit) {
          const sib = sibs.find((x) => x.eventId === hit.eventId);
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
        throw new HttpsError("failed-precondition", "Not enough prize stock remaining.");
      }
      rows[index].remainingQuantity = remaining - decrement.count;
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
    const authed = isHttps && err.code !== "unauthenticated" && err.code !== "permission-denied" && !(err.message || "").includes("App Check");
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
  value: { NO_BRANCH_STOCK_MESSAGE, findBestPrizeMatchIndex, resolvePrizeIndexForDecrement, storeCodeFromReceiptNumber, branchIdFromStoreCode, findSharedPoolRow, sharedPoolEnabled, applyCampaignPrizeClaim, receiptUnitLimit,
    piecesPerOffer, claimedUnits, recordClaimFailure, trimDecrementsToLimit, trimPatchToDecrements, planConsumingClaim },
  enumerable: false,
});
