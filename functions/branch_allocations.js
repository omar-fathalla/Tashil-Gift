"use strict";
/**
 * updateBranchAllocations callable: server-side write path for the branch
 * balances screen (company portal and admin). Company users (role partner)
 * cannot write events / gift_stock_movements / company_gifts under
 * firestore.rules, so the client computes the new allocatedPrizes exactly as
 * before and this function validates and writes them with the Admin SDK.
 *
 * actions:
 *  - "bulk":       { companySlug, events:[{eventId, allocatedPrizes, branchNames?}], movements:[...] }
 *  - "settlement": { companySlug, eventId, allocatedPrizes, settlement:{...}, movement:{...} }
 */
const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");

const MAX_QTY = 10000000;
const MAX_PRIZES = 1000;
const MAX_EVENTS = 50;
const MAX_MOVEMENTS = 2000;
const BULK_TYPES = new Set(["branch_allocation_increase", "branch_allocation_decrease"]);

const s = (v) => (v === undefined || v === null ? "" : String(v)).trim();

function bad(msg) { return new HttpsError("invalid-argument", msg); }

function str(v, max, field) {
  if (v === undefined || v === null) return "";
  if (typeof v !== "string" || v.length > max) throw bad(`${field} is invalid.`);
  return v;
}

function int(v, field, { min = -MAX_QTY, max = MAX_QTY } = {}) {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) throw bad(`${field} must be an integer.`);
  return v;
}

function num(v, field) {
  if (v === undefined || v === null) return 0;
  if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 1e9) throw bad(`${field} is invalid.`);
  return v;
}

/** Same shape as AllocatedPrize.toMap() on the client. */
function cleanPrize(p, i) {
  if (!p || typeof p !== "object" || Array.isArray(p)) throw bad(`allocatedPrizes[${i}] is invalid.`);
  const allocated = int(p.allocatedQuantity, "allocatedQuantity", { min: 0 });
  const remaining = int(p.remainingQuantity, "remainingQuantity", { min: 0 });
  if (remaining > allocated) throw bad("remainingQuantity cannot exceed allocatedQuantity.");
  const out = {
    giftId: str(p.giftId, 200, "giftId"),
    name: str(p.name, 300, "name"),
    allocatedQuantity: allocated,
    remainingQuantity: remaining,
    giftType: str(p.giftType, 60, "giftType"),
    unitValue: num(p.unitValue, "unitValue"),
  };
  const branchId = str(p.branchId, 200, "branchId");
  const branchName = str(p.branchName, 300, "branchName");
  const imageUrl = str(p.imageUrl, 2000, "imageUrl");
  if (branchId) out.branchId = branchId;
  if (branchName) out.branchName = branchName;
  if (imageUrl) out.imageUrl = imageUrl;
  return out;
}

function cleanPrizes(list) {
  if (!Array.isArray(list) || list.length > MAX_PRIZES) throw bad("allocatedPrizes is invalid.");
  return list.map(cleanPrize);
}

const prizeKey = (p) => `${s(p.branchName).toLowerCase()}|${s(p.giftId || p.name).toLowerCase()}`;

const normBranch = (v) => s(v).toLowerCase()
  .replace(/[\u064B-\u065F\u0670\u0640]/g, "").replace(/[أإآ]/g, "ا").replace(/ة/g, "ه").replace(/ى/g, "ي")
  .replace(/\s*\([^)]*\)|\s*\[[^\]]*\]/g, " ").replace(/^\s*فرع\s+/, "").replace(/\s+/g, " ").trim();

function branchMatches(a, b) {
  const x = normBranch(a), y = normBranch(b);
  if (!x || !y) return false;
  return x === y || (x.length >= 3 && y.includes(x)) || (y.length >= 3 && x.includes(y));
}

/**
 * Handed-out counts per receipt branch, built like the balances screen's
 * "صرف" column: claimed_gifts, else linkedGifts + prizes_won + prize_won.
 * Returns [{branch, gifts: Map<lowerKey, qty>}].
 */
