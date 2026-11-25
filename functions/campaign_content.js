/**
 * TAG-51 phase 1: requiredProducts / customPrompt copied out of the campaign
 * document into events/{eventId}/content/{partId}. JavaScript twin of
 * lib/features/admin/domain/campaign_content_storage.dart (same layout, same
 * revision bytes, same checks).
 *
 *   products-0..N  {kind: "products", rev, part, parts, items: [...]}
 *   prompt-0..M    {kind: "prompt",   rev, part, parts, text: "..."}
 *   events/{id}.contentStorage = {v: 1, rev, productParts, promptParts,
 *                                 productsCount, promptLength, legacyMirror}
 *
 * Readers use the parts when the marker is valid and every part matches it,
 * else the legacy fields on the campaign document.
 */
const crypto = require("crypto");

const SUBCOLLECTION = "content";
const MARKER_FIELD = "contentStorage";
const VERSION = 1;
const MAX_PART_BYTES = 600000;
const MAX_PARTS = 100;

const productsPartId = (i) => `products-${i}`;
const promptPartId = (i) => `prompt-${i}`;

function legacyProducts(data) {
  const raw = data && data.requiredProducts;
  return Array.isArray(raw) ? raw.filter((p) => typeof p === "string") : [];
}

function legacyPrompt(data) {
  return data && typeof data.customPrompt === "string" ? data.customPrompt : "";
}

/** sha256 over products (each + 0x00), 0x01, prompt; first 24 hex chars. */
function contentRev(products, prompt) {
  const h = crypto.createHash("sha256");
  for (const p of products) {
    h.update(Buffer.from(p, "utf8"));
    h.update(Buffer.from([0]));
  }
  h.update(Buffer.from([1]));
  h.update(Buffer.from(prompt, "utf8"));
  return h.digest("hex").slice(0, 24);
}

function chunkProducts(products, maxBytes = MAX_PART_BYTES) {
  const parts = [];
  let current = [];
  let size = 0;
  for (const p of products) {
    const s = Buffer.byteLength(p, "utf8") + 16;
    if (current.length && size + s > maxBytes) {
      parts.push(current);
      current = [];
      size = 0;
    }
    current.push(p);
    size += s;
  }
  parts.push(current);
  return parts;
}

function chunkPrompt(prompt, maxBytes = MAX_PART_BYTES) {
  const parts = [];
  let start = 0;
  let bytes = 0;
  let i = 0;
  while (i < prompt.length) {
    const cu = prompt.charCodeAt(i);
    const next = i + 1 < prompt.length ? prompt.charCodeAt(i + 1) : 0;
    const isPair = cu >= 0xd800 && cu <= 0xdbff && next >= 0xdc00 && next <= 0xdfff;
    const b = isPair ? 4 : cu < 0x80 ? 1 : cu < 0x800 ? 2 : 3;
    if (bytes + b > maxBytes && i > start) {
      parts.push(prompt.slice(start, i));
      start = i;
      bytes = 0;
    }
    bytes += b;
    i += isPair ? 2 : 1;
  }
  parts.push(prompt.slice(start));
  return parts;
}

/** Part documents and marker for one content. */
function planContent(products, prompt, { legacyMirror = true } = {}) {
  const rev = contentRev(products, prompt);
  const productParts = chunkProducts(products);
  const promptParts = chunkPrompt(prompt);
  if (productParts.length > MAX_PARTS || promptParts.length > MAX_PARTS) {
    throw new Error(`campaign content too large: ${productParts.length} product parts, ${promptParts.length} prompt parts`);
  }
  const parts = {};
  productParts.forEach((items, i) => {
    parts[productsPartId(i)] = { kind: "products", rev, part: i, parts: productParts.length, items };
  });
  promptParts.forEach((text, i) => {
    parts[promptPartId(i)] = { kind: "prompt", rev, part: i, parts: promptParts.length, text };
  });
  return {
    marker: {
      v: VERSION,
      rev,
      productParts: productParts.length,
      promptParts: promptParts.length,
      productsCount: products.length,
      promptLength: prompt.length,
      legacyMirror,
    },
    parts,
  };
}

