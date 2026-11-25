/**
 * TAG-62 phase 1: campaign products / AI prompt, wherever they are stored.
 *
 * Large campaigns keep requiredProducts and customPrompt in
 * events/{id}/content (products [+ products_N chunks] and prompt) instead of
 * the campaign doc. A key present on the campaign doc always wins (older app
 * versions still edit it there); otherwise, when hasExternalContent is true,
 * the content docs are read. Nothing is read for an inline campaign.
 *
 * Missing or inconsistent content docs throw: the claim check must never
 * treat "list not found" as "no product condition".
 */

class CampaignContentUnavailable extends Error {
  constructor(eventId, reason) {
    super(`campaign content unavailable (${eventId}): ${reason}`);
    this.name = "CampaignContentUnavailable";
    this.eventId = eventId;
    this.reason = reason;
  }
}

const has = (data, key) => !!data && Object.prototype.hasOwnProperty.call(data, key);

/** True when [field] ("requiredProducts" | "customPrompt") must be read from content docs. */
function needsExternal(data, field) {
  return !!data && data.hasExternalContent === true && !has(data, field);
}

function contentRef(db, eventId, docId) {
  return db.collection("events").doc(eventId).collection("content").doc(docId);
}

async function readDoc(db, eventId, docId, tx) {
  const ref = contentRef(db, eventId, docId);
  const snap = tx ? await tx.get(ref) : await ref.get();
  return snap.exists ? snap.data() || {} : null;
}

const strings = (raw) => (Array.isArray(raw) ? raw.map((x) => String(x)) : []);

async function readProducts(db, eventId, { tx } = {}) {
  const head = await readDoc(db, eventId, "products", tx);
  if (!head) throw new CampaignContentUnavailable(eventId, "products doc missing");
  const chunks = Number(head.chunks) || 0;
  if (chunks <= 0) return strings(head.items);
  const parts = await Promise.all(Array.from({ length: chunks }, (_, i) => readDoc(db, eventId, `products_${i}`, tx)));
  const out = [];
  parts.forEach((part, i) => {
    if (!part) throw new CampaignContentUnavailable(eventId, `chunk ${i} missing`);
    if (part.version !== head.version) throw new CampaignContentUnavailable(eventId, `chunk ${i} has another version`);
    out.push(...strings(part.items));
  });
  if (Number.isFinite(head.count) && head.count !== out.length) {
    throw new CampaignContentUnavailable(eventId, `expected ${head.count} products, got ${out.length}`);
  }
  return out;
}

async function readPrompt(db, eventId, { tx } = {}) {
  const doc = await readDoc(db, eventId, "prompt", tx);
  if (!doc) throw new CampaignContentUnavailable(eventId, "prompt doc missing");
  return typeof doc.text === "string" ? doc.text : "";
}

/**
 * The campaign data with requiredProducts (and customPrompt unless
 * prompt: false) filled in. Returns [data] itself when nothing is external.
 * Pass tx to read inside a transaction (call it before any write).
 */
async function withCampaignContent(db, eventId, data, { tx, prompt = true } = {}) {
  if (!data) return data;
  const wantProducts = needsExternal(data, "requiredProducts");
  const wantPrompt = prompt && needsExternal(data, "customPrompt");
  if (!wantProducts && !wantPrompt) return data;
  const [products, text] = await Promise.all([
    wantProducts ? readProducts(db, eventId, { tx }) : null,
    wantPrompt ? readPrompt(db, eventId, { tx }) : null,
  ]);
  const out = Object.assign({}, data);
  if (wantProducts) out.requiredProducts = products;
  if (wantPrompt) out.customPrompt = text;
  return out;
}


// Same limits as CampaignContentRepository (Dart).
const INLINE_LIMIT_BYTES = 256 * 1024;
const CHUNK_LIMIT_BYTES = 700 * 1024;
const PROMPT_LIMIT_BYTES = 900 * 1024;

const bytes = (value) => Buffer.byteLength(typeof value === "string" ? value : JSON.stringify(value), "utf8");

function chunkProducts(items, limit = CHUNK_LIMIT_BYTES) {
  const out = [];
  let current = [];
  let size = 2;
  for (const item of items) {
    const itemBytes = bytes(JSON.stringify(item)) + 1;
    if (current.length && size + itemBytes > limit) {
      out.push(current);
      current = [];
      size = 2;
    }
    current.push(item);
    size += itemBytes;
  }
  if (current.length || !out.length) out.push(current);
  return out;
}

/**
 * Content docs + campaign fields for one write at [version] (mirrors
 * CampaignContentRepository.plan). Inline keys of a large campaign are
 * returned in deleteFields. [ts] is the timestamp value to store.
 */
function planContentWrite({ products, prompt, version, previousChunks = 0, ts = null }) {
  if (bytes(prompt) > PROMPT_LIMIT_BYTES) throw new Error("prompt larger than 900KB");
  const single = bytes(products) <= CHUNK_LIMIT_BYTES;
  const parts = single ? [products] : chunkProducts(products);
  const chunks = single ? 0 : parts.length;
  const docs = {
    products: { items: single ? products : [], count: products.length, version, chunks, updatedAt: ts },
    prompt: { text: prompt, version, updatedAt: ts },
  };
  if (!single) parts.forEach((items, index) => { docs[`products_${index}`] = { items, index, version, updatedAt: ts }; });
  const deletes = [];
  for (let i = chunks; i < previousChunks; i++) deletes.push(`products_${i}`);
  const inline = bytes(products) + bytes(prompt) <= INLINE_LIMIT_BYTES;
  const eventFields = { hasExternalContent: true, contentVersion: version, contentChunks: chunks, requiredProductsCount: products.length };
  if (inline) Object.assign(eventFields, { requiredProducts: products, customPrompt: prompt });
  return { docs, deletes, inline, eventFields, deleteFields: inline ? [] : ["requiredProducts", "customPrompt"] };
}

module.exports = {
  INLINE_LIMIT_BYTES,
  CHUNK_LIMIT_BYTES,
  PROMPT_LIMIT_BYTES,
  bytes,
  chunkProducts,
  planContentWrite,
  CampaignContentUnavailable,
  needsExternal,
  readProducts,
  readPrompt,
  withCampaignContent,
};