function buildHandedOut(txDocs, cutoffMs) {
  const byBranch = new Map();
  for (const d of txDocs) {
    if (cutoffMs) {
      const t = d.timestamp && typeof d.timestamp.toMillis === "function" ? d.timestamp.toMillis()
        : (typeof d.timestamp === "string" ? Date.parse(d.timestamp) : NaN);
      if (Number.isFinite(t) && t <= cutoffMs) continue;
    }
    const br = s(d.canonical_branch || d.branch_detected || d.branchName || d.branch);
    if (!br) continue;
    const key = normBranch(br);
    if (!byBranch.has(key)) byBranch.set(key, { branch: br, gifts: new Map() });
    const m = byBranch.get(key).gifts;
    const add = (k, q) => { k = s(k).toLowerCase(); if (k) m.set(k, (m.get(k) || 0) + q); };
    const cg = Array.isArray(d.claimed_gifts) ? d.claimed_gifts : [];
    if (cg.length) {
      for (const g of cg) {
        if (!g || typeof g !== "object") continue;
        const q = Math.trunc(Number(g.quantity ?? g.count ?? 1)) || 0;
        add(g.giftId || g.gift_id, q); add(g.giftName || g.name, q);
      }
    } else {
      const lg = Array.isArray(d.linkedGifts) ? d.linkedGifts : (Array.isArray(d.linked_gifts) ? d.linked_gifts : []);
      for (const g of lg) {
        if (!g || typeof g !== "object") continue;
        const q = Math.trunc(Number(g.quantity ?? 1)) || 0;
        add(g.giftId || g.gift_id, q); add(g.giftName || g.name, q);
      }
      for (const pw of Array.isArray(d.prizes_won) ? d.prizes_won : []) add(pw, 1);
      const one = s(d.prize_won || d.prizeName);
      if (one && one !== "null" && one !== "لم يفز") add(one, 1);
    }
  }
  return [...byBranch.values()];
}

/** Handed-out quantity of one branch prize, same lookup as the screen. */
function handedOutFor(handed, p) {
  const id = s(p.giftId).toLowerCase(), name = s(p.name).toLowerCase();
  let total = 0;
  for (const b of handed) {
    if (!branchMatches(b.branch, p.branchName)) continue;
    const g = b.gifts;
    if (id && g.has(id)) total += g.get(id);
    else if (name && g.has(name)) total += g.get(name);
    else if (name) for (const [k, v] of g) if (k.includes(name) || name.includes(k)) total += v;
  }
  return total;
}

/**
 * Only rows the caller actually changed are validated. A changed row is
 * rejected only when its new allocation is below the quantity really handed
 * out (receipts, as on the screen), or when it would erase handed-out stock
 * (allocated - remaining below what is provably handed out). Untouched rows
 * with old inconsistent data are returned as warnings instead of blocking.
 * `handed` null = no receipt data: fall back to the stored consumed amount.
 */
function assertConsumedKept(oldPrizes, newPrizes, handed = null) {
  const old = new Map();
  for (const p of oldPrizes || []) {
    if (!p || !s(p.branchName)) continue;
    if (!old.has(prizeKey(p))) old.set(prizeKey(p), p);
  }
  const warnings = [];
  for (const p of newPrizes) {
    if (!s(p.branchName)) continue;
    const o = old.get(prizeKey(p));
    const oAlloc = o ? Number(o.allocatedQuantity) || 0 : 0;
    const oRem = o ? Number(o.remainingQuantity) || 0 : 0;
    const stored = Math.max(oAlloc - oRem, 0);
    const real = handed ? handedOutFor(handed, p) : stored;
    const unchanged = o && oAlloc === p.allocatedQuantity && oRem === p.remainingQuantity;
    if (unchanged) {
      if (p.allocatedQuantity < real) warnings.push({ branchName: p.branchName, name: p.name, allocated: p.allocatedQuantity, handedOut: real });
      continue;
    }
    if (p.allocatedQuantity < real) {
      throw new HttpsError("failed-precondition",
        `لا يمكن تعيين رصيد فرع (${p.branchName}) لصنف (${p.name}) أقل من المنصرف (${real} قطعة)`);
    }
    if (p.allocatedQuantity - p.remainingQuantity < Math.min(stored, real)) {
      throw new HttpsError("failed-precondition",
        `لا يمكن زيادة المتبقي لفرع (${p.branchName}) لصنف (${p.name}) بما يمحو المنصرف (${Math.min(stored, real)} قطعة)`);
    }
  }
  return warnings;
}

async function loadHandedOut(db, eventId) {
  const [a, b, st] = await Promise.all([
    db.collection("receipts_transactions").where("campaignId", "==", eventId).get(),
    db.collection("receipts_transactions").where("event_id", "==", eventId).get(),
    db.collection("campaign_stock_settlements").where("eventId", "==", eventId).get(),
  ]);
  const seen = new Set(); const docs = [];
  for (const d of [...a.docs, ...b.docs]) if (!seen.has(d.id)) { seen.add(d.id); docs.push(d.data()); }
  let cutoff = 0;
  for (const d of st.docs) {
    const t = d.get("settledAt"); const ms = t && typeof t.toMillis === "function" ? t.toMillis() : 0;
    if (ms > cutoff) cutoff = ms;
  }
  return buildHandedOut(docs, cutoff);
}

