const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("./admin_sdk");
const { formatInternationalPhone } = require("./waha_webhook");

const callableOptions = {
  region: "us-central1",
  memory: "256MiB",
  enforceAppCheck: true,
};

const TEMPLATE_KEYS = ["verified", "pendingReview", "rejected", "notAllowed", "registered"];

function assertWebhookStaff(request) {
  if (!request || request.app == null) {
    throw new HttpsError("failed-precondition", "App Check token is required.");
  }
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sign-in is required.");
  }
  const role = (request.auth.token && request.auth.token.role) || "";
  if (role !== "super_admin" && role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Only a super_admin or admin can manage the WhatsApp webhook.",
    );
  }
}

function cleanText(value, max) {
  return String(value == null ? "" : value).trim().slice(0, max);
}

function requireCampaignId(value) {
  const campaignId = cleanText(value, 128);
  if (!campaignId || /[/\s]/.test(campaignId)) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }
  return campaignId;
}

function normalizeJoinCode(value) {
  const code = cleanText(value, 16).toUpperCase();
  if (!code) return "";
  if (!/^[A-Z0-9]{4,16}$/.test(code)) {
    throw new HttpsError("invalid-argument", "joinCode must be 4-16 letters or digits.");
  }
  return code;
}

async function applyWebhookConfigUpdate(db, data, serverTimestamp) {
  const input = data || {};
  const patch = {};
  if (typeof input.enabled === "boolean") patch.enabled = input.enabled;
  if (typeof input.autoRepliesEnabled === "boolean") patch.autoRepliesEnabled = input.autoRepliesEnabled;
  if (typeof input.allowListOnly === "boolean") patch.allowListOnly = input.allowListOnly;
  if (input.businessNumber != null) {
    const digits = formatInternationalPhone(input.businessNumber);
    if (digits && (digits.length < 8 || digits.length > 15)) {
      throw new HttpsError("invalid-argument", "businessNumber is not a valid phone.");
    }
    patch.businessNumber = digits;
  }
  if (input.businessDisplayName != null) {
    patch.businessDisplayName = cleanText(input.businessDisplayName, 80);
  }
  if (input.templates && typeof input.templates === "object") {
    const templates = {};
    for (const key of TEMPLATE_KEYS) {
      if (input.templates[key] != null) templates[key] = cleanText(input.templates[key], 1000);
    }
    patch.templates = templates;
  }
  patch.updatedAt = typeof serverTimestamp === "function"
    ? serverTimestamp()
    : admin.firestore.FieldValue.serverTimestamp();

  if (input.campaign && typeof input.campaign === "object") {
    const campaignId = requireCampaignId(input.campaign.campaignId);
    const joinCode = normalizeJoinCode(input.campaign.joinCode);
    if (joinCode) {
      const clash = await db.collection("whatsapp_webhook_campaigns")
        .where("joinCode", "==", joinCode)
        .limit(5)
        .get();
      const docs = clash && clash.docs ? clash.docs : [];
      if (docs.some((docSnap) => docSnap.id !== campaignId)) {
        throw new HttpsError("already-exists", "This join code is already used by another campaign.");
      }
    }
    await db.collection("whatsapp_webhook_campaigns").doc(campaignId).set({
      campaignId,
      campaignName: cleanText(input.campaign.campaignName, 120),
      companySlug: cleanText(input.campaign.companySlug, 80).toLowerCase(),
      selfRegistrationEnabled: input.campaign.selfRegistrationEnabled === true,
      joinCode,
      prizeIdentifier: cleanText(input.campaign.prizeIdentifier, 200),
      updatedAt: patch.updatedAt,
    }, { merge: true });
  }

  await db.collection("whatsapp_webhook_config").doc("default").set(patch, { merge: true });
  return { ok: true };
}

async function applySenderLinkChange(db, data, serverTimestamp) {
  const input = data || {};
  const action = cleanText(input.action, 16) || "upsert";
  const phone = formatInternationalPhone(input.phone);
  if (!phone || phone.length < 8 || phone.length > 15) {
    throw new HttpsError("invalid-argument", "A valid phone number is required.");
  }
  const ref = db.collection("whatsapp_sender_links").doc(phone);
  const stamp = typeof serverTimestamp === "function"
    ? serverTimestamp()
    : admin.firestore.FieldValue.serverTimestamp();
  if (action === "delete") {
    await ref.delete();
    return { ok: true, phone, deleted: true };
  }
  if (action !== "upsert") {
    throw new HttpsError("invalid-argument", "action must be upsert or delete.");
  }
  const campaignId = requireCampaignId(input.campaignId);
  await ref.set({
    phone,
    campaignId,
    campaignName: cleanText(input.campaignName, 120),
    companySlug: cleanText(input.companySlug, 80).toLowerCase(),
    prizeIdentifier: cleanText(input.prizeIdentifier, 200),
    displayName: cleanText(input.displayName, 80),
    active: input.active !== false,
    registeredVia: "admin",
    updatedAt: stamp,
  }, { merge: true });
  return { ok: true, phone, campaignId };
}

const updateWhatsappWebhookConfig = onCall(callableOptions, async (request) => {
  assertWebhookStaff(request);
  return applyWebhookConfigUpdate(admin.firestore(), request.data || {});
});

const manageWhatsappSenderLink = onCall(callableOptions, async (request) => {
  assertWebhookStaff(request);
  return applySenderLinkChange(admin.firestore(), request.data || {});
});

module.exports = {
  assertWebhookStaff,
  applyWebhookConfigUpdate,
  applySenderLinkChange,
  updateWhatsappWebhookConfig,
  manageWhatsappSenderLink,
};
