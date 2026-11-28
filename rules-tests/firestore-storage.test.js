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
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  query,
  where,
  getDocs,
  serverTimestamp,
} = require("firebase/firestore");
const { ref, uploadBytes, getBytes, listAll, deleteObject, updateMetadata } = require("firebase/storage");

const PROJECT_ID = "demo-tashil-gift";
const RULES_DIR = path.resolve(__dirname, "..");

let testEnv;

function contextFor(uid, claims) {
  return testEnv.authenticatedContext(uid, claims);
}

function authedDb(uid, claims) {
  return contextFor(uid, claims).firestore();
}

const superAdmin = () => authedDb("super-1", { role: "super_admin", email: "support@sw-point.com" });
const admin = () => authedDb("admin-1", { role: "admin", email: "ops@example.com" });
const partner = () => authedDb("partner-1", {
  role: "partner",
  companySlug: "acme",
  partnerAccess: "read",
  email: "partner@example.com",
});
const partnerOps = () => authedDb("partner-ops", {
  role: "partner",
  companySlug: "acme",
  partnerAccess: "ops",
  email: "ops-partner@example.com",
});
const anon = () => authedDb("rep-1", {
  firebase: { sign_in_provider: "anonymous", identities: {} },
});
const otherAnon = () => authedDb("rep-2", {
  firebase: { sign_in_provider: "anonymous", identities: {} },
});

function receiptPayload(overrides = {}) {
  return {
    submittedByUid: "rep-1",
    campaignId: "camp-1",
    companySlug: "acme",
    receipt_number: "R-100",
    status: "accepted",
    is_valid: true,
    total_value: 120,
    customerName: "عميل",
    customerPhone: "01000000000",
    extracted_products: [],
    game_played: false,
    timestamp: serverTimestamp(),
    ...overrides,
  };
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(RULES_DIR, "firestore.rules"), "utf8"),
    },
    storage: {
      rules: fs.readFileSync(path.join(RULES_DIR, "storage.rules"), "utf8"),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "events/camp-1"), {
      companySlug: "acme",
      isActive: true,
      eventName: "Active campaign",
    });
    await setDoc(doc(db, "events/camp-off"), {
      companySlug: "acme",
      isActive: false,
      eventName: "Paused campaign",
    });
    await setDoc(doc(db, "events/other-camp"), {
      companySlug: "other-co",
      isActive: true,
      eventName: "Other company",
    });
    await setDoc(doc(db, "companies/acme"), {
      slug: "acme",
      brandManagerPassword: "secret-brand",
    });
    await setDoc(doc(db, "company_gifts/gift-1"), {
      companySlug: "acme",
      giftName: "Voucher",
      availableQuantity: 10,
    });
    await setDoc(doc(db, "admins/support@sw-point.com"), {
      email: "support@sw-point.com",
      role: "super_admin",
    });
    await setDoc(doc(db, "portal_credentials/acme"), {
      companySlug: "acme",
      password: "do-not-leak",
    });
    await setDoc(doc(db, "receipts_transactions/owned"), {
      submittedByUid: "rep-1",
      campaignId: "camp-1",
      companySlug: "acme",
      receipt_number: "OWN-1",
      status: "accepted",
    });
    await setDoc(doc(db, "event_drafts/draft-1"), {
      sourceEventId: null,
      eventName: "Draft campaign",
      companySlug: "acme",
      event: { companySlug: "acme", isActive: true, eventName: "Draft campaign" },
    });
    await setDoc(doc(db, "receipts_transactions/foreign"), {
      submittedByUid: "rep-2",
      campaignId: "camp-1",
      companySlug: "acme",
      receipt_number: "FOR-1",
      status: "accepted",
    });
  });
});