function cleanMovement(m, slug, types, performedBy) {
  if (!m || typeof m !== "object") throw bad("movement is invalid.");
  const type = str(m.movementType, 60, "movementType");
  if (!types.has(type)) throw bad("movementType is not allowed.");
  return {
    companySlug: slug,
    giftId: str(m.giftId, 200, "giftId"),
    giftName: str(m.giftName, 300, "giftName"),
    movementType: type,
    quantityChange: int(m.quantityChange, "quantityChange"),
    previousTotal: int(m.previousTotal, "previousTotal"),
    newTotal: int(m.newTotal, "newTotal"),
    previousAvailable: int(m.previousAvailable, "previousAvailable"),
    newAvailable: int(m.newAvailable, "newAvailable"),
    reference: str(m.reference, 500, "reference"),
    notes: str(m.notes, 1000, "notes"),
    performedBy: str(m.performedBy, 200, "performedBy") || performedBy,
    timestamp: Timestamp.now(),
  };
}

/** Caller must be staff, or a partner with ops access to this company. */
function authorize(request, slug) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const t = request.auth.token || {};
  const provider = t.firebase && t.firebase.sign_in_provider;
  if (provider === "anonymous") throw new HttpsError("permission-denied", "Not allowed.");
  const role = s(t.role);
  if (role === "admin" || role === "super_admin") return;
  if (role === "partner" && s(t.companySlug).toLowerCase() === slug && s(t.partnerAccess) === "ops") return;
  throw new HttpsError("permission-denied", "ليس لديك صلاحية تعديل أرصدة هذه الشركة.");
}

/** Same as CompanyGiftsService.syncCompanyGiftsAvailableQuantities on the client. */
async function syncAvailable(db, slug) {
  const [giftsSnap, eventsSnap] = await Promise.all([
    db.collection("company_gifts").where("companySlug", "==", slug).get(),
    db.collection("events").where("companySlug", "==", slug).where("isActive", "==", true).get(),
  ]);
  if (giftsSnap.empty) return;
  const used = new Map();
  for (const ev of eventsSnap.docs) {
    for (const p of ev.get("allocatedPrizes") || []) {
      if (!p || typeof p !== "object") continue;
      const q = Math.trunc(Number(p.allocatedQuantity) || 0);
      const id = typeof p.giftId === "string" ? p.giftId : "";
      const name = s(p.name);
      if (id) used.set(id, (used.get(id) || 0) + q);
      if (name) used.set(name, (used.get(name) || 0) + q);
    }
  }
  const batch = db.batch();
  for (const g of giftsSnap.docs) {
    const total = Math.trunc(Number(g.get("totalQuantity")) || 0);
    const others = used.get(g.id) ?? used.get(s(g.get("giftName"))) ?? 0;
    batch.update(g.ref, { availableQuantity: Math.min(Math.max(total - others, 0), total) });
  }
  await batch.commit();
}

async function bulk(db, data, slug, performedBy) {
  const events = data.events;
  if (!Array.isArray(events) || events.length === 0 || events.length > MAX_EVENTS) throw bad("events is invalid.");
  const movements = Array.isArray(data.movements) ? data.movements : [];
  if (movements.length > MAX_MOVEMENTS) throw bad("too many movements.");
  const cleanMoves = movements.map((m) => cleanMovement(m, slug, BULK_TYPES, performedBy));
  const items = events.map((e, i) => {
    const eventId = str(e && e.eventId, 128, `events[${i}].eventId`);
    if (!eventId || eventId.includes("/")) throw bad("eventId is invalid.");
    const prizes = cleanPrizes(e.allocatedPrizes);
    let branchNames = null;
    if (e.branchNames !== undefined && e.branchNames !== null) {
      if (!Array.isArray(e.branchNames) || e.branchNames.length > 1000) throw bad("branchNames is invalid.");
      branchNames = e.branchNames.map((b) => str(b, 300, "branchNames"));
    }
    return { eventId, prizes, branchNames };
  });

  const handedList = await Promise.all(items.map((it) => loadHandedOut(db, it.eventId)));
  const warnings = [];
  await db.runTransaction(async (tx) => {
    const refs = items.map((it) => db.collection("events").doc(it.eventId));
    const snaps = await Promise.all(refs.map((r) => tx.get(r)));
    snaps.forEach((snap, i) => {
      if (!snap.exists) throw new HttpsError("not-found", "الحملة غير موجودة.");
      if (s(snap.get("companySlug")).toLowerCase() !== slug) {
        throw new HttpsError("permission-denied", "الحملة لا تتبع هذه الشركة.");
      }
      warnings.push(...assertConsumedKept(snap.get("allocatedPrizes"), items[i].prizes, handedList[i]));
    });
    items.forEach((it, i) => {
      const patch = { allocatedPrizes: it.prizes };
      if (it.branchNames && it.branchNames.length) patch.branchNames = it.branchNames;
      tx.update(refs[i], patch);
    });
    for (const m of cleanMoves) tx.set(db.collection("gift_stock_movements").doc(), m);
  });
  await syncAvailable(db, slug).catch(() => {});
  return { ok: true, updatedEvents: items.length, movements: cleanMoves.length, warnings: warnings.slice(0, 100) };
}

