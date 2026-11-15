"use strict";

/**
 * Daily end-date auto-close.
 *
 * Sets isActive=false (plus updatedAt and updatedBy='system:auto-close') on
 * campaigns whose end date has passed, using the same cutoff as the client:
 * Cairo 00:00 of the day after the end day. It never looks at gift or stock
 * levels: a campaign that is out of stock but still in date stays active.
 *
 * Idempotent: closed campaigns are not selected again, and every candidate is
 * re-read inside a transaction, so a campaign an admin has just re-opened or
 * extended is left alone.
 */
const admin = require("./admin_sdk");
const { isCampaignEnded, toMillis } = require("./campaign_eligibility");

const AUTO_CLOSE_ACTOR = "system:auto-close";

function describe(id, data) {
  const endMs = toMillis(data && data.endDate);
  return {
    eventId: id,
    eventName: String((data && data.eventName) || "").slice(0, 160),
    companySlug: String((data && data.companySlug) || ""),
    endDate: endMs == null ? null : new Date(endMs).toISOString(),
  };
}

async function autoCloseExpiredCampaigns(db, options) {
  const nowMs = options && Number.isFinite(options.nowMs) ? options.nowMs : Date.now();
  const log = (options && options.log) || ((line) => console.log(JSON.stringify(line)));
  const stamp = (options && options.serverTimestamp) || (() => admin.firestore.FieldValue.serverTimestamp());

  // endDate is stored at Cairo 00:00 of the last day, so "endDate <= now" is a
  // superset of the expired set; the exact cutoff is applied per document.
  const snap = await db.collection("events")
    .where("isActive", "==", true)
    .where("endDate", "<=", admin.firestore.Timestamp.fromMillis(nowMs))
    .get();

  const closed = [];
  let skipped = 0;
  for (const doc of snap.docs) {
    const outcome = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const data = fresh.exists ? (fresh.data() || {}) : null;
      if (!data || data.isActive !== true || !isCampaignEnded(data, nowMs)) return null;
      tx.update(doc.ref, { isActive: false, updatedAt: stamp(), updatedBy: AUTO_CLOSE_ACTOR });
      return describe(doc.id, data);
    });
    if (outcome) {
      closed.push(outcome);
      log({ severity: "INFO", fn: "autoCloseExpiredCampaigns", action: "closed", ...outcome });
    } else {
      skipped += 1;
    }
  }
  log({
    severity: "INFO",
    fn: "autoCloseExpiredCampaigns",
    action: "summary",
    scanned: snap.size,
    closed: closed.length,
    skipped,
    closedIds: closed.map((c) => c.eventId),
  });
  return { scanned: snap.size, closed, skipped };
}

module.exports = { autoCloseExpiredCampaigns, AUTO_CLOSE_ACTOR };
