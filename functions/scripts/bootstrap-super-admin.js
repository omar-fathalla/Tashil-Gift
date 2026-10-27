/**
 * One-time bootstrap: grant the super_admin custom claim.
 *
 * Default email: support@sw-point.com
 * Override: SUPER_ADMIN_EMAIL=other@example.com node scripts/bootstrap-super-admin.js
 *       or: node scripts/bootstrap-super-admin.js other@example.com
 *
 * The Firebase Auth user must already exist (email/password created in the
 * console or Admin SDK). This script never creates a user and never sets a
 * password.
 *
 * Auth: Application Default Credentials, or
 *   gcloud auth application-default login
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *
 * Run from the functions directory:
 *   node scripts/bootstrap-super-admin.js
 */
const admin = require("../admin_sdk");

const DEFAULT_SUPER_ADMIN_EMAIL = "support@sw-point.com";

function resolveEmail() {
  const fromArg = process.argv[2] && !process.argv[2].startsWith("-")
    ? process.argv[2].trim()
    : "";
  const fromEnv = (process.env.SUPER_ADMIN_EMAIL || "").trim();
  return (fromArg || fromEnv || DEFAULT_SUPER_ADMIN_EMAIL).toLowerCase();
}

async function main() {
  const email = resolveEmail();
  if (!email.includes("@")) {
    console.error("SUPER_ADMIN_EMAIL must be an email address.");
    process.exit(1);
  }

  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "tashil-gift",
    });
  }

  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (err) {
    console.error(`No Firebase Auth user for ${email}.`);
    console.error("Create that email/password user in Firebase Authentication first, then re-run this script.");
    console.error("This script does not create users and does not set a password.");
    process.exit(1);
  }

  const claims = Object.assign({}, user.customClaims || {}, { role: "super_admin" });
  delete claims.companySlug;
  delete claims.partnerAccess;
  await admin.auth().setCustomUserClaims(user.uid, claims);

  await admin.firestore().collection("admins").doc(email).set({
    uid: user.uid,
    email,
    role: "super_admin",
    bootstrappedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log(`Granted super_admin to ${email} (uid ${user.uid}).`);
  console.log("The user must sign out and sign in again so the ID token picks up the claim.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
