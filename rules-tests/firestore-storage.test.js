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
const { ref, uploadBytes, getBytes } = require("firebase/storage");

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

  test("unauthenticated clients cannot read or write", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "events/camp-1")));
    await assertFails(setDoc(doc(db, "receipts_transactions/nope"), receiptPayload()));
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
});