describe("anonymous field reps", () => {
  test("can read one active campaign and not an inactive one", async () => {
    await assertSucceeds(getDoc(doc(anon(), "events/camp-1")));
    await assertFails(getDoc(doc(anon(), "events/camp-off")));
  });

  test("can list only active campaigns", async () => {
    const activeQuery = query(collection(anon(), "events"), where("isActive", "==", true));
    await assertSucceeds(getDocs(activeQuery));
    await assertFails(getDocs(collection(anon(), "events")));
  });

  test("creates a receipt only for an active campaign and only as themselves", async () => {
    await assertSucceeds(setDoc(doc(anon(), "receipts_transactions/new-1"), receiptPayload()));
    await assertFails(setDoc(doc(anon(), "receipts_transactions/bad-uid"), receiptPayload({
      submittedByUid: "someone-else",
    })));
    await assertFails(setDoc(doc(anon(), "receipts_transactions/paused"), receiptPayload({
      campaignId: "camp-off",
    })));
    await assertFails(setDoc(doc(anon(), "receipts_transactions/missing"), receiptPayload({
      campaignId: "does-not-exist",
    })));
    await assertFails(setDoc(doc(anon(), "receipts_transactions/wrong-company"), receiptPayload({
      companySlug: "other-co",
      campaignId: "camp-1",
    })));
  });

  test("reads only their own receipt and cannot update or delete it", async () => {
    await assertSucceeds(getDoc(doc(anon(), "receipts_transactions/owned")));
    await assertFails(getDoc(doc(anon(), "receipts_transactions/foreign")));
    const ownQuery = query(
      collection(anon(), "receipts_transactions"),
      where("submittedByUid", "==", "rep-1"),
    );
    await assertSucceeds(getDocs(ownQuery));
    await assertFails(getDocs(collection(anon(), "receipts_transactions")));
    await assertFails(updateDoc(doc(anon(), "receipts_transactions/owned"), { prize_won: "stolen" }));
    await assertFails(deleteDoc(doc(anon(), "receipts_transactions/owned")));
  });

  test("cannot read customers, inventory, credentials, or admins", async () => {
    await assertFails(getDoc(doc(anon(), "companies/acme")));
    await assertFails(getDoc(doc(anon(), "company_gifts/gift-1")));
    await assertFails(getDoc(doc(anon(), "portal_credentials/acme")));
    await assertFails(getDoc(doc(anon(), "admins/support@sw-point.com")));
    await assertFails(getDocs(collection(anon(), "marketing_contacts")));
    await assertFails(setDoc(doc(anon(), "company_gifts/gift-1"), { availableQuantity: 0 }));
  });
});

