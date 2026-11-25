// TAG-51 phase 1: rules for events/{id}/content and the whole flow on the
// emulator with a Unilever-sized campaign: migrate (dry run, apply, re-run),
// reads through the rules, admin edit/save as the app does it, claims and the
// AI gateway reading products/prompt, and the later cleanup step.
//
// TAG51_UNILEVER_FIXTURE may point at a local copy of the production campaign
// (Firestore REST JSON, credentials stripped, never committed). Without it a
// synthetic campaign of the same size is used.
const fs = require("fs");
const path = require("path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  getDocs,
  setDoc,
  collection,
  runTransaction,
  serverTimestamp,
  deleteField,
} = require("firebase/firestore");

const content = require("../functions/campaign_content");
const migration = require("../functions/scripts/migrate_campaign_content");
const { getCachedCampaignProducts } = require("../functions/gemini_gateway");
const { evaluateClaimEligibility } = require("../functions/campaign_eligibility");

const PROJECT_ID = "demo-tashil-gift";
const RULES_DIR = path.resolve(__dirname, "..");
const EVENT_ID = "unilever-copy";
let testEnv;
let adminDb; // Admin SDK (functions / migration script side)

const adminCtx = () => testEnv.authenticatedContext("admin-1", { role: "admin", email: "ops@example.com" }).firestore();
const anonCtx = () => testEnv.authenticatedContext("rep-1", { firebase: { sign_in_provider: "anonymous", identities: {} } }).firestore();
const partnerCtx = (slug) => testEnv.authenticatedContext("p-" + slug, { role: "partner", companySlug: slug, partnerAccess: "read" }).firestore();

function fromRest(v) {
  const t = Object.keys(v)[0];
  const x = v[t];
  switch (t) {
    case "stringValue": return x;
    case "booleanValue": return x;
    case "integerValue": return Number(x);
    case "doubleValue": return Number(x);
    case "nullValue": return null;
    case "timestampValue": return new Date(x);
    case "arrayValue": return (x.values || []).map(fromRest);
    case "mapValue": return Object.fromEntries(Object.entries(x.fields || {}).map(([k, y]) => [k, fromRest(y)]));
    default: return null;
  }
}

function campaignData() {
  const file = process.env.TAG51_UNILEVER_FIXTURE;
  if (file && fs.existsSync(file)) {
    const raw = JSON.parse(fs.readFileSync(file, "utf8"));
    const data = Object.fromEntries(Object.entries(raw.fields).map(([k, v]) => [k, fromRest(v)]));
    return { data, source: "production copy " + raw.name };
  }
  const requiredProducts = Array.from({ length: 3636 }, (_, i) => `يونيلفر صنف رقم ${i} ${"ص".repeat(25)}`);
  return {
    data: {
      eventName: "حمله منتجات شركه يونيلفر (synthetic)",
      targetCompany: "Unilever",
      companySlug: "512",
      isActive: true,
      minimumSpend: 0,
      requiredProducts,
      customPrompt: "تعليمات فحص الفاتورة ".repeat(7000),
      promotionalRules: [],
      allocatedPrizes: [],
    },
    source: "synthetic",
  };
}

// The app's CampaignContentRepository.hydrate, through the rules.
async function readLikeApp(db, eventId) {
  const snap = await getDoc(doc(db, "events", eventId));
  const data = snap.data();
  const legacy = { requiredProducts: content.legacyProducts(data), customPrompt: content.legacyPrompt(data), source: "legacy" };
  const marker = content.parseMarker(data.contentStorage);
  if (!marker) return legacy;
  try {
    const parts = {};
    for (const id of content.partIds(marker)) {
      const s = await getDoc(doc(db, "events", eventId, "content", id));
      parts[id] = s.exists() ? s.data() : null;
    }
    const c = content.assembleContent(marker, parts);
    return c ? Object.assign(c, { source: "parts" }) : legacy;
  } catch (e) {
    return legacy;
  }
}

