"use strict";
// TAG-56: content chunks for requiredProducts / customPrompt.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  MAX_ITEMS_PER_CHUNK,
  MAX_CHARS_PER_CHUNK,
  chunkProducts,
  chunkPrompt,
  contentPointer,
  assembleContent,
  withEventContent,
  planContentWrites,
  contentBytes,
} = require("../campaign_content");

const FieldValue = {
  serverTimestamp: () => ({ __op: "serverTimestamp" }),
  delete: () => ({ __op: "delete" }),
};

// Shape of the Unilever campaign: 3,636 products and a ~247K-char prompt.
function bigCampaign() {
  const products = Array.from({ length: 3636 }, (_, i) => `منتج يونيلفر رقم ${i} - صابون لوكس ${i % 7} جم`);
  const prompt = "أنت مساعد ذكي لفحص فواتير يونيلفر. ".repeat(7100);
  return { products, prompt };
}

function fakeDb(docsById) {
  return {
    collection: (c) => ({
      doc: (id) => ({
        collection: (sub) => ({
          _path: `${c}/${id}/${sub}`,
          get: async () => ({ docs: [...docsById.entries()].map(([k, v]) => ({ id: k, data: () => v })) }),
        }),
      }),
    }),
  };
}

function storeOf(plan) {
  return new Map([...plan.docs.entries()]);
}

test("chunks respect item and size limits and keep order", () => {
  const { products, prompt } = bigCampaign();
  const chunks = chunkProducts(products);
  assert.ok(chunks.length >= 3);
  for (const c of chunks) {
    assert.ok(c.length <= MAX_ITEMS_PER_CHUNK);
    assert.ok(Buffer.byteLength(JSON.stringify(c), "utf8") < 900 * 1024);
  }
  assert.deepEqual(chunks.flat(), products);
  const parts = chunkPrompt(prompt);
  assert.ok(parts.every((p) => p.length <= MAX_CHARS_PER_CHUNK));
  assert.equal(parts.join(""), prompt);
  assert.deepEqual(chunkProducts([]), []);
  assert.deepEqual(chunkPrompt(""), []);
});

test("a surrogate pair is never split across prompt chunks", () => {
  const prompt = "a".repeat(MAX_CHARS_PER_CHUNK - 1) + "😀" + "b";
  const parts = chunkPrompt(prompt);
  assert.equal(parts.join(""), prompt);
  assert.ok(!/[\ud800-\udbff]$/.test(parts[0]));
});

test("plan + assemble round-trip the Unilever-sized campaign; large drops legacy", () => {
  const { products, prompt } = bigCampaign();
  const plan = planContentWrites({ products, prompt, previous: null, FieldValue });
  assert.equal(plan.revision, 1);
  assert.equal(plan.eventFields.requiredProducts.__op, "delete");
  assert.equal(plan.eventFields.customPrompt.__op, "delete");
  const pointer = contentPointer(plan.eventFields);
  assert.equal(pointer.productsCount, 3636);
  const back = assembleContent(pointer, storeOf(plan));
  assert.deepEqual(back.products, products);
  assert.equal(back.prompt, prompt);
  for (const d of plan.docs.values()) assert.ok(Buffer.byteLength(JSON.stringify(d), "utf8") < 900 * 1024);
});

test("small campaigns keep the legacy mirror", () => {
  const plan = planContentWrites({ products: ["Lux"], prompt: "p", previous: null, FieldValue });
  assert.deepEqual(plan.eventFields.requiredProducts, ["Lux"]);
  assert.equal(plan.eventFields.customPrompt, "p");
  assert.ok(contentBytes(["Lux"], "p") < 100);
});

test("a new revision deletes stale chunks; an old-revision chunk is rejected", () => {
  const { products, prompt } = bigCampaign();
  const first = planContentWrites({ products, prompt, previous: null, FieldValue });
  const prev = contentPointer(first.eventFields);
  const second = planContentWrites({ products: ["Lux"], prompt: "", previous: prev, FieldValue });
  assert.equal(second.revision, 2);
  assert.ok(second.deleteIds.includes("products_1"));
  assert.ok(second.deleteIds.includes("prompt_0"));
  const mixed = storeOf(first);
  mixed.set("products_0", second.docs.get("products_0"));
  assert.equal(assembleContent(prev, mixed), null, "revision 1 pointer must not accept a revision 2 chunk");
});

test("withEventContent: legacy untouched, chunks loaded, fail closed when incomplete", async () => {
  const legacy = { requiredProducts: ["Lux"], customPrompt: "p" };
  assert.equal(await withEventContent(fakeDb(new Map()), "e1", legacy), legacy);

  const { products, prompt } = bigCampaign();
  const plan = planContentWrites({ products, prompt, previous: null, FieldValue });
  const event = { eventName: "Unilever", contentVersion: 1, ...plan.eventFields };
  delete event.requiredProducts;
  delete event.customPrompt;
  const loaded = await withEventContent(fakeDb(storeOf(plan)), "e1", event);
  assert.equal(loaded.requiredProducts.length, 3636);
  assert.equal(loaded.customPrompt, prompt);
  assert.equal(loaded.eventName, "Unilever");

  const broken = storeOf(plan);
  broken.delete("products_1");
  await assert.rejects(withEventContent(fakeDb(broken), "e1", event), /incomplete/);
  // ...but a legacy copy on the document is used instead of failing.
  const withLegacy = Object.assign({}, event, { requiredProducts: products.slice(0, 5) });
  assert.equal((await withEventContent(fakeDb(broken), "e1", withLegacy)).requiredProducts.length, 5);
});

test("optional: the real Unilever copy (TAG56_UNILEVER_JSON, never committed)", { skip: !process.env.TAG56_UNILEVER_JSON }, () => {
  const data = JSON.parse(fs.readFileSync(process.env.TAG56_UNILEVER_JSON, "utf8"));
  const products = data.requiredProducts || [];
  const prompt = data.customPrompt || "";
  const plan = planContentWrites({ products, prompt, previous: null, FieldValue });
  const back = assembleContent(contentPointer(plan.eventFields), storeOf(plan));
  assert.deepEqual(back.products, products);
  assert.equal(back.prompt, prompt);
  console.log(`unilever: ${products.length} products, ${prompt.length} prompt chars, ${plan.docs.size} chunks`);
});
