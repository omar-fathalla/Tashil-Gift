#!/usr/bin/env node
/**
 * TAG-62 phase 2 tool: move campaign products / AI prompt to
 * events/{id}/content. DRY-RUN by default: it only reads and prints a report
 * (every campaign, its size before and after, and what would change).
 *
 *   # report only (default)
 *   node scripts/migrate_campaign_content.js --project <projectId> [--event <id>]
 *   # write, emulator / demo- project
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/migrate_campaign_content.js --project demo-x --apply
 *
 * Writing to a real (non demo-) project also needs --approved-by "<name>"
 * and must only be run after Mohamed approved phase 2.
 *
 * Idempotent: a campaign whose content docs already match is skipped.
 * Small campaigns (products + prompt <= 256KB) keep their inline fields
 * (written in both places). Large ones get their inline fields copied to
 * events/{id}/content/legacy_backup first, then removed from the campaign doc,
 * all in one batch per campaign.
 */
const admin = require("../admin_sdk");
const { withCampaignContent, planContentWrite, bytes } = require("../campaign_content");

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--") ? process.argv[i + 1] : fallback;
}
const flag = (name) => process.argv.includes(`--${name}`);

const sameList = (a, b) => Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => x === b[i]);

/** What the migration does with one campaign (pure; exported for tests). */
function planCampaign(eventId, data, stored) {
  const products = Array.isArray(stored.requiredProducts) ? stored.requiredProducts.map(String) : [];
  const prompt = typeof stored.customPrompt === "string" ? stored.customPrompt : "";
  const docBytesBefore = bytes(data);
  const hasInline = Object.prototype.hasOwnProperty.call(data, "requiredProducts") ||
    Object.prototype.hasOwnProperty.call(data, "customPrompt");
  const version = (Number(data.contentVersion) || 0) + 1;
  const write = planContentWrite({ products, prompt, version, previousChunks: Number(data.contentChunks) || 0 });
  const after = Object.assign({}, data, write.eventFields);
  for (const k of write.deleteFields) delete after[k];
  const report = {
    eventId,
    eventName: data.eventName || "",
    isActive: data.isActive === true,
    products: products.length,
    productsBytes: bytes(products),
    promptBytes: bytes(prompt),
    docBytesBefore,
    docBytesAfter: bytes(after),
    contentDocs: Object.keys(write.docs).length,
  };
  // Already migrated: external and (for a small one) inline copy present.
  const done = data.hasExternalContent === true && Number(data.contentVersion) > 0 &&
    (write.inline ? hasInline : !hasInline);
  report.action = done ? "skip" : write.inline ? "dual-write" : "externalize";
  return { report, write, products, prompt, hasInline };
}

async function contentMatches(db, eventId, products, prompt) {
  try {
    const stored = await withCampaignContent(db, eventId, { hasExternalContent: true }, { prompt: true });
    return sameList(stored.requiredProducts, products) && stored.customPrompt === prompt;
  } catch (_) {
    return false;
  }
}

async function applyCampaign(db, eventId, data, plan) {
  const ref = db.collection("events").doc(eventId);
  const content = ref.collection("content");
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  for (const [id, doc] of Object.entries(plan.write.docs)) batch.set(content.doc(id), Object.assign({}, doc, { updatedAt: ts }));
  for (const id of plan.write.deletes) batch.delete(content.doc(id));
  const patch = Object.assign({}, plan.write.eventFields);
  if (!plan.write.inline && plan.hasInline) {
    batch.set(content.doc("legacy_backup"), {
      requiredProducts: Array.isArray(data.requiredProducts) ? data.requiredProducts : null,
      customPrompt: typeof data.customPrompt === "string" ? data.customPrompt : null,
      backedUpAt: ts,
    });
  }
  for (const k of plan.write.deleteFields) patch[k] = admin.firestore.FieldValue.delete();
  batch.update(ref, patch);
  await batch.commit();
}

async function main() {
  const project = arg("project", "");
  if (!project) throw new Error("--project is required");
  const apply = flag("apply");
  const emulator = !!process.env.FIRESTORE_EMULATOR_HOST;
  if (apply && !project.startsWith("demo-")) {
    const approvedBy = arg("approved-by", "");
    if (!approvedBy) throw new Error("--apply on a real project needs --approved-by \"<name>\" (phase 2 approval)");
    if (emulator) throw new Error("FIRESTORE_EMULATOR_HOST is set but the project is not demo-; refusing");
  }
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();
  const only = arg("event", "");
  const docs = only ? [await db.collection("events").doc(only).get()] : (await db.collection("events").get()).docs;
  const report = [];
  for (const doc of docs) {
    if (!doc.exists) continue;
    const data = doc.data() || {};
    let stored;
    try {
      stored = await withCampaignContent(db, doc.id, data, { prompt: true });
    } catch (e) {
      report.push({ eventId: doc.id, action: "error", error: e.message });
      continue;
    }
    const plan = planCampaign(doc.id, data, stored);
    if (plan.report.action === "skip" && !(await contentMatches(db, doc.id, plan.products, plan.prompt))) {
      plan.report.action = plan.write.inline ? "dual-write" : "externalize";
      plan.report.note = "content docs differ from the campaign; rewriting";
    }
    if (apply && plan.report.action !== "skip") {
      await applyCampaign(db, doc.id, data, plan);
      plan.report.applied = true;
    }
    report.push(plan.report);
  }
  console.log(JSON.stringify({ project, mode: apply ? "apply" : "dry-run", campaigns: report.length, report }, null, 2));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}

module.exports = { planCampaign };