describe("staff and partner claims", () => {
  test("admin can operate campaigns and receipts but not credential collections", async () => {
    await assertSucceeds(getDoc(doc(admin(), "events/camp-1")));
    await assertSucceeds(getDoc(doc(admin(), "receipts_transactions/foreign")));
    await assertSucceeds(updateDoc(doc(admin(), "events/camp-1"), { eventName: "Renamed" }));
    await assertFails(getDoc(doc(admin(), "portal_credentials/acme")));
    await assertFails(getDoc(doc(admin(), "admins/support@sw-point.com")));
    await assertFails(setDoc(doc(admin(), "admins/new@example.com"), { role: "admin" }));
  });

  test("TAG-18: the dashboard switch status fields are written by admins only, with their own uid and server time", async () => {
    const sw = (db, active, uid) => updateDoc(doc(db, "events/camp-off"), {
      isActive: active,
      pausedManually: !active,
      statusUpdatedAt: serverTimestamp(),
      statusUpdatedBy: uid,
    });
    await assertSucceeds(sw(admin(), true, "admin-1"));
    await assertSucceeds(sw(admin(), false, "admin-1"));
    // Someone else's uid, a system actor name, or a client clock are refused.
    await assertFails(sw(admin(), true, "super-1"));
    await assertFails(sw(admin(), true, "system:auto-activate"));
    await assertFails(updateDoc(doc(admin(), "events/camp-off"), {
      isActive: true, pausedManually: false, statusUpdatedAt: new Date(), statusUpdatedBy: "admin-1",
    }));
    await assertSucceeds(sw(superAdmin(), true, "super-1"));
    await assertFails(updateDoc(doc(admin(), "events/camp-off"), { pausedManually: "yes" }));
    // Nobody but staff writes campaigns.
    await assertFails(sw(partnerOps(), true, "partner-ops"));
    await assertFails(sw(partner(), true, "partner-1"));
    await assertFails(sw(anon(), true, "rep-1"));
    // An edit that does not touch the status fields keeps working after a system write.
    await testEnv.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), "events/camp-1"), {
      statusUpdatedBy: "system:auto-activate", statusUpdatedAt: new Date(),
    }));
    await assertSucceeds(updateDoc(doc(admin(), "events/camp-1"), { eventName: "Renamed again", updatedBy: "admin-1" }));
    // Creating a campaign without the status fields is unchanged.
    await assertSucceeds(setDoc(doc(admin(), "events/new-camp"), { eventName: "New", companySlug: "acme", isActive: true }));
    await assertFails(setDoc(doc(admin(), "events/new-camp-2"), {
      eventName: "New", companySlug: "acme", isActive: true, statusUpdatedBy: "someone-else",
    }));
  });

  test("super_admin can read and write admins and portal credentials", async () => {
    await assertSucceeds(getDoc(doc(superAdmin(), "portal_credentials/acme")));
    await assertSucceeds(setDoc(doc(superAdmin(), "admins/ops@example.com"), {
      email: "ops@example.com",
      role: "admin",
    }));
  });

  test("partner is limited to their company and cannot see credentials", async () => {
    await assertSucceeds(getDoc(doc(partner(), "events/camp-1")));
    await assertFails(getDoc(doc(partner(), "events/other-camp")));
    await assertSucceeds(getDoc(doc(partner(), "receipts_transactions/owned")));
    await assertFails(getDoc(doc(partner(), "companies/acme")));
    await assertFails(getDoc(doc(partner(), "portal_credentials/acme")));
    await assertFails(updateDoc(doc(partner(), "company_gifts/gift-1"), { availableQuantity: 0 }));
    await assertFails(updateDoc(doc(partner(), "receipts_transactions/owned"), { status: "rejected" }));
    await assertSucceeds(updateDoc(doc(partnerOps(), "receipts_transactions/owned"), { status: "rejected" }));
  });

  test("whatsapp webhook collections are readable by staff and not writable by clients", async () => {
    const paths = [
      "whatsapp_inbound_messages/msg-1",
      "whatsapp_message_status/msg-1",
      "whatsapp_outbox/msg-1",
      "whatsapp_sender_links/201012345678",
      "whatsapp_webhook_config/default",
      "whatsapp_webhook_campaigns/camp-1",
    ];
    for (const path of paths) {
      await assertSucceeds(getDoc(doc(superAdmin(), path)));
      await assertSucceeds(getDoc(doc(admin(), path)));
      await assertFails(setDoc(doc(superAdmin(), path), { status: "stored" }));
      await assertFails(setDoc(doc(admin(), path), { status: "stored" }));
      await assertFails(getDoc(doc(partner(), path)));
      await assertFails(getDoc(doc(anon(), path)));
    }
  });

  function supervisorPayload(overrides = {}) {
    return {
      name: "مشرف تجريبي Test Supervisor",
      alternateNames: ["اسم بديل"],
      mobile: "01099999997",
      cleanPhone: "201099999997",
      source: "excel_import",
      audience: "company_supervisors",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...overrides,
    };
  }

  test("company supervisors are readable and writable only by staff", async () => {
    const ref = (db) => doc(db, "company_supervisors/01099999997");
    await assertSucceeds(setDoc(ref(admin()), supervisorPayload()));
    await assertSucceeds(getDoc(ref(admin())));
    await assertSucceeds(getDocs(collection(superAdmin(), "company_supervisors")));
    await assertSucceeds(updateDoc(ref(superAdmin()), { name: "مشرف تجريبي Test Supervisor" }));
    await assertFails(setDoc(ref(admin()), supervisorPayload({ mobile: "01000000000" })));
    await assertFails(setDoc(ref(partner()), supervisorPayload()));
    await assertFails(getDoc(ref(partner())));
    await assertFails(getDoc(ref(partnerOps())));
    await assertFails(getDocs(collection(anon(), "company_supervisors")));
    await assertFails(getDoc(ref(anon())));
    const publicDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(publicDb, "company_supervisors/01099999997")));
    await assertSucceeds(deleteDoc(ref(admin())));
  });

  test("unauthenticated clients cannot read or write", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "events/camp-1")));
    await assertFails(setDoc(doc(db, "receipts_transactions/nope"), receiptPayload()));
  });

  test("loginThrottle is server-only for every client", async () => {
    const dbs = [superAdmin(), admin(), partnerOps(), anon(), testEnv.unauthenticatedContext().firestore()];
    for (const db of dbs) {
      await assertFails(getDoc(doc(db, "loginThrottle/abc")));
      await assertFails(getDocs(collection(db, "loginThrottle")));
      await assertFails(setDoc(doc(db, "loginThrottle/abc"), { failures: 0 }));
      await assertFails(deleteDoc(doc(db, "loginThrottle/abc")));
    }
  });
});