function parseMarker(raw) {
  if (!raw || typeof raw !== "object") return null;
  const int = (v) => (Number.isInteger(v) ? v : null);
  const m = {
    v: int(raw.v),
    rev: raw.rev,
    productParts: int(raw.productParts),
    promptParts: int(raw.promptParts),
    productsCount: int(raw.productsCount),
    promptLength: int(raw.promptLength),
    legacyMirror: raw.legacyMirror !== false,
  };
  if (m.v !== VERSION || typeof m.rev !== "string" || !m.rev) return null;
  if ([m.productParts, m.promptParts, m.productsCount, m.promptLength].some((x) => x == null)) return null;
  if (m.productParts < 1 || m.promptParts < 1 || m.productParts > MAX_PARTS || m.promptParts > MAX_PARTS) return null;
  if (m.productsCount < 0 || m.promptLength < 0) return null;
  return m;
}

function partIds(marker) {
  const ids = [];
  for (let i = 0; i < marker.productParts; i++) ids.push(productsPartId(i));
  for (let i = 0; i < marker.promptParts; i++) ids.push(promptPartId(i));
  return ids;
}

/** {requiredProducts, customPrompt} from parts (id -> data|null), or null. */
function assembleContent(marker, parts) {
  const products = [];
  for (let i = 0; i < marker.productParts; i++) {
    const d = parts[productsPartId(i)];
    if (!d || d.kind !== "products" || d.rev !== marker.rev || d.parts !== marker.productParts) return null;
    if (!Array.isArray(d.items) || d.items.some((x) => typeof x !== "string")) return null;
    products.push(...d.items);
  }
  let prompt = "";
  for (let i = 0; i < marker.promptParts; i++) {
    const d = parts[promptPartId(i)];
    if (!d || d.kind !== "prompt" || d.rev !== marker.rev || d.parts !== marker.promptParts) return null;
    if (typeof d.text !== "string") return null;
    prompt += d.text;
  }
  if (products.length !== marker.productsCount || prompt.length !== marker.promptLength) return null;
  return { requiredProducts: products, customPrompt: prompt };
}

/**
 * Reads the content of campaign [eventId] whose document data is [data].
 * Pass [tx] to read the parts inside a transaction. Never throws: on any
 * problem it returns the legacy fields with source "legacy".
 */
async function readCampaignContent(db, eventId, data, tx = null) {
  const legacy = { requiredProducts: legacyProducts(data), customPrompt: legacyPrompt(data), source: "legacy" };
  const marker = parseMarker(data && data[MARKER_FIELD]);
  if (!marker || !eventId) return legacy;
  try {
    const col = db.collection("events").doc(eventId).collection(SUBCOLLECTION);
    const refs = partIds(marker).map((id) => col.doc(id));
    const snaps = tx ? await tx.getAll(...refs) : await db.getAll(...refs);
    const parts = {};
    snaps.forEach((s) => { parts[s.id] = s.exists ? s.data() : null; });
    const content = assembleContent(marker, parts);
    if (!content) {
      console.warn(`TAG-51: content parts of ${eventId} do not match rev ${marker.rev}; using the campaign fields`);
      return legacy;
    }
    return Object.assign(content, { source: "parts" });
  } catch (e) {
    console.warn(`TAG-51: content parts of ${eventId} not read (${e && e.message}); using the campaign fields`);
    return legacy;
  }
}

/** Copy of [data] with requiredProducts / customPrompt from readCampaignContent. */
async function withCampaignContent(db, eventId, data, tx = null) {
  const c = await readCampaignContent(db, eventId, data, tx);
  return Object.assign({}, data, { requiredProducts: c.requiredProducts, customPrompt: c.customPrompt });
}

module.exports = {
  SUBCOLLECTION,
  MARKER_FIELD,
  VERSION,
  MAX_PART_BYTES,
  MAX_PARTS,
  productsPartId,
  promptPartId,
  legacyProducts,
  legacyPrompt,
  contentRev,
  chunkProducts,
  chunkPrompt,
  planContent,
  parseMarker,
  partIds,
  assembleContent,
  readCampaignContent,
  withCampaignContent,
};