async function settlement(db, data, slug, performedBy) {
  const eventId = str(data.eventId, 128, "eventId");
  if (!eventId || eventId.includes("/")) throw bad("eventId is invalid.");
  const prizes = cleanPrizes(data.allocatedPrizes);
  const st = data.settlement || {};
  const snapshots = st.branchSnapshots;
  if (!snapshots || typeof snapshots !== "object" || Array.isArray(snapshots)) throw bad("branchSnapshots is invalid.");
  if (JSON.stringify(snapshots).length > 500000) throw bad("branchSnapshots is too large.");
  const eventRef = db.collection("events").doc(eventId);
  const settlementRef = db.collection("campaign_stock_settlements").doc();
  const movement = cleanMovement({ ...(data.movement || {}), reference: settlementRef.id },
    slug, new Set(["settlement_cycle"]), performedBy);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(eventRef);
    if (!snap.exists) throw new HttpsError("not-found", "الفعالية غير موجودة في قاعدة البيانات");
    if (s(snap.get("companySlug")).toLowerCase() !== slug) {
      throw new HttpsError("permission-denied", "الحملة لا تتبع هذه الشركة.");
    }
    tx.set(settlementRef, {
      campaignId: eventId,
      campaignName: str(st.campaignName, 300, "campaignName") || s(snap.get("eventName")),
      companySlug: slug,
      cycleTitle: str(st.cycleTitle, 300, "cycleTitle").trim() || "تسوية دورة الويك إند",
      settledAt: FieldValue.serverTimestamp(),
      settledBy: str(st.settledBy, 200, "settledBy") || performedBy,
      totalAllocatedBefore: int(st.totalAllocatedBefore, "totalAllocatedBefore", { min: 0 }),
      totalClaimed: int(st.totalClaimed, "totalClaimed", { min: 0 }),
      totalReturned: int(st.totalReturned, "totalReturned", { min: 0 }),
      newAllocatedStock: int(st.newAllocatedStock, "newAllocatedStock", { min: 0 }),
      branchSnapshots: snapshots,
    });
    tx.update(eventRef, {
      allocatedPrizes: prizes,
      lastSettlementId: settlementRef.id,
      lastSettledAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.collection("gift_stock_movements").doc(), movement);
  });
  return { ok: true, settlementId: settlementRef.id };
}

async function updateBranchAllocationsHandler(db, request) {
  const data = request.data || {};
  const slug = s(data.companySlug).toLowerCase();
  if (!slug || slug.length > 128 || slug.includes("/")) throw bad("companySlug is required.");
  authorize(request, slug);
  try {
    await consumeRateLimit({ db, scope: "branchAlloc", key: clientKey({ uid: request.auth.uid, rawRequest: request.rawRequest }) });
  } catch (e) {
    if (e instanceof RateLimitError) throw new HttpsError("resource-exhausted", e.message);
    throw e;
  }
  const performedBy = s(request.auth.token.email) || "مشرف شركة الدعاية / العمليات";
  const action = s(data.action);
  if (action === "bulk") return bulk(db, data, slug, performedBy);
  if (action === "settlement") return settlement(db, data, slug, performedBy);
  throw bad("action is invalid.");
}

module.exports = { updateBranchAllocationsHandler, _test: { cleanPrize, assertConsumedKept, authorize, buildHandedOut } };