// The app's CampaignEditSave.save + invalidateContentCopy, as the admin.
async function editLikeApp(db, eventId, changes) {
  await runTransaction(db, async (tx) => {
    const ref = doc(db, "events", eventId);
    const snap = await tx.get(ref);
    const current = snap.data();
    const patch = Object.assign({}, changes);
    const touches = "requiredProducts" in patch || "customPrompt" in patch;
    if (touches && "contentStorage" in current) {
      patch.requiredProducts = patch.requiredProducts || content.legacyProducts(current);
      patch.customPrompt = "customPrompt" in patch ? patch.customPrompt : content.legacyPrompt(current);
      patch.contentStorage = deleteField();
    }
    patch.updatedAt = serverTimestamp();
    patch.updatedBy = "admin-1";
    tx.update(ref, patch);
  });
}

// The app's CampaignContentRepository.syncFromLegacy, as the admin.
async function syncLikeApp(db, eventId) {
  await runTransaction(db, async (tx) => {
    const ref = doc(db, "events", eventId);
    const data = (await tx.get(ref)).data();
    const existing = content.parseMarker(data.contentStorage);
    const plan = content.planContent(content.legacyProducts(data), content.legacyPrompt(data));
    if (existing && (existing.rev === plan.marker.rev || !existing.legacyMirror)) return;
    for (const [id, part] of Object.entries(plan.parts)) tx.set(doc(db, "events", eventId, "content", id), part);
    tx.update(ref, { contentStorage: plan.marker });
  });
}

function docBytes(data) {
  return Buffer.byteLength(JSON.stringify(data), "utf8");
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: fs.readFileSync(path.join(RULES_DIR, "firestore.rules"), "utf8") },
  });
  const { initializeApp, getApps } = require("../functions/node_modules/firebase-admin/lib/app");
  const { getFirestore } = require("../functions/node_modules/firebase-admin/lib/firestore");
  if (!getApps().length) initializeApp({ projectId: PROJECT_ID });
  adminDb = getFirestore();
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe("TAG-51 rules for events/{id}/content", () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "events/on"), { companySlug: "acme", isActive: true });
      await setDoc(doc(db, "events/off"), { companySlug: "acme", isActive: false });
      const plan = content.planContent(["a"], "p");
      for (const id of ["on", "off"]) {
        for (const [pid, part] of Object.entries(plan.parts)) await setDoc(doc(db, "events", id, "content", pid), part);
      }
    });
  });

  test("admin writes valid parts only", async () => {
    const db = adminCtx();
    const part = { kind: "products", rev: "r1", part: 0, parts: 1, items: ["x"] };
    await assertSucceeds(setDoc(doc(db, "events/on/content/products-0"), part));
    await assertSucceeds(setDoc(doc(db, "events/on/content/prompt-3"), { kind: "prompt", rev: "r1", part: 3, parts: 4, text: "t" }));
    await assertFails(setDoc(doc(db, "events/on/content/products-0"), Object.assign({}, part, { kind: "prompt" })));
    await assertFails(setDoc(doc(db, "events/on/content/other"), part));
    await assertFails(setDoc(doc(db, "events/on/content/products-100"), part));
    await assertFails(setDoc(doc(db, "events/on/content/products-1"), Object.assign({}, part, { rev: 5 })));
    await assertSucceeds(getDocs(collection(db, "events/on/content")));
  });

  test("anonymous reps get parts of an active campaign by id, nothing else", async () => {
    const db = anonCtx();
    await assertSucceeds(getDoc(doc(db, "events/on/content/products-0")));
    await assertFails(getDoc(doc(db, "events/off/content/products-0")));
    await assertFails(getDocs(collection(db, "events/on/content")));
    await assertFails(setDoc(doc(db, "events/on/content/products-0"), { kind: "products", rev: "x", part: 0, parts: 1, items: [] }));
  });

  test("partners read only their company's parts; signed-out clients nothing", async () => {
    await assertSucceeds(getDoc(doc(partnerCtx("acme"), "events/off/content/prompt-0")));
    await assertFails(getDoc(doc(partnerCtx("other"), "events/on/content/prompt-0")));
    await assertFails(setDoc(doc(partnerCtx("acme"), "events/on/content/prompt-0"), { kind: "prompt", rev: "x", part: 0, parts: 1, text: "" }));
    await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), "events/on/content/prompt-0")));
  });
});

