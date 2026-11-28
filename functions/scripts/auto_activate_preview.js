#!/usr/bin/env node
/**
 * TAG-18: which campaigns the daily auto-activate would turn on, and (only
 * with --apply and explicit ids) mark chosen ones as paused by an admin so it
 * leaves them off.
 *
 *   READ-ONLY (default):
 *     node scripts/auto_activate_preview.js --project <projectId> [--at <ISO time>]
 *   WRITE (needs the owner's explicit approval for production):
 *     node scripts/auto_activate_preview.js --project <projectId> --mark-paused <id1,id2> --apply
 *
 * The preview prints name, company, Cairo first/last day and branch count; no
 * customer data. --mark-paused without --apply only prints what it would do.
 * Uses Application Default Credentials, or FIRESTORE_EMULATOR_HOST.
 */
const admin = require("../admin_sdk");
const { activationVerdict } = require("../auto_activate_campaigns");
const { toMillis } = require("../campaign_eligibility");

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const cairoDay = (v) => {
  const ms = toMillis(v);
  return ms == null ? "-" : new Intl.DateTimeFormat("en-GB", { timeZone: "Africa/Cairo" }).format(new Date(ms));
};

async function main() {
  const project = arg("project", "");
  if (!project) throw new Error("--project is required");
  const at = arg("at", "");
  const nowMs = at ? Date.parse(at) : Date.now();
  if (!Number.isFinite(nowMs)) throw new Error("--at must be an ISO time");
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();

  const snap = await db.collection("events").where("isActive", "==", false).get();
  const eligible = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (activationVerdict(d, nowMs) !== "eligible") continue;
    eligible.push({
      id: doc.id,
      name: String(d.eventName || ""),
      company: String(d.targetCompany || d.companySlug || ""),
      firstDay: cairoDay(d.startDate),
      lastDay: cairoDay(d.endDate),
      branches: d.isAllBranches === true ? "all" : (Array.isArray(d.branchNames) ? d.branchNames.length : 0),
    });
  }
  console.log(JSON.stringify({ at: new Date(nowMs).toISOString(), wouldActivate: eligible }, null, 2));

  const mark = arg("mark-paused", "");
  if (!mark) return;
  const ids = mark.split(",").map((s) => s.trim()).filter(Boolean);
  const apply = process.argv.includes("--apply");
  for (const id of ids) {
    const ref = db.collection("events").doc(id);
    const fresh = await ref.get();
    if (!fresh.exists) { console.log(`skip ${id}: not found`); continue; }
    if (fresh.get("isActive") === true) { console.log(`skip ${id}: already active`); continue; }
    if (!apply) { console.log(`would mark paused: ${id} (${fresh.get("eventName")})`); continue; }
    await ref.update({
      pausedManually: true,
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedBy: "system:tag18-backfill",
    });
    console.log(`marked paused: ${id}`);
  }
}

main().catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
