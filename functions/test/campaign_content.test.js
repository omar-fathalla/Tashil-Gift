/** TAG-62: campaign content helper and migration plan (no emulator). */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  withCampaignContent, planContentWrite, chunkProducts, bytes, CampaignContentUnavailable,
  CHUNK_LIMIT_BYTES, INLINE_LIMIT_BYTES,
} = require("../campaign_content");
const { planCampaign } = require("../scripts/migrate_campaign_content");

/** Minimal Firestore double: events/{id}/content/{doc} reads, counted. */
function fakeDb(contentByEvent) {
  const reads = [];
  const db = {
    reads,
    collection: (c) => ({
      doc: (eventId) => ({
        collection: (sub) => ({
          doc: (docId) => ({
            path: `${c}/${eventId}/${sub}/${docId}`,
            get: async () => {
              reads.push(docId);
              const data = ((contentByEvent[eventId] || {})[docId]);
              return { exists: data !== undefined, data: () => data };
            },
          }),
        }),
      }),
    }),
  };
  return db;
}

const products = (n, long = false) => Array.from({ length: n }, (_, i) =>
  long ? `منتج يونيليفر رقم ${i} - عبوة 250 جم - منظف متعدد الاستخدامات برائحة الليمون` : `منتج يونيليفر رقم ${i} - عبوة 250 جم`);

test("inline campaign: no read, same object", async () => {
  const db = fakeDb({});
  const data = { requiredProducts: ["أ"], customPrompt: "p", hasExternalContent: true };
  assert.equal(await withCampaignContent(db, "e1", data), data);
  assert.equal(db.reads.length, 0);
  const legacy = { requiredProducts: ["ب"] };
  assert.equal(await withCampaignContent(db, "e1", legacy), legacy);
});

test("an inline key wins over content docs (older apps edit it)", async () => {
  const db = fakeDb({ e1: { products: { items: ["قديم"], count: 1, version: 1, chunks: 0 }, prompt: { text: "x", version: 1 } } });
  const out = await withCampaignContent(db, "e1", { hasExternalContent: true, requiredProducts: ["جديد"], customPrompt: "y" });
  assert.deepEqual(out.requiredProducts, ["جديد"]);
  assert.equal(db.reads.length, 0);
});

test("external campaign: reads products and prompt", async () => {
  const db = fakeDb({ e1: { products: { items: ["أ", "ب"], count: 2, version: 3, chunks: 0 }, prompt: { text: "برومبت", version: 3 } } });
  const out = await withCampaignContent(db, "e1", { hasExternalContent: true, minimumSpend: 1 });
  assert.deepEqual(out.requiredProducts, ["أ", "ب"]);
  assert.equal(out.customPrompt, "برومبت");
  assert.equal(out.minimumSpend, 1);
});

test("prompt: false skips the prompt doc", async () => {
  const db = fakeDb({ e1: { products: { items: ["أ"], count: 1, version: 1, chunks: 0 } } });
  const out = await withCampaignContent(db, "e1", { hasExternalContent: true }, { prompt: false });
  assert.deepEqual(out.requiredProducts, ["أ"]);
  assert.deepEqual(db.reads, ["products"]);
});

test("missing products doc fails closed", async () => {
  const db = fakeDb({});
  await assert.rejects(withCampaignContent(db, "e1", { hasExternalContent: true }), CampaignContentUnavailable);
});

test("10,000 products are chunked under the limit and read back in order", async () => {
  const list = products(10000, true);
  assert.ok(bytes(list) > CHUNK_LIMIT_BYTES);
  const write = planContentWrite({ products: list, prompt: "ب".repeat(145000), version: 2 });
  assert.equal(write.inline, false);
  assert.deepEqual(write.deleteFields, ["requiredProducts", "customPrompt"]);
  assert.ok(write.eventFields.contentChunks >= 2);
  for (const [id, doc] of Object.entries(write.docs)) {
    assert.ok(bytes(doc) < 1000 * 1024, `${id} too big`);
    if (id.startsWith("products_")) assert.ok(bytes(doc.items) <= CHUNK_LIMIT_BYTES);
  }
  const db = fakeDb({ e1: write.docs });
  const out = await withCampaignContent(db, "e1", { hasExternalContent: true });
  assert.deepEqual(out.requiredProducts, list);
});

test("a chunk of another version fails closed", async () => {
  const list = products(10000, true);
  const docs = planContentWrite({ products: list, prompt: "", version: 2 }).docs;
  docs.products_0 = Object.assign({}, docs.products_0, { version: 1 });
  await assert.rejects(withCampaignContent(fakeDb({ e1: docs }), "e1", { hasExternalContent: true }), CampaignContentUnavailable);
});

test("small content stays inline too; shrinking deletes old chunks", () => {
  const write = planContentWrite({ products: ["أ"], prompt: "p", version: 4, previousChunks: 3 });
  assert.equal(write.inline, true);
  assert.deepEqual(write.eventFields.requiredProducts, ["أ"]);
  assert.deepEqual(write.deletes, ["products_0", "products_1", "products_2"]);
  assert.deepEqual(chunkProducts([]), [[]]);
});

test("migration plan: Unilever-sized campaign is externalized, small one dual-written, migrated one skipped", () => {
  const big = { eventName: "يونيليفر", requiredProducts: products(3636), customPrompt: "ت".repeat(145000) };
  const p1 = planCampaign("big", big, big);
  assert.equal(p1.report.action, "externalize");
  assert.ok(p1.report.docBytesBefore > INLINE_LIMIT_BYTES);
  assert.ok(p1.report.docBytesAfter < 10 * 1024, `after ${p1.report.docBytesAfter}`);

  const small = { eventName: "صغيرة", requiredProducts: ["أ"], customPrompt: "p" };
  assert.equal(planCampaign("s", small, small).report.action, "dual-write");

  const migrated = Object.assign({}, small, { hasExternalContent: true, contentVersion: 1 });
  assert.equal(planCampaign("m", migrated, migrated).report.action, "skip");
  const migratedBig = { eventName: "x", hasExternalContent: true, contentVersion: 1 };
  assert.equal(planCampaign("mb", migratedBig, Object.assign({}, migratedBig, { requiredProducts: big.requiredProducts, customPrompt: big.customPrompt })).report.action, "skip");
});
