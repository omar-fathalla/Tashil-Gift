#!/usr/bin/env node
/**
 * TAG-51: copy requiredProducts / customPrompt of campaigns into
 * events/{id}/content (layout in ../campaign_content.js).
 *
 * Dry run by default: nothing is written unless --apply is given.
 *
 *   --mode=migrate   write the parts + contentStorage marker from the campaign
 *                    fields. Idempotent: a campaign whose marker already has
 *                    the same revision and whose parts verify is skipped. The
 *                    campaign fields are kept (legacyMirror: true).
 *   --mode=verify    read-only: compare parts with the campaign fields.
 *   --mode=cleanup   remove the campaign fields where the parts verify and set
 *                    legacyMirror: false. Needs --apply AND
 *                    --legacy-readers-retired (only after the phase 3 release
 *                    that writes the parts inside the edit transaction is live).
 *
 * Options: --project=<id> (required), --event=<id> (one campaign),
 *          --min-bytes=<n> (only campaigns whose two fields exceed n bytes).
 *
 * Safety: outside the emulator (FIRESTORE_EMULATOR_HOST unset) the script
 * refuses to run unless --owner-approved=<project> repeats the project id.
 * Running it on production (tashil-gift) needs Mohamed's explicit approval.
 * Credentials come from the environment (ADC); none are stored here.
 */
const { FieldValue } = require("firebase-admin/firestore");
const {
  MARKER_FIELD,
  SUBCOLLECTION,
  legacyProducts,
  legacyPrompt,
  planContent,
  parseMarker,
  partIds,
  assembleContent,
} = require("../campaign_content");

function parseArgs(argv) {
  const out = {};
  for (const a of argv) {
    const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
    if (m) out[m[1]] = m[2] === undefined ? true : m[2];
  }
  return out;
}

function sameContent(a, b) {
  if (!a || !b || a.customPrompt !== b.customPrompt) return false;
  if (a.requiredProducts.length !== b.requiredProducts.length) return false;
  return a.requiredProducts.every((p, i) => p === b.requiredProducts[i]);
}

function contentBytes(data) {
  return Buffer.byteLength(JSON.stringify(legacyProducts(data)), "utf8") + Buffer.byteLength(legacyPrompt(data), "utf8");
}

async function readParts(db, eventId, marker, tx) {
  const col = db.collection("events").doc(eventId).collection(SUBCOLLECTION);
  const refs = partIds(marker).map((id) => col.doc(id));
  const snaps = tx ? await tx.getAll(...refs) : await db.getAll(...refs);
  const parts = {};
  snaps.forEach((s) => { parts[s.id] = s.exists ? s.data() : null; });
  return assembleContent(marker, parts);
}

