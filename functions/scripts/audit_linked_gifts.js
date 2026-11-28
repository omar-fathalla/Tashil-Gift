#!/usr/bin/env node
/**
 * TAG-40 READ-ONLY report: tier gift links (promotionalRules[].linkedGifts and
 * the legacy linkedGiftId) that point at a gift missing from the company's
 * company_gifts. It writes nothing. Any cleanup on production needs Mohamed's
 * approval; opening and saving a campaign in the editor already cleans it.
 *
 *   node scripts/audit_linked_gifts.js --project <projectId> [--all]
 *
 * Default: active campaigns only (--all for every campaign). Uses Application
 * Default Credentials, or FIRESTORE_EMULATOR_HOST for an emulator.
 */
const admin = require("../admin_sdk");

function arg(name) {
  return process.argv.includes(`--${name}`);
}

function deadLinks(event, giftsById, giftNames) {
  const out = [];
  const rules = Array.isArray(event.promotionalRules) ? event.promotionalRules : [];
  for (const rule of rules) {
    if (!rule || typeof rule !== "object") continue;
    for (const lg of Array.isArray(rule.linkedGifts) ? rule.linkedGifts : []) {
      const id = String((lg && lg.giftId) || "");
      if (giftsById.has(id)) continue;
      const name = String((lg && lg.giftName) || "");
      out.push({ rule: rule.id || rule.ruleTitle || "?", giftId: id, giftName: name, fixableByName: giftNames.get(name) === 1 });
    }
    const legacy = String(rule.linkedGiftId || "");
    if (legacy && !giftsById.has(legacy)) {
      out.push({ rule: rule.id || rule.ruleTitle || "?", giftId: legacy, giftName: String(rule.linkedGiftName || ""), legacy: true,
        fixableByName: giftNames.get(String(rule.linkedGiftName || "")) === 1 });
    }
  }
  return out;
}

async function main() {
  const i = process.argv.indexOf("--project");
  const projectId = i >= 0 ? process.argv[i + 1] : undefined;
  if (!projectId && !process.env.FIRESTORE_EMULATOR_HOST) {
    console.error("usage: node scripts/audit_linked_gifts.js --project <projectId> [--all]");
    process.exit(2);
  }
  if (!admin.apps.length) admin.initializeApp(projectId ? { projectId } : {});
  const db = admin.firestore();
  const query = arg("all") ? db.collection("events") : db.collection("events").where("isActive", "==", true);
  const events = await query.get();
  const giftsBySlug = new Map();
  let total = 0;
  for (const doc of events.docs) {
    const e = doc.data() || {};
    const slug = String(e.companySlug || "").trim().toLowerCase();
    if (!giftsBySlug.has(slug)) {
      const snap = await db.collection("company_gifts").where("companySlug", "==", slug).get();
      const byId = new Set(snap.docs.map((d) => d.id));
      const names = new Map();
      for (const d of snap.docs) {
        const n = String((d.data() || {}).giftName || "");
        names.set(n, (names.get(n) || 0) + 1);
      }
      giftsBySlug.set(slug, { byId, names });
    }
    const { byId, names } = giftsBySlug.get(slug);
    const dead = deadLinks(e, byId, names);
    if (!dead.length) continue;
    total += dead.length;
    console.log(`${doc.id}  ${e.eventName || ""}  (${slug})  dead links: ${dead.length}`);
    for (const d of dead) console.log(`   rule ${d.rule}: ${d.giftId} «${d.giftName}»${d.legacy ? " [legacy]" : ""}${d.fixableByName ? " -> re-pointed by name on next save" : " -> removed on next save"}`);
  }
  console.log(`\n${events.size} campaign(s) checked, ${total} dead link(s). Nothing was written.`);
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}

module.exports = { deadLinks };