describe("TAG-51 Unilever-sized campaign on the emulator", () => {
  const { data, source } = campaignData();
  const legacyProducts = data.requiredProducts;
  const legacyPrompt = data.customPrompt;
  const log = [];

  beforeAll(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "events", EVENT_ID), data);
    });
    log.push(`campaign: ${source}, ${legacyProducts.length} products, prompt ${legacyPrompt.length} chars, doc ~${docBytes(data)} bytes`);
  });

  afterAll(() => {
    console.log("TAG-51 emulator flow:\n  " + log.join("\n  "));
  });

  test("1. migration dry run writes nothing", async () => {
    const r = await migration.run(adminDb, { mode: "migrate", apply: false, event: EVENT_ID });
    expect(r.summary).toEqual({ "would-migrate": 1 });
    const parts = await adminDb.collection("events").doc(EVENT_ID).collection("content").get();
    expect(parts.size).toBe(0);
    const ev = (await adminDb.collection("events").doc(EVENT_ID).get()).data();
    expect(ev.contentStorage).toBeUndefined();
    log.push(`dry run: ${JSON.stringify(r.summary)}, parts planned ${r.results[0].parts.join(",")}`);
  });

  test("2. migration apply, re-run is a no-op, verify ok, legacy fields kept", async () => {
    const r1 = await migration.run(adminDb, { mode: "migrate", apply: true, event: EVENT_ID });
    expect(r1.summary).toEqual({ migrated: 1 });
    const r2 = await migration.run(adminDb, { mode: "migrate", apply: true, event: EVENT_ID });
    expect(r2.summary).toEqual({ "already-migrated": 1 });
    const v = await migration.run(adminDb, { mode: "verify", event: EVENT_ID });
    expect(v.summary).toEqual({ ok: 1 });
    const ev = (await adminDb.collection("events").doc(EVENT_ID).get()).data();
    expect(ev.requiredProducts.length).toBe(legacyProducts.length);
    expect(ev.customPrompt).toBe(legacyPrompt);
    const parts = await adminDb.collection("events").doc(EVENT_ID).collection("content").get();
    for (const p of parts.docs) expect(docBytes(p.data())).toBeLessThan(1000000);
    log.push(`apply: ${JSON.stringify(r1.summary)}; re-run: ${JSON.stringify(r2.summary)}; verify: ${JSON.stringify(v.summary)}; parts ${parts.docs.map((d) => `${d.id}≈${docBytes(d.data())}B`).join(", ")}`);
  });

  test("3. reps (anonymous) and admins read products and prompt from the parts through the rules", async () => {
    for (const db of [anonCtx(), adminCtx()]) {
      const c = await readLikeApp(db, EVENT_ID);
      expect(c.source).toBe("parts");
      expect(c.requiredProducts).toEqual(legacyProducts);
      expect(c.customPrompt).toBe(legacyPrompt);
    }
  });

  test("4. claims (in the claim transaction) and the AI gateway read the products", async () => {
    const ref = adminDb.collection("events").doc(EVENT_ID);
    const inTx = await adminDb.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      return content.withCampaignContent(adminDb, EVENT_ID, snap.data(), tx);
    });
    expect(inTx.requiredProducts).toEqual(legacyProducts);
    const viaGateway = await getCachedCampaignProducts(adminDb, EVENT_ID);
    expect(viaGateway.length).toBe(legacyProducts.length);
    // The eligibility check sees the products (named product on the invoice vs not).
    const now = Date.now();
    const base = { receipt_date: new Date(now).toISOString().slice(0, 10), timestamp: new Date(now) };
    const event = Object.assign({}, inTx, { isActive: true, startDate: null, endDate: null, promotionalRules: [], minimumSpend: 0, spendLadderMode: "exclusive" });
    const hit = evaluateClaimEligibility({ event, receipt: Object.assign({}, base, { extracted_products: [{ name: legacyProducts[0], qty: 1, price: 50, total: 50 }] }), nowMs: now, system: false });
    const miss = evaluateClaimEligibility({ event, receipt: Object.assign({}, base, { extracted_products: [{ name: "zzz-not-a-product", qty: 1, price: 50, total: 50 }] }), nowMs: now, system: false });
    log.push(`claim check: invoice with "${legacyProducts[0].slice(0, 30)}" -> ${hit.ok ? "ok" : hit.code}; unrelated line -> ${miss.ok ? "ok" : miss.code}`);
    expect(hit.code).not.toBe(miss.code);
  });

  test("5. admin edit/save of the prompt (as the app) works; readers fall back, then the copy is re-synced", async () => {
    const db = adminCtx();
    const newPrompt = legacyPrompt + "\nتعديل TAG-51";
    await assertSucceeds(editLikeApp(db, EVENT_ID, { customPrompt: newPrompt }));
    const between = await readLikeApp(anonCtx(), EVENT_ID);
    expect(between.source).toBe("legacy");
    expect(between.customPrompt).toBe(newPrompt);
    await assertSucceeds(syncLikeApp(db, EVENT_ID));
    const after = await readLikeApp(anonCtx(), EVENT_ID);
    expect(after.source).toBe("parts");
    expect(after.customPrompt).toBe(newPrompt);
    expect(after.requiredProducts).toEqual(legacyProducts);
    log.push("edit prompt -> marker dropped, readers on campaign fields -> re-sync -> readers on parts with the new prompt");
  });

  test("6. a small edit (name only) keeps the copy valid", async () => {
    await assertSucceeds(editLikeApp(adminCtx(), EVENT_ID, { eventName: data.eventName + " ✓" }));
    const c = await readLikeApp(anonCtx(), EVENT_ID);
    expect(c.source).toBe("parts");
  });

  test("7. cleanup (later phase) removes the big fields; everything still reads; an edit after it still saves", async () => {
    const before = docBytes((await adminDb.collection("events").doc(EVENT_ID).get()).data());
    const dry = await migration.run(adminDb, { mode: "cleanup", apply: false, event: EVENT_ID });
    expect(dry.summary).toEqual({ "would-clean": 1 });
    const r = await migration.run(adminDb, { mode: "cleanup", apply: true, event: EVENT_ID });
    expect(r.summary).toEqual({ cleaned: 1 });
    const ev = (await adminDb.collection("events").doc(EVENT_ID).get()).data();
    expect(ev.requiredProducts).toBeUndefined();
    expect(ev.customPrompt).toBeUndefined();
    const afterBytes = docBytes(ev);
    log.push(`cleanup: campaign document ~${before}B -> ~${afterBytes}B`);
    expect(afterBytes).toBeLessThan(before / 3);
    const c = await readLikeApp(anonCtx(), EVENT_ID);
    expect(c.source).toBe("parts");
    expect(c.requiredProducts.length).toBe(legacyProducts.length);
    const fn = await content.readCampaignContent(adminDb, EVENT_ID, ev);
    expect(fn.source).toBe("parts");
    expect(fn.requiredProducts.length).toBe(legacyProducts.length);
    // Phase-1 sync must never rebuild parts from the removed fields.
    await assertSucceeds(syncLikeApp(adminCtx(), EVENT_ID));
    expect((await readLikeApp(anonCtx(), EVENT_ID)).requiredProducts.length).toBe(legacyProducts.length);
    // A phase-1 editor changing the prompt writes both fields back in full.
    const editor = adminCtx();
    const hydrated = await readLikeApp(editor, EVENT_ID);
    await runTransaction(editor, async (tx) => {
      const ref = doc(editor, "events", EVENT_ID);
      await tx.get(ref);
      tx.update(ref, { customPrompt: hydrated.customPrompt + "!", requiredProducts: hydrated.requiredProducts, contentStorage: deleteField() });
    });
    await assertSucceeds(syncLikeApp(adminCtx(), EVENT_ID));
    const final = await readLikeApp(anonCtx(), EVENT_ID);
    expect(final.source).toBe("parts");
    expect(final.requiredProducts.length).toBe(legacyProducts.length);
    expect(final.customPrompt.endsWith("!")).toBe(true);
  });

  test("8. why: a prompt that grows past 1 MiB cannot live in the campaign document, but fits in parts", async () => {
    const big = legacyPrompt.repeat(5);
    let err = null;
    try {
      await adminDb.collection("events").doc(EVENT_ID).update({ customPrompt: big, requiredProducts: legacyProducts });
    } catch (e) {
      err = e;
    }
    expect(err).not.toBeNull();
    const plan = content.planContent(legacyProducts, big);
    const batch = adminDb.batch();
    for (const [id, part] of Object.entries(plan.parts)) batch.set(adminDb.collection("events").doc("big-copy").collection("content").doc(id), part);
    await batch.commit();
    log.push(`5x prompt (${Buffer.byteLength(big, "utf8")}B) in the campaign document -> ${String(err && (err.code || err.message)).slice(0, 80)}; as parts -> ${Object.keys(plan.parts).length} parts, OK`);
  });
});
