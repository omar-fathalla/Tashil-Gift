"use strict";

/**
 * TAG-56: a campaign's product list and AI prompt are stored outside the
 * campaign document, in events/{id}/content/products_{n} and prompt_{n}.
 * The campaign document keeps a pointer (contentVersion, contentRevision,
 * contentProductsChunks, contentPromptChunks). Mirrors lib/features/admin/
 * domain/campaign_content.dart.
 */

const SUBCOLLECTION = "content";
const CONTENT_VERSION = 1;
const MAX_ITEMS_PER_CHUNK = 1500;
const MAX_CHARS_PER_CHUNK = 300000;
const LEGACY_MIRROR_MAX_BYTES = 200 * 1024;

const productsDocId = (i) => `products_${i}`;
const promptDocId = (i) => `prompt_${i}`;

function toInt(v) {
  return typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : 0;
}

/** Pointer on a campaign document, or null for a legacy campaign. */
function contentPointer(data) {
  if (!data || toInt(data.contentVersion) < 1) return null;
  return {
    version: toInt(data.contentVersion),
    revision: toInt(data.contentRevision),
    productsChunks: toInt(data.contentProductsChunks),
    promptChunks: toInt(data.contentPromptChunks),
    productsCount: toInt(data.requiredProductsCount),
    promptLength: toInt(data.customPromptLength),
  };
}

function chunkProducts(products) {
  const chunks = [];
  let current = [];
  let size = 0;
  for (const p of products) {
    const len = Buffer.byteLength(String(p), "utf8") + 4;
    if (current.length && (current.length >= MAX_ITEMS_PER_CHUNK || size + len > MAX_CHARS_PER_CHUNK)) {
      chunks.push(current);
      current = [];
      size = 0;
    }
    current.push(String(p));
    size += len;
  }
  if (current.length) chunks.push(current);
  return chunks;
}

function chunkPrompt(prompt) {
  const chunks = [];
  let start = 0;
  while (start < prompt.length) {
    let end = start + MAX_CHARS_PER_CHUNK;
    if (end >= prompt.length) {
      end = prompt.length;
    } else {
      const unit = prompt.charCodeAt(end - 1);
      if (unit >= 0xd800 && unit <= 0xdbff) end -= 1;
    }
    chunks.push(prompt.slice(start, end));
    start = end;
  }
  return chunks;
}

function contentBytes(products, prompt) {
  return Buffer.byteLength(JSON.stringify(products), "utf8") + Buffer.byteLength(prompt, "utf8");
}

/**
 * Products and prompt from chunk docs (Map id -> data) for pointer, or null
 * when a chunk is missing or belongs to another revision.
 */
function assembleContent(pointer, docs) {
  const products = [];
  for (let i = 0; i < pointer.productsChunks; i++) {
    const d = docs.get(productsDocId(i));
    if (!d || toInt(d.revision) !== pointer.revision || !Array.isArray(d.items)) return null;
    for (const item of d.items) products.push(String(item));
  }
  let prompt = "";
  for (let i = 0; i < pointer.promptChunks; i++) {
    const d = docs.get(promptDocId(i));
    if (!d || toInt(d.revision) !== pointer.revision) return null;
    prompt += String(d.text || "");
  }
  return { products, prompt };
}

/**
 * Campaign data with requiredProducts / customPrompt filled from the content
 * chunks. Legacy campaigns come back unchanged. When the chunks are
 * incomplete the legacy fields are used; with none, an error is thrown (fail
 * closed: an empty product list must never widen eligibility).
 * Pass tx to read inside a transaction (before any write).
 */
async function withEventContent(db, eventId, data, { tx } = {}) {
  const pointer = contentPointer(data);
  if (!pointer) return data;
  const legacyProducts = Array.isArray(data.requiredProducts) ? data.requiredProducts : [];
  const legacyPrompt = typeof data.customPrompt === "string" ? data.customPrompt : "";
  if (legacyProducts.length === pointer.productsCount && legacyPrompt.length === pointer.promptLength) {
    return data; // small campaign: the mirror on the document is complete
  }
  const query = db.collection("events").doc(String(eventId)).collection(SUBCOLLECTION);
  const snap = tx ? await tx.get(query) : await query.get();
  const docs = new Map(snap.docs.map((d) => [d.id, d.data() || {}]));
  const content = assembleContent(pointer, docs);
  if (!content) {
    if (legacyProducts.length || legacyPrompt) return data;
    if (pointer.productsChunks === 0 && pointer.promptChunks === 0) return data;
    const err = new Error(`Campaign content for ${eventId} is incomplete (revision ${pointer.revision}).`);
    err.code = "campaign-content-unavailable";
    throw err;
  }
  return Object.assign({}, data, { requiredProducts: content.products, customPrompt: content.prompt });
}

/**
 * Writes storing products + prompt as revision previous+1: eventFields for
 * the campaign doc, docs to set (id -> data), deleteIds for stale chunks.
 * keepLegacy=true keeps the legacy fields as they are (migration); otherwise
 * they are mirrored when small and deleted when large.
 */
function planContentWrites({ products, prompt, previous, keepLegacy = false, FieldValue }) {
  const revision = (previous ? previous.revision : 0) + 1;
  const productChunks = chunkProducts(products);
  const promptChunks = chunkPrompt(prompt);
  const docs = new Map();
  productChunks.forEach((items, index) => docs.set(productsDocId(index), { kind: "products", index, revision, items }));
  promptChunks.forEach((text, index) => docs.set(promptDocId(index), { kind: "prompt", index, revision, text }));
  const deleteIds = [];
  if (previous) {
    for (let i = productChunks.length; i < previous.productsChunks; i++) deleteIds.push(productsDocId(i));
    for (let i = promptChunks.length; i < previous.promptChunks; i++) deleteIds.push(promptDocId(i));
  }
  const eventFields = {
    contentVersion: CONTENT_VERSION,
    contentRevision: revision,
    contentProductsChunks: productChunks.length,
    contentPromptChunks: promptChunks.length,
    requiredProductsCount: products.length,
    customPromptLength: prompt.length,
    contentUpdatedAt: FieldValue ? FieldValue.serverTimestamp() : new Date(),
  };
  if (!keepLegacy) {
    const mirror = contentBytes(products, prompt) <= LEGACY_MIRROR_MAX_BYTES;
    eventFields.requiredProducts = mirror ? products : FieldValue.delete();
    eventFields.customPrompt = mirror ? prompt : FieldValue.delete();
  }
  return { revision, eventFields, docs, deleteIds };
}

module.exports = {
  SUBCOLLECTION,
  CONTENT_VERSION,
  MAX_ITEMS_PER_CHUNK,
  MAX_CHARS_PER_CHUNK,
  LEGACY_MIRROR_MAX_BYTES,
  productsDocId,
  promptDocId,
  contentPointer,
  chunkProducts,
  chunkPrompt,
  contentBytes,
  assembleContent,
  withEventContent,
  planContentWrites,
};
