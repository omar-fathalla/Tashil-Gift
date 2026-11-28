"use strict";

/**
 * Daily start-date auto-activate (TAG-18).
 *
 * Turns on (isActive=true, statusUpdatedAt, statusUpdatedBy='system:auto-activate')
 * campaigns that are off, were NOT stopped by an admin (pausedManually !== true),
 * and whose Cairo window covers now: Cairo 00:00 of the start day up to (not
 * including) Cairo 00:00 of the day after the end day, the same window the
 * claim check and auto-close use. Campaigns without both dates are never
 * touched, so an open-ended campaign is never switched on by the system.
 *
 * The query is a single-field equality (isActive == false), which needs no
 * composite index; the dates are checked in code. Every candidate is re-read
 * inside its own transaction, so a campaign an admin has just paused, edited or
 * turned on is left alone. Idempotent: an activated campaign is not selected
 * again. Writes run in small parallel batches.
 */
const admin = require("./admin_sdk");
const { campaignWindow, toMillis } = require("./campaign_eligibility");

const AUTO_ACTIVATE_ACTOR = "system:auto-activate";
const BATCH_SIZE = 10;

/** Why a stored campaign is (not) eligible for auto-activation at nowMs. */
function activationVerdict(data, nowMs) {
  if (!data) return "missing";
  if (data.isActive === true) return "already_active";
  if (data.pausedManually === true) return "paused_manually";
  if (toMillis(data.startDate) == null || toMillis(data.endDate) == null) return "missing_dates";
  const { opensAtMs, cutoffMs } = campaignWindow(data);
  if (nowMs < opensAtMs) return "not_started";
  if (nowMs >= cutoffMs) return "ended";
  return "eligible";
}

function describe(id, data) {
  const iso = (v) => {
    const ms = toMillis(v);
    return ms == null ? null : new Date(ms).toISOString();
  };
  return {
    eventId: id,
    eventName: String((data && data.eventName) || "").slice(0, 160),
    companySlug: String((data && data.companySlug) || ""),
    startDate: iso(data && data.startDate),
    endDate: iso(data && data.endDate),
  };
}

async function autoActivateCampaigns(db, options) {
  const nowMs = options && Number.isFinite(options.nowMs) ? options.nowMs : Date.now();
  const log = (options && options.log) || ((line) => console.log(JSON.stringify(line)));
  const stamp = (options && options.serverTimestamp) || (() => admin.firestore.FieldValue.serverTimestamp());
  const batchSize = (options && options.batchSize) || BATCH_SIZE;

  const snap = await db.collection("events").where("isActive", "==", false).get();
  const candidates = snap.docs.filter((doc) => activationVerdict(doc.data() || {}, nowMs) === "eligible");

  const activated = [];
  let skipped = 0;
  for (let i = 0; i < candidates.length; i += batchSize) {
    const chunk = candidates.slice(i, i + batchSize);
    const outcomes = await Promise.all(chunk.map((doc) => db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const data = fresh.exists ? (fresh.data() || {}) : null;
      if (activationVerdict(data, nowMs) !== "eligible") return null;
      tx.update(doc.ref, { isActive: true, statusUpdatedAt: stamp(), statusUpdatedBy: AUTO_ACTIVATE_ACTOR });
      return describe(doc.id, data);
    })));
    for (const outcome of outcomes) {
      if (outcome) {
        activated.push(outcome);
        log({ severity: "INFO", fn: "autoActivateCampaigns", action: "activated", ...outcome });
      } else {
        skipped += 1;
      }
    }
  }
  log({
    severity: "INFO",
    fn: "autoActivateCampaigns",
    action: "summary",
    scanned: snap.size,
    candidates: candidates.length,
    activated: activated.length,
    skipped,
    activatedIds: activated.map((c) => c.eventId),
  });
  return { scanned: snap.size, activated, skipped };
}

module.exports = { autoActivateCampaigns, activationVerdict, AUTO_ACTIVATE_ACTOR };
