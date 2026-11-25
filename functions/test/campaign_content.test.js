// TAG-51: layout helpers for events/{id}/content (unit, no emulator).
const test = require("node:test");
const assert = require("node:assert/strict");
const c = require("../campaign_content");
const { sameContent, contentBytes } = require("../scripts/migrate_campaign_content");

// Same fixture and expected revisions as test/tag51_campaign_content_storage_test.dart.
const FIXTURE_PRODUCTS = ["كادبري", "Dove 😀", "a,b", ""];
const FIXTURE_PROMPT = "برومبت\n{REQUIRED_PRODUCTS} 🎁";

test("revision bytes match the Dart side", () => {
  assert.equal(c.contentRev(FIXTURE_PRODUCTS, FIXTURE_PROMPT), "616d97bf7cf48b48acf02b76");
  assert.equal(c.contentRev([], ""), "4bf5122f344554c53bde2ebb");
  assert.notEqual(c.contentRev(["ab"], ""), c.contentRev(["a", "b"], ""));
  assert.notEqual(c.contentRev(["a"], ""), c.contentRev([], "a"));
});

test("products are chunked under the byte limit and keep order", () => {
  const products = Array.from({ length: 1000 }, (_, i) => `منتج رقم ${i}`);
  const parts = c.chunkProducts(products, 2000);
  assert.ok(parts.length > 1);
  for (const p of parts) {
    const bytes = p.reduce((s, x) => s + Buffer.byteLength(x, "utf8") + 16, 0);
    assert.ok(bytes <= 2000, `part of ${bytes} bytes`);
  }
  assert.deepEqual(parts.flat(), products);
  assert.deepEqual(c.chunkProducts([]), [[]]);
});

test("prompt is chunked under the byte limit without splitting a surrogate pair", () => {
  const prompt = "أ😀b".repeat(5000);
  const parts = c.chunkPrompt(prompt, 999);
  assert.ok(parts.length > 1);
  for (const p of parts) {
    assert.ok(Buffer.byteLength(p, "utf8") <= 999);
    const last = p.charCodeAt(p.length - 1);
    assert.ok(!(last >= 0xd800 && last <= 0xdbff), "part ends inside a surrogate pair");
  }
  assert.equal(parts.join(""), prompt);
  assert.deepEqual(c.chunkPrompt(""), [""]);
});

test("plan + assemble round trip, and every mismatch falls back (null)", () => {
  const products = Array.from({ length: 3636 }, (_, i) => `يونيلفر صنف ${i} ${"x".repeat(40)}`);
  const prompt = "تعليمات ".repeat(20000);
  const plan = c.planContent(products, prompt);
  assert.equal(plan.marker.v, 1);
  assert.equal(plan.marker.legacyMirror, true);
  assert.equal(plan.marker.productsCount, products.length);
  assert.equal(plan.marker.promptLength, prompt.length);
  for (const doc of Object.values(plan.parts)) {
    assert.ok(Buffer.byteLength(JSON.stringify(doc), "utf8") < 1000000);
  }
  const marker = c.parseMarker(plan.marker);
  assert.ok(marker);
  assert.deepEqual(c.partIds(marker), Object.keys(plan.parts));
  const back = c.assembleContent(marker, plan.parts);
  assert.deepEqual(back.requiredProducts, products);
  assert.equal(back.customPrompt, prompt);

  const missing = Object.assign({}, plan.parts, { "prompt-0": null });
  assert.equal(c.assembleContent(marker, missing), null);
  const stale = Object.assign({}, plan.parts, { "products-0": Object.assign({}, plan.parts["products-0"], { rev: "old" }) });
  assert.equal(c.assembleContent(marker, stale), null);
  assert.equal(c.assembleContent(Object.assign({}, marker, { productsCount: 1 }), plan.parts), null);
});

test("parseMarker rejects anything that is not a v1 marker", () => {
  assert.equal(c.parseMarker(null), null);
  assert.equal(c.parseMarker({ v: 2, rev: "a", productParts: 1, promptParts: 1, productsCount: 0, promptLength: 0 }), null);
  assert.equal(c.parseMarker({ v: 1, rev: "", productParts: 1, promptParts: 1, productsCount: 0, promptLength: 0 }), null);
  assert.equal(c.parseMarker({ v: 1, rev: "a", productParts: 0, promptParts: 1, productsCount: 0, promptLength: 0 }), null);
  assert.equal(c.parseMarker({ v: 1, rev: "a", productParts: 1, promptParts: 1, productsCount: 0, promptLength: 0, legacyMirror: false }).legacyMirror, false);
});

function fakeDb(parts, { fail = false } = {}) {
  const doc = (id) => ({ id });
  return {
    collection: () => ({ doc: () => ({ collection: () => ({ doc }) }) }),
    getAll: async (...refs) => {
      if (fail) throw new Error("PERMISSION_DENIED");
      return refs.map((r) => ({ id: r.id, exists: parts[r.id] != null, data: () => parts[r.id] }));
    },
  };
}

test("readCampaignContent: parts when valid, legacy fields otherwise (never throws)", async () => {
  const plan = c.planContent(["جديد"], "برومبت جديد");
  const legacy = { requiredProducts: ["قديم"], customPrompt: "برومبت قديم" };

  const noMarker = await c.readCampaignContent(fakeDb(plan.parts), "e1", legacy);
  assert.equal(noMarker.source, "legacy");
  assert.deepEqual(noMarker.requiredProducts, ["قديم"]);

  const withMarker = Object.assign({}, legacy, { contentStorage: plan.marker });
  const fromParts = await c.readCampaignContent(fakeDb(plan.parts), "e1", withMarker);
  assert.equal(fromParts.source, "parts");
  assert.deepEqual(fromParts.requiredProducts, ["جديد"]);
  assert.equal(fromParts.customPrompt, "برومبت جديد");

  const denied = await c.readCampaignContent(fakeDb(plan.parts, { fail: true }), "e1", withMarker);
  assert.equal(denied.source, "legacy");
  const broken = await c.readCampaignContent(fakeDb({}), "e1", withMarker);
  assert.equal(broken.source, "legacy");

  const merged = await c.withCampaignContent(fakeDb(plan.parts), "e1", Object.assign({ eventName: "x" }, withMarker));
  assert.equal(merged.eventName, "x");
  assert.deepEqual(merged.requiredProducts, ["جديد"]);
});

test("migration helpers", () => {
  assert.ok(sameContent({ requiredProducts: ["a"], customPrompt: "p" }, { requiredProducts: ["a"], customPrompt: "p" }));
  assert.ok(!sameContent({ requiredProducts: ["a"], customPrompt: "p" }, { requiredProducts: ["b"], customPrompt: "p" }));
  assert.ok(contentBytes({ requiredProducts: ["ab"], customPrompt: "cd" }) > 4);
});
