/**
 * Auth claims and server-side gift stock mutations.
 *
 * setUserRole: super_admin only. Grants or clears role claims.
 * decrementCampaignPrize: staff, partner ops, or the anonymous receipt owner.
 * Inventory remainingQuantity is changed here with the Admin SDK so clients
 * cannot write stock counters directly.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
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
  "linked_gifts",
  "unit_value",
  "is_voucher",
]);

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
async function applyCampaignPrizeClaim(db, input) {
  const eventId = String((input && input.eventId) || "").trim();
  const receiptId = String((input && input.receiptId) || "").trim();
  const decrements = sanitizeDecrements((input && input.decrements) || []);
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
        if (anonymous || partner || system) {
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

    const prizes = Array.isArray(event.allocatedPrizes)
      ? event.allocatedPrizes.map((p) => Object.assign({}, p))
      : [];
    const applied = [];
    for (const decrement of decrements) {
      const index = findBestPrizeMatchIndex(prizes, decrement.prizeIdentifier, decrement);
      if (index === -1) {
        // failed-precondition (not not-found): the campaign exists but has no
        // stock row for this gift, so the client must not treat it as a
        // missing function / missing document.
        throw new HttpsError(
          "failed-precondition",
          `لا يوجد رصيد مخصص لهدية (${decrement.prizeIdentifier}) في هذه الحملة/الفرع. يرجى تغذية أرصدة الفروع من شاشة الأرصدة ثم إعادة المحاولة.`,
        );
      }
      const remaining = Number(prizes[index].remainingQuantity || 0);
      if (remaining < decrement.count) {
        throw new HttpsError("failed-precondition", "Not enough prize stock remaining.");
      }
      prizes[index].remainingQuantity = remaining - decrement.count;
      applied.push({
        prizeIdentifier: decrement.prizeIdentifier,
        count: decrement.count,
        remainingQuantity: prizes[index].remainingQuantity,
      });
    }

    if (decrements.length > 0) {
      tx.update(eventRef, { allocatedPrizes: prizes });
    }
    if (receiptRef && (createdReceipt || Object.keys(patch).length > 0)) {
      const payload = createdReceipt
        ? Object.assign({}, receipt, patch)
        : Object.assign({}, patch);
      payload.claim_processed_at = admin.firestore.FieldValue.serverTimestamp();
      tx.set(receiptRef, payload, { merge: true });
    }
    return { applied, hadReceipt: !!receipt };
  });

  await Promise.all(decrements.map((decrement) => recordShards(db, eventId, decrement).catch((err) => {
    console.error("Shard increment failed", err);
  })));

  return { ok: true, eventId, receiptId: receiptId || null, applied: result.applied };
}

exports.applyCampaignPrizeClaim = applyCampaignPrizeClaim;

exports.decrementCampaignPrize = onCall(callableOptions, async (request) => {
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
});
