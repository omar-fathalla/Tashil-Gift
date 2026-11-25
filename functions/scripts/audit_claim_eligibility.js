#!/usr/bin/env node
/**
 * READ-ONLY audit: which active campaigns would start rejecting claims that are
 * accepted today under the server-side eligibility check, and which the daily
 * auto-close would close.
 *
 *   node scripts/audit_claim_eligibility.js --project <projectId> [--limit 300]
 *
 * It only reads (events where isActive == true, and each campaign's receipts).
 * It writes nothing and never calls a function. Against a live project it uses
 * Application Default Credentials; set FIRESTORE_EMULATOR_HOST to audit an
 * emulator. Each already-claimed receipt is replayed at its own upload time.
 */
const admin = require("../admin_sdk");
const { evaluateClaimEligibility, isCampaignEnded, campaignWindow, toMillis } = require("../campaign_eligibility");
const { withCampaignContent } = require("../campaign_content");

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

function wasClaimed(receipt) {
  const prize = receipt.prize_won == null ? "" : String(receipt.prize_won).trim();
  return receipt.game_played === true || (Array.isArray(receipt.claimed_gifts) && receipt.claimed_gifts.length > 0) ||
    (prize !== "" && prize !== "null");
}

function configNotes(event, nowMs) {
  const notes = [];
  const rules = Array.isArray(event.promotionalRules) ? event.promotionalRules : [];
  if (isCampaignEnded(event, nowMs)) notes.push("ended: the daily auto-close will set isActive=false");
  const w = campaignWindow(event);
  if (w.opensAtMs != null && nowMs < w.opensAtMs) notes.push("not started yet: claims are rejected until the start day");
  if (rules.some((r) => r && r.conditionType === "combo_spend")) notes.push("combo rule: gift count not recomputed (cap and chances_earned only)");
  if (rules.some((r) => r && r.conditionType === "by_quantity")) notes.push("quantity rule: loose upper bound only");
  if (event.spendLadderMode === "consuming") notes.push("consuming ladder: rounds already server-planned; date, minimum and product checks added");
  if (Array.isArray(event.requiredProducts) && event.requiredProducts.length) notes.push("requiredProducts: needs an explicit name or barcode match on the invoice lines");
  return notes;
}

async function main() {
  const project = arg("project", "");
  if (!project) throw new Error("--project is required");
  const limit = Math.max(1, Math.min(2000, Number(arg("limit", "300")) || 300));
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();
  const nowMs = Date.now();
  const events = await db.collection("events").where("isActive", "==", true).get();
  const report = [];
  for (const doc of events.docs) {
    const event = await withCampaignContent(db, doc.id, doc.data() || {}); // TAG-51
    const receipts = await db.collection("receipts_transactions").where("campaignId", "==", doc.id).limit(limit).get();
    const byReason = {};
    const samples = [];
    let claimed = 0;
    let wouldReject = 0;
    for (const rdoc of receipts.docs) {
      const receipt = rdoc.data() || {};
      if (!wasClaimed(receipt)) continue;
      claimed += 1;
      const at = toMillis(receipt.timestamp) != null ? toMillis(receipt.timestamp) : nowMs;
      const verdict = evaluateClaimEligibility({ event: Object.assign({}, event, { isActive: true }), receipt, nowMs: at, system: receipt.source === "waha_webhook" });
      if (!verdict.ok) {
        wouldReject += 1;
        byReason[verdict.code] = (byReason[verdict.code] || 0) + 1;
        if (samples.length < 5) samples.push({ receiptId: rdoc.id, reason: verdict.code });
      }
    }
    report.push({
      eventId: doc.id,
      eventName: event.eventName || "",
      companySlug: event.companySlug || "",
      endDate: toMillis(event.endDate) == null ? null : new Date(toMillis(event.endDate)).toISOString(),
      spendLadderMode: event.spendLadderMode || "exclusive",
      scannedReceipts: receipts.size,
      claimedReceiptsReplayed: claimed,
      wouldReject,
      byReason,
      samples,
      notes: configNotes(event, nowMs),
    });
  }
  console.log(JSON.stringify({ project, generatedAt: new Date(nowMs).toISOString(), activeCampaigns: report.length, report }, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
