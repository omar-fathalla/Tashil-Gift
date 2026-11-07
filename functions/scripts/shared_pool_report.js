#!/usr/bin/env node
/**
 * 2.0.148+206 shared prize pool — READ-ONLY report. NOT run automatically.
 * No data movement is required by the shared-pool design; this lists, per
 * company, active campaigns without stock rows and which sibling rows would
 * feed them. Optional --backup <file> writes a JSON copy of every company
 * campaign's allocatedPrizes (local file only, no Firestore writes).
 *   node scripts/shared_pool_report.js [--company 583] [--backup out.json]
 */
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const fs = require("fs");

const arg = (k) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : null; };
initializeApp({ projectId: "tashil-gift" });
const db = getFirestore();

(async () => {
  const company = arg("--company");
  let q = db.collection("events");
  if (company) q = q.where("companySlug", "==", company);
  const snap = await q.get();
  const byCompany = new Map();
  const backup = {};
  snap.forEach((d) => {
    const x = d.data() || {};
    const slug = String(x.companySlug || "");
    if (!byCompany.has(slug)) byCompany.set(slug, []);
    byCompany.get(slug).push({ id: d.id, name: x.eventName, active: x.isActive === true,
      mode: x.balanceMode || "", rows: Array.isArray(x.allocatedPrizes) ? x.allocatedPrizes : [] });
    backup[d.id] = { companySlug: slug, allocatedPrizes: x.allocatedPrizes || [] };
  });
  for (const [slug, evs] of byCompany) {
    for (const e of evs.filter((v) => v.active && v.rows.length === 0 && v.mode !== "campaign_only")) {
      const feeders = evs.filter((v) => v.id !== e.id && v.active && v.mode !== "campaign_only" && v.rows.length > 0);
      console.log(`company ${slug}: ${e.id} "${e.name}" -> shared pool from ${feeders.map((f) => `${f.id} (${f.rows.length} rows)`).join(", ") || "NONE"}`);
    }
  }
  const out = arg("--backup");
  if (out) { fs.writeFileSync(out, JSON.stringify(backup, null, 2)); console.log("backup written:", out); }
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