describe("C-05 campaign drafts", () => {
  test("admin and super_admin can create, read, list, update and delete drafts", async () => {
    for (const db of [admin(), superAdmin()]) {
      await assertSucceeds(getDoc(doc(db, "event_drafts/draft-1")));
      await assertSucceeds(getDocs(collection(db, "event_drafts")));
      await assertSucceeds(setDoc(doc(db, "event_drafts/new-draft"), { eventName: "New", event: {} }));
      await assertSucceeds(updateDoc(doc(db, "event_drafts/new-draft"), { eventName: "Renamed" }));
      await assertSucceeds(deleteDoc(doc(db, "event_drafts/new-draft")));
    }
  });

  test("reps, partners and signed-out clients cannot see or write drafts", async () => {
    const unauth = testEnv.unauthenticatedContext().firestore();
    for (const db of [anon(), partner(), partnerOps(), unauth]) {
      await assertFails(getDoc(doc(db, "event_drafts/draft-1")));
      await assertFails(getDocs(collection(db, "event_drafts")));
      await assertFails(getDocs(query(collection(db, "event_drafts"), where("companySlug", "==", "acme"))));
      await assertFails(setDoc(doc(db, "event_drafts/x"), { eventName: "x" }));
      await assertFails(updateDoc(doc(db, "event_drafts/draft-1"), { eventName: "x" }));
      await assertFails(deleteDoc(doc(db, "event_drafts/draft-1")));
    }
  });

  test("a draft is not a campaign: no receipt can be filed against it", async () => {
    await assertFails(getDoc(doc(anon(), "events/draft-1")));
    await assertFails(setDoc(doc(anon(), "receipts_transactions/on-draft"), receiptPayload({ campaignId: "draft-1" })));
  });
});

describe("storage rules", () => {
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

  test("anonymous rep can upload and read only their receipt image", async () => {
    const rep = contextFor("rep-1", {
      firebase: { sign_in_provider: "anonymous", identities: {} },
    });
    const other = contextFor("rep-2", {
      firebase: { sign_in_provider: "anonymous", identities: {} },
    });
    const file = ref(rep.storage(), "receipts/acme/camp-1/R-100.jpg");
    await assertSucceeds(uploadBytes(file, jpeg, {
      contentType: "image/jpeg",
      customMetadata: { uploaderUid: "rep-1" },
    }));
    await assertSucceeds(getBytes(file));
    await assertFails(getBytes(ref(other.storage(), "receipts/acme/camp-1/R-100.jpg")));
    await assertFails(uploadBytes(ref(rep.storage(), "company_logos/logo.jpg"), jpeg, {
      contentType: "image/jpeg",
    }));
  });

  test("uploads require auth and staff can read receipt images", async () => {
    const guest = testEnv.unauthenticatedContext();
    await assertFails(uploadBytes(ref(guest.storage(), "receipts/acme/camp-1/x.jpg"), jpeg, {
      contentType: "image/jpeg",
      customMetadata: { uploaderUid: "rep-1" },
    }));
    await assertFails(uploadBytes(ref(guest.storage(), "anywhere/secret.txt"), new Uint8Array([1]), {
      contentType: "text/plain",
    }));

    const rep = contextFor("rep-1", {
      firebase: { sign_in_provider: "anonymous", identities: {} },
    });
    await uploadBytes(ref(rep.storage(), "receipts/acme/camp-1/staff-read.jpg"), jpeg, {
      contentType: "image/jpeg",
      customMetadata: { uploaderUid: "rep-1" },
    });
    const staff = contextFor("admin-1", { role: "admin" });
    await assertSucceeds(getBytes(ref(staff.storage(), "receipts/acme/camp-1/staff-read.jpg")));
  });

  test("catch-all paths are denied", async () => {
    const staff = contextFor("super-1", { role: "super_admin" });
    await assertFails(uploadBytes(ref(staff.storage(), "private/note.txt"), new Uint8Array([1]), {
      contentType: "text/plain",
    }));
  });

  test("SVG uploads are rejected even for staff (L3)", async () => {
    const staff = contextFor("super-1", { role: "super_admin" });
    const svg = new TextEncoder().encode("<svg xmlns='http://www.w3.org/2000/svg'/>");
    await assertFails(uploadBytes(ref(staff.storage(), "company_logos/x.svg"), svg, {
      contentType: "image/svg+xml",
    }));
    await assertSucceeds(uploadBytes(ref(staff.storage(), "company_logos/x.png"), jpeg, {
      contentType: "image/png",
    }));
  });
});