/** One campaign. Returns {eventId, status, ...}. */
async function processEvent(db, eventId, { mode, apply }) {
  const ref = db.collection("events").doc(eventId);
  if (mode === "verify") {
    const snap = await ref.get();
    const data = snap.data() || {};
    const marker = parseMarker(data[MARKER_FIELD]);
    if (!marker) return { eventId, status: "no-marker", bytes: contentBytes(data) };
    const parts = await readParts(db, eventId, marker);
    if (!parts) return { eventId, status: "parts-invalid", rev: marker.rev };
    if (!marker.legacyMirror) return { eventId, status: "ok-parts-only", rev: marker.rev };
    const legacy = { requiredProducts: legacyProducts(data), customPrompt: legacyPrompt(data) };
    return { eventId, status: sameContent(parts, legacy) ? "ok" : "mismatch", rev: marker.rev };
  }

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { eventId, status: "missing" };
    const data = snap.data() || {};
    const marker = parseMarker(data[MARKER_FIELD]);
    const legacy = { requiredProducts: legacyProducts(data), customPrompt: legacyPrompt(data) };

    if (mode === "migrate") {
      if (marker && !marker.legacyMirror) return { eventId, status: "skip-parts-only", rev: marker.rev };
      const plan = planContent(legacy.requiredProducts, legacy.customPrompt);
      if (marker && marker.rev === plan.marker.rev) {
        const parts = await readParts(db, eventId, marker, tx);
        if (parts && sameContent(parts, legacy)) return { eventId, status: "already-migrated", rev: marker.rev };
      }
      const result = {
        eventId,
        status: apply ? "migrated" : "would-migrate",
        rev: plan.marker.rev,
        products: legacy.requiredProducts.length,
        promptLength: legacy.customPrompt.length,
        parts: Object.keys(plan.parts),
      };
      if (apply) {
        const col = ref.collection(SUBCOLLECTION);
        for (const [id, doc] of Object.entries(plan.parts)) tx.set(col.doc(id), doc);
        tx.update(ref, { [MARKER_FIELD]: Object.assign({}, plan.marker, { migratedAt: FieldValue.serverTimestamp() }) });
      }
      return result;
    }

    if (mode === "cleanup") {
      if (!marker) return { eventId, status: "skip-no-marker" };
      const parts = await readParts(db, eventId, marker, tx);
      if (!parts) return { eventId, status: "skip-parts-invalid", rev: marker.rev };
      if (!marker.legacyMirror) return { eventId, status: "already-clean", rev: marker.rev };
      if (!sameContent(parts, legacy)) return { eventId, status: "skip-mismatch", rev: marker.rev };
      if (apply) {
        tx.update(ref, {
          requiredProducts: FieldValue.delete(),
          customPrompt: FieldValue.delete(),
          [`${MARKER_FIELD}.legacyMirror`]: false,
          [`${MARKER_FIELD}.cleanedAt`]: FieldValue.serverTimestamp(),
        });
      }
      return { eventId, status: apply ? "cleaned" : "would-clean", rev: marker.rev };
    }
    throw new Error(`unknown mode ${mode}`);
  });
}

async function run(db, opts) {
  const { mode = "verify", apply = false, event = null, minBytes = 0 } = opts;
  let ids;
  if (event) {
    ids = [event];
  } else {
    const snap = await db.collection("events").get();
    ids = snap.docs.filter((d) => contentBytes(d.data() || {}) >= minBytes).map((d) => d.id);
  }
  const results = [];
  for (const id of ids) {
    try {
      results.push(await processEvent(db, id, { mode, apply }));
    } catch (e) {
      results.push({ eventId: id, status: "error", error: String(e && e.message) });
    }
  }
  const summary = {};
  for (const r of results) summary[r.status] = (summary[r.status] || 0) + 1;
  return { mode, apply, count: results.length, summary, results };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = String(args.project || "");
  const mode = String(args.mode || "verify");
  const apply = args.apply === true;
  if (!project) throw new Error("--project is required");
  if (!["migrate", "verify", "cleanup"].includes(mode)) throw new Error("--mode must be migrate, verify or cleanup");
  const emulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  if (!emulator && args["owner-approved"] !== project) {
    throw new Error(`Refusing to run on real project "${project}" without --owner-approved=${project} (production needs Mohamed's explicit approval).`);
  }
  if (mode === "cleanup" && apply && args["legacy-readers-retired"] !== true) {
    throw new Error("cleanup --apply needs --legacy-readers-retired (phase 3 release must be live first).");
  }
  const { initializeApp } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  initializeApp({ projectId: project });
  const db = getFirestore();
  const report = await run(db, {
    mode,
    apply,
    event: typeof args.event === "string" ? args.event : null,
    minBytes: Number(args["min-bytes"] || 0) || 0,
  });
  for (const r of report.results) delete r.parts;
  console.log(JSON.stringify(report, null, 2));
  if (!apply && mode !== "verify") console.log("DRY RUN: nothing was written. Add --apply to write.");
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = { run, processEvent, sameContent, contentBytes };
