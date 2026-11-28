/**
 * TAG-62: events/{id}/content/{doc} (campaign products / AI prompt).
 * Read like the campaign (admin, anonymous rep while active, same-company
 * partner); write by admins only. Includes a Unilever-sized campaign
 * (3,636 products + ~145k-char prompt) and a 10,000-product chunked one.
 */
const fs = require("fs");
const path = require("path");
const { assertFails, assertSucceeds, initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, collection, getDocs } = require("firebase/firestore");

let testEnv;
const db = (uid, claims) => testEnv.authenticatedContext(uid, claims).firestore();
const admin = () => db("admin-1", { role: "admin", email: "ops@example.com" });
const partner = (slug = "acme") => db("partner-1", { role: "partner", companySlug: slug, partnerAccess: "read" });
const partnerOps = () => db("partner-ops", { role: "partner", companySlug: "acme", partnerAccess: "ops" });
const anon = () => db("rep-1", { firebase: { sign_in_provider: "anonymous", identities: {} } });

const products = (n) => Array.from({ length: n }, (_, i) => `منتج يونيليفر رقم ${i} - عبوة 250 جم - منظف متعدد الاستخدامات`);
const UNILEVER = products(3636);
const PROMPT = "تعليمات فحص الفاتورة ".repeat(7000);

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-tashil-gift",
    firestore: { rules: fs.readFileSync(path.resolve(__dirname, "..", "firestore.rules"), "utf8") },
  });
});
afterAll(async () => { await testEnv.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    const meta = { hasExternalContent: true, contentVersion: 1, contentChunks: 0, requiredProductsCount: UNILEVER.length };
    await setDoc(doc(d, "events/uni"), { companySlug: "acme", isActive: true, eventName: "Unilever", ...meta });
    await setDoc(doc(d, "events/uni-off"), { companySlug: "acme", isActive: false, eventName: "Paused", ...meta });
    for (const id of ["uni", "uni-off"]) {
      await setDoc(doc(d, `events/${id}/content/products`), { items: UNILEVER, count: UNILEVER.length, version: 1, chunks: 0 });
      await setDoc(doc(d, `events/${id}/content/prompt`), { text: PROMPT, version: 1 });
    }
  });
});

describe("TAG-62 campaign content rules", () => {
  test("anonymous rep reads content of an active campaign only", async () => {
    const snap = await assertSucceeds(getDoc(doc(anon(), "events/uni/content/products")));
    expect(snap.data().items.length).toBe(3636);
    await assertSucceeds(getDoc(doc(anon(), "events/uni/content/prompt")));
    await assertFails(getDoc(doc(anon(), "events/uni-off/content/products")));
    await assertFails(getDoc(doc(anon(), "events/missing/content/products")));
  });

  test("partner reads only their company's content; nobody but admins writes", async () => {
    await assertSucceeds(getDoc(doc(partner(), "events/uni-off/content/prompt")));
    await assertFails(getDoc(doc(partner("other-co"), "events/uni/content/prompt")));
    for (const ctx of [anon(), partner(), partnerOps()]) {
      await assertFails(setDoc(doc(ctx, "events/uni/content/products"), { items: [], count: 0, version: 2 }));
      await assertFails(updateDoc(doc(ctx, "events/uni/content/prompt"), { text: "x" }));
      await assertFails(deleteDoc(doc(ctx, "events/uni/content/prompt")));
    }
    await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), "events/uni/content/prompt")));
  });

  test("admin creates a 10,000-product campaign with chunked content in one batch, edits and deletes it", async () => {
    const list = products(10000);
    const half = Math.ceil(list.length / 2);
    const a = admin();
    const batch = writeBatch(a);
    batch.set(doc(a, "events/big"), { companySlug: "acme", isActive: true, eventName: "Big", hasExternalContent: true, contentVersion: 1, contentChunks: 2, requiredProductsCount: list.length });
    batch.set(doc(a, "events/big/content/products"), { items: [], count: list.length, version: 1, chunks: 2 });
    batch.set(doc(a, "events/big/content/products_0"), { items: list.slice(0, half), index: 0, version: 1 });
    batch.set(doc(a, "events/big/content/products_1"), { items: list.slice(half), index: 1, version: 1 });
    batch.set(doc(a, "events/big/content/prompt"), { text: PROMPT, version: 1 });
    await assertSucceeds(batch.commit());

    const listed = await assertSucceeds(getDocs(collection(anon(), "events/big/content")));
    expect(listed.size).toBe(4);
    await assertSucceeds(updateDoc(doc(a, "events/big/content/prompt"), { text: "جديد", version: 2 }));
    await assertSucceeds(deleteDoc(doc(a, "events/big/content/products_1")));
  });
});

describe("TAG-65 large draft content rules", () => {
  test("admin writes a draft with chunked content in one batch; nobody else reads or writes it", async () => {
    const a = admin();
    const list = products(10000);
    const half = Math.ceil(list.length / 2);
    const batch = writeBatch(a);
    batch.set(doc(a, "event_drafts/d1"), { eventName: "Big", companySlug: "acme", event: { eventName: "Big" }, base: null,
      externalContent: { version: 7, event: { chunks: 2, count: list.length }, base: null } });
    batch.set(doc(a, "event_drafts/d1/content/event_products_0"), { items: list.slice(0, half), index: 0, version: 7 });
    batch.set(doc(a, "event_drafts/d1/content/event_products_1"), { items: list.slice(half), index: 1, version: 7 });
    batch.set(doc(a, "event_drafts/d1/content/event_prompt"), { text: PROMPT, version: 7 });
    await assertSucceeds(batch.commit());
    const all = await assertSucceeds(getDocs(collection(a, "event_drafts/d1/content")));
    expect(all.size).toBe(3);

    for (const ctx of [partner(), partnerOps(), anon(), testEnv.unauthenticatedContext().firestore()]) {
      await assertFails(getDoc(doc(ctx, "event_drafts/d1/content/event_prompt")));
      await assertFails(setDoc(doc(ctx, "event_drafts/d1/content/event_products_0"), { items: [], index: 0, version: 8 }));
    }
    await assertSucceeds(deleteDoc(doc(a, "event_drafts/d1/content/event_products_1")));
  });
});
