#!/usr/bin/env node
/**
 * TAG-56: copy each campaign's requiredProducts / customPrompt into
 * events/{id}/content chunks and set the content pointer on the campaign.
 *
 *   node scripts/migrate_campaign_content.js --project <id> [--event <eventId>] [--min-bytes 0] [--apply]
 *
 * Default is a DRY RUN: it reads and prints what it would write, nothing else.
 * --apply writes the chunks and the pointer only. The legacy fields stay on
 * the campaign document (cleanup is a separate, later phase). Re-running is
 * safe: a campaign whose chunks already match its legacy fields is skipped.
 *
 * Phase 1 safety: --apply runs ONLY against the Firestore emulator
 * (FIRESTORE_EMULATOR_HOST set) and on a demo- project; it refuses anything
 * else, production (tashil-gift) included.
 */
const admin = require("../admin_sdk");
const {
  SUBCOLLECTION,
  contentPointer,
  assembleContent,
  contentBytes,
  planContentWrites,
} = require("../campaign_content");

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--") ? process.argv[i + 1] : fallback;
}
const flag = (name) => process.argv.includes(`--${name}`);

function legacyOf(data) {
  return {
    products: Array.isArray(data.requiredProducts) ? data.requiredProducts.map(String) : [],
    prompt: typeof data.customPrompt === "string" ? data.customPrompt : "",
  };
}

function sameContent(a, b) {
  return a.prompt === b.prompt && a.products.length === b.products.length && a.products.every((p, i) => p === b.products[i]);
}

/** Plan for one campaign: { action: "skip" | "migrate", reason, ... }. */
async function planCampaign(db, doc) {
  const data = doc.data() || {};
  const legacy = legacyOf(data);
  const docBytes = Buffer.byteLength(JSON.stringify(data), "utf8");
  const base = { id: doc.id, name: String(data.eventName || ""), docBytes, products: legacy.products.length, promptChars: legacy.prompt.length };
  if (!legacy.products.length && !legacy.prompt) return Object.assign(base, { action: "skip", reason: "no legacy content" });
  const pointer = contentPointer(data);
  if (pointer) {
    // Once a pointer exists the chunks are the source of truth; only a
    // campaign whose chunks are incomplete is copied again from its legacy fields.
    const snap = await doc.ref.collection(SUBCOLLECTION).get();
    const stored = assembleContent(pointer, new Map(snap.docs.map((d) => [d.id, d.data() || {}])));
    if (stored) {
      return Object.assign(base, { action: "skip", reason: sameContent(stored, legacy) ? "already migrated" : "content managed by the editor" });
    }
  }
  const writes = planContentWrites({ products: legacy.products, prompt: legacy.prompt, previous: pointer, keepLegacy: true, FieldValue: admin.firestore.FieldValue });
  const pointerBytes = 200;
  return Object.assign(base, {
    action: "migrate",
    reason: pointer ? "chunks incomplete" : "legacy campaign",
    chunks: writes.docs.size,
    deletes: writes.deleteIds.length,
    contentBytes: contentBytes(legacy.products, legacy.prompt),
    docBytesAfterCleanup: Math.max(0, docBytes - contentBytes(legacy.products, legacy.prompt)) + pointerBytes,
    writes,
  });
}

async function applyPlan(db, doc, plan) {
  const batch = db.batch();
  const content = doc.ref.collection(SUBCOLLECTION);
  for (const [id, data] of plan.writes.docs) batch.set(content.doc(id), data);
  for (const id of plan.writes.deleteIds) batch.delete(content.doc(id));
  batch.update(doc.ref, plan.writes.eventFields);
  await batch.commit();
}

async function main() {
  const project = arg("project", "");
  if (!project) throw new Error("--project is required");
  const apply = flag("apply");
  if (apply && (!process.env.FIRESTORE_EMULATOR_HOST || !project.startsWith("demo-"))) {
    throw new Error("--apply is allowed only on the Firestore emulator with a demo- project in this phase.");
  }
  const minBytes = Math.max(0, Number(arg("min-bytes", "0")) || 0);
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();
  const eventId = arg("event", "");
  const docs = eventId ? [await db.collection("events").doc(eventId).get()] : (await db.collection("events").get()).docs;
  const report = [];
  for (const doc of docs) {
    if (!doc.exists) continue;
    const plan = await planCampaign(db, doc);
    if (plan.action === "migrate" && plan.docBytes < minBytes) {
      plan.action = "skip";
      plan.reason = `below --min-bytes ${minBytes}`;
    }
    if (apply && plan.action === "migrate") await applyPlan(db, doc, plan);
    const { writes, ...row } = plan;
    report.push(row);
  }
  report.sort((a, b) => b.docBytes - a.docBytes);
  const summary = {
    mode: apply ? "APPLY (emulator)" : "DRY RUN (no writes)",
    project,
    campaigns: report.length,
    toMigrate: report.filter((r) => r.action === "migrate").length,
  };
  console.log(JSON.stringify({ summary, campaigns: report }, null, 2));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}

module.exports = { planCampaign, applyPlan };