describe("whatsapp campaign media storage", () => {
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34]);
  const adminPath = "whatsapp_campaign_media/admin-1/1731440000000_offer.pdf";

  function asAdmin() {
    return contextFor("admin-1", { role: "admin" });
  }

  function asSuper() {
    return contextFor("super-1", { role: "super_admin" });
  }

  function asPartner() {
    return contextFor("partner-1", {
      role: "partner",
      companySlug: "acme",
      partnerAccess: "read",
    });
  }

  function asAnon() {
    return contextFor("rep-1", {
      firebase: { sign_in_provider: "anonymous", identities: {} },
    });
  }

  test("admin and super_admin can upload a PDF or image under their own uid", async () => {
    await assertSucceeds(uploadBytes(ref(asAdmin().storage(), adminPath), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "admin-1" },
    }));
    await assertSucceeds(uploadBytes(
      ref(asSuper().storage(), "whatsapp_campaign_media/super-1/1731440000001_poster.jpg"),
      jpeg,
      {
        contentType: "image/jpeg",
        customMetadata: { uploaderUid: "super-1" },
      },
    ));
    await assertSucceeds(uploadBytes(
      ref(asAdmin().storage(), "whatsapp_campaign_media/admin-1/1731440000002_poster.png"),
      jpeg,
      {
        contentType: "image/png",
        customMetadata: { uploaderUid: "admin-1" },
      },
    ));
    await assertSucceeds(uploadBytes(
      ref(asAdmin().storage(), "whatsapp_campaign_media/admin-1/1731440000003_poster.webp"),
      jpeg,
      {
        contentType: "image/webp",
        customMetadata: { uploaderUid: "admin-1" },
      },
    ));
  });

  test("partners, anonymous users, and the public cannot upload, read, or list", async () => {
    await assertSucceeds(uploadBytes(ref(asAdmin().storage(), adminPath), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "admin-1" },
    }));

    await assertFails(uploadBytes(ref(asPartner().storage(), "whatsapp_campaign_media/partner-1/1_offer.pdf"), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "partner-1" },
    }));
    await assertFails(uploadBytes(ref(asAnon().storage(), "whatsapp_campaign_media/rep-1/1_offer.pdf"), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "rep-1" },
    }));
    const guest = testEnv.unauthenticatedContext();
    await assertFails(uploadBytes(ref(guest.storage(), adminPath), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "admin-1" },
    }));

    await assertFails(getBytes(ref(asPartner().storage(), adminPath)));
    await assertFails(getBytes(ref(asAnon().storage(), adminPath)));
    await assertFails(getBytes(ref(guest.storage(), adminPath)));
    await assertSucceeds(getBytes(ref(asSuper().storage(), adminPath)));

    await assertFails(listAll(ref(asAdmin().storage(), "whatsapp_campaign_media")));
    await assertFails(listAll(ref(asAdmin().storage(), "whatsapp_campaign_media/admin-1")));
    await assertFails(listAll(ref(guest.storage(), "whatsapp_campaign_media")));
    await assertFails(listAll(ref(asPartner().storage(), "whatsapp_campaign_media")));
  });

  test("rejects another uid, a bad type, a missing owner, and overwrites", async () => {
    const admin = asAdmin();
    await assertFails(uploadBytes(
      ref(admin.storage(), "whatsapp_campaign_media/super-1/1_offer.pdf"),
      pdf,
      {
        contentType: "application/pdf",
        customMetadata: { uploaderUid: "admin-1" },
      },
    ));
    await assertFails(uploadBytes(ref(admin.storage(), adminPath), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "someone-else" },
    }));
    await assertFails(uploadBytes(ref(admin.storage(), adminPath), pdf, {
      contentType: "text/plain",
      customMetadata: { uploaderUid: "admin-1" },
    }));
    await assertFails(uploadBytes(ref(admin.storage(), "whatsapp_campaign_media/admin-1/1_notes.txt"), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "admin-1" },
    }));
    await assertFails(uploadBytes(ref(admin.storage(), "whatsapp_campaign_media/admin-1/1_anim.gif"), jpeg, {
      contentType: "image/gif",
      customMetadata: { uploaderUid: "admin-1" },
    }));
    await assertFails(uploadBytes(ref(admin.storage(), "company_logos/offer.pdf"), pdf, {
      contentType: "application/pdf",
    }));

    await assertSucceeds(uploadBytes(ref(admin.storage(), adminPath), pdf, {
      contentType: "application/pdf",
      customMetadata: { uploaderUid: "admin-1" },
    }));
    await assertFails(updateMetadata(ref(admin.storage(), adminPath), {
      contentType: "text/plain",
      customMetadata: { uploaderUid: "admin-1" },
    }));
    await assertSucceeds(deleteObject(ref(admin.storage(), adminPath)));
    await assertFails(deleteObject(ref(asPartner().storage(), adminPath)));
  });
});

describe("TAG-43 campaign save diagnostics", () => {
  const failure = (overrides = {}) => ({
    kind: "late_error",
    op: "create",
    code: "unavailable",
    message: "Failed to get document because the client is offline.",
    eventId: "evt-1",
    companySlug: "512",
    payloadBytes: 300000,
    elapsedMs: 15000,
    appVersion: "2.0.188+248",
    userAgent: "Mozilla/5.0",
    uid: "admin-1",
    createdAt: serverTimestamp(),
    ...overrides,
  });

  test("save_failures: admin create-only with small fixed fields", async () => {
    const db = admin();
    await assertSucceeds(setDoc(doc(db, "save_failures/f1"), failure()));
    await assertSucceeds(getDoc(doc(db, "save_failures/f1")));
    await assertFails(updateDoc(doc(db, "save_failures/f1"), { code: "x" }));
    await assertFails(deleteDoc(doc(db, "save_failures/f1")));
    await assertFails(setDoc(doc(db, "save_failures/f2"), failure({ uid: "someone-else" })));
    await assertFails(setDoc(doc(db, "save_failures/f3"), failure({ extra: "no" })));
    await assertFails(setDoc(doc(db, "save_failures/f4"), failure({ kind: "other" })));
    await assertFails(setDoc(doc(db, "save_failures/f5"), failure({ message: "x".repeat(501) })));
    await assertFails(setDoc(doc(db, "save_failures/f6"), failure({ createdAt: new Date(0) })));
    await assertFails(setDoc(doc(partner(), "save_failures/f7"), failure({ uid: "partner-1" })));
    await assertFails(setDoc(doc(anon(), "save_failures/f8"), failure({ uid: "rep-1" })));
    await assertFails(getDoc(doc(partner(), "save_failures/f1")));
  });

  // Mohamed's case: a NEW Unilever campaign, no gift stock allocated, active
  // at once, a long product list, saved after «تفعيل رغم التحذيرات».
  test("new zero-stock active Unilever campaign (~300KB) is allowed in one write", async () => {
    const db = admin();
    const products = Array.from({ length: 500 }, (_, i) => `منتج يونيليفر رقم ${i} شامبو كلير ضد القشرة 400 مل`);
    const rules = Array.from({ length: 120 }, (_, i) => ({
      id: `rule-${i}`,
      title: `قاعدة ${i}`,
      products: products.slice(0, 40),
      minimumSpend: 200,
    }));
    const event = {
      eventName: "حمله منتجات شركه يونيلفر",
      targetCompany: "يونيليفر",
      companySlug: "512",
      retailChainId: "fathalla",
      retailChainName: "أسواق فتح الله",
      branchIds: ["b1", "b2", "b3", "b4", "b5", "b6"],
      isActive: true,
      gameType: "instant",
      minimumSpend: 200,
      requiredProducts: products,
      promotionalRules: rules,
      allocatedPrizes: [],
      allowComplementaryReceipts: true,
      enableWhatsAppWinnerNotification: true,
      createdAt: serverTimestamp(),
      lastSaveToken: "tok-1",
    };
    const bytes = Buffer.byteLength(JSON.stringify(event));
    expect(bytes).toBeGreaterThan(250000);
    const t0 = Date.now();
    await assertSucceeds(setDoc(doc(db, "events/tag43-new"), event));
    // The edit path writes the token with the changed fields.
    await assertSucceeds(updateDoc(doc(db, "events/tag43-new"), { eventName: "renamed", updatedBy: "admin-1", updatedAt: serverTimestamp(), lastSaveToken: "tok-2" }));
    console.log(`TAG-43 zero-stock create+edit of ${bytes} bytes: ${Date.now() - t0}ms`);
    // Same doc for company "unilever" is equally allowed (rules do not look at the slug for admins).
    await assertSucceeds(setDoc(doc(db, "events/tag43-new-2"), { ...event, companySlug: "unilever" }));
  });
});
