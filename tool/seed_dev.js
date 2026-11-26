#!/usr/bin/env node
/**
 * Seeds FAKE data into the DEV Firebase project (TAG-13, TAG-14, TAG-15).
 *
 * HARD-REFUSES anything but tashil-gift-dev or a local demo-* emulator
 * (see resolveSeedTarget in tool/seed_dev_lib.js). Production is never a
 * possible target: there is no default project and `tashil-gift` is rejected.
 *
 * Usage (from the repo root, after `cd functions && npm ci`):
 *   node tool/seed_dev.js --project tashil-gift-dev --dry-run
 *   GOOGLE_APPLICATION_CREDENTIALS=~/keys/tashil-gift-dev-seeder.json \
 *     node tool/seed_dev.js --project tashil-gift-dev --confirm tashil-gift-dev
 *   # local emulators:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
 *   FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 node tool/seed_dev.js --project demo-tashil-dev
 *
 * Options: --dry-run (print the plan, write nothing), --skip-storage,
 *          --skip-auth, --credentials-out <file> (write new passwords to a
 *          file instead of stdout; used by CI; existing portal passwords are
 *          included), --reset-passwords (give existing test users a new
 *          password; used by CI so a lost password is never a dead end). Optional env: DEV_ADMIN_PASSWORD (else a random one is
 *          generated and printed ONCE, when the user is first created).
 *
 * Idempotent: fixed document ids + merge writes; existing passwords are kept.
 * Details: docs/DEV_ENVIRONMENT.md.
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { createRequire } = require("node:module");
const { resolveSeedTarget, buildSeedData, assertFakeOnly, SeedRefused } = require("./seed_dev_lib");

const ROOT = path.resolve(__dirname, "..");
const RECEIPTS_DIR = path.join(__dirname, "dev_fixtures", "receipts");

function credentialsProjectId(env) {
  const file = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!file) return "";
  try {
    return JSON.parse(fs.readFileSync(file, "utf8")).project_id || "";
  } catch (_) {
    throw new SeedRefused(`Cannot read GOOGLE_APPLICATION_CREDENTIALS (${file}).`);
  }
}

function randomPassword(prefix) {
  return `${prefix}${crypto.randomBytes(9).toString("base64url")}`;
}

const FIXTURE = { isDevFixture: true, seededBy: "tool/seed_dev.js" };

async function main() {
  const argv = process.argv.slice(2);
  let target;
  try {
    target = resolveSeedTarget({ argv, env: process.env, credentialsProjectId: credentialsProjectId(process.env) });
  } catch (err) {
    if (err instanceof SeedRefused) {
      console.error(err.message);
      process.exit(2);
    }
    throw err;
  }
  const data = buildSeedData();
  assertFakeOnly(data);
  const skipStorage = argv.includes("--skip-storage");
  const skipAuth = argv.includes("--skip-auth");
  const resetPasswords = argv.includes("--reset-passwords");
  const outIdx = argv.indexOf("--credentials-out");
  const credentialsOut = outIdx >= 0 ? argv[outIdx + 1] : "";
  const receipts = fs.existsSync(RECEIPTS_DIR) ? fs.readdirSync(RECEIPTS_DIR).filter((f) => f.endsWith(".png")).sort() : [];

  console.log(`Target: ${target.projectId}${target.emulator ? " (local emulators)" : ""}${target.dryRun ? " [dry run]" : ""}`);
  console.log(`  companies ${data.companies.length}, retail_chains ${data.chains.length}, branches ${data.branches.length}, company_products ${data.products.length}`);
  console.log(`  company_gifts ${data.gifts.length}, events ${data.events.length}, event_drafts ${data.drafts.length}, auth users ${skipAuth ? 0 : data.users.length}`);
  console.log(`  receipt images ${skipStorage ? 0 : receipts.length} -> gs://<bucket>/dev_fixtures/receipts/`);
  if (target.dryRun) return;

  const fnRequire = createRequire(path.join(ROOT, "functions", "package.json"));
  const { initializeApp } = fnRequire("firebase-admin/app");
  const { getFirestore, FieldValue } = fnRequire("firebase-admin/firestore");
  const { getAuth } = fnRequire("firebase-admin/auth");
  const { getStorage } = fnRequire("firebase-admin/storage");
  const bucketName = target.emulator ? `${target.projectId}.appspot.com` : `${target.projectId}.firebasestorage.app`;
  const app = initializeApp({ projectId: target.projectId, storageBucket: bucketName }, "seed-dev");
  if (app.options.projectId !== target.projectId) throw new Error("project mismatch after init");
  const db = getFirestore(app);
  const now = FieldValue.serverTimestamp();
  const printed = [];
  let credentialsWritten = false;
  function writeCredentials() {
    if (credentialsWritten) return;
    credentialsWritten = true;
    if (printed.length && credentialsOut) {
      // CI: never print passwords to the job log; write them to a private file
      // that the workflow uploads as a short-lived artifact.
      fs.writeFileSync(credentialsOut, printed.join("\n") + "\n", { mode: 0o600 });
      console.log(`\nCredentials written to ${path.basename(credentialsOut)} (not printed here).`);
    } else if (printed.length) {
      console.log("\nNEW credentials (shown once; save them in your password manager, never in the repo or a ticket):");
      for (const line of printed) console.log(`  ${line}`);
    } else {
      console.log("\nCredentials unchanged (users and companies already existed).");
    }
  }

  const batch = db.batch();
  const put = (col, id, doc) => batch.set(db.collection(col).doc(id), { ...doc, ...FIXTURE, seededAt: now }, { merge: true });

  for (const c of data.companies) {
    const existing = (await db.collection("companies").doc(c.slug).get()).data() || {};
    const creds = {
      brandManagerUsername: existing.brandManagerUsername || `brand_${c.slug}`,
      brandManagerPassword: existing.brandManagerPassword || randomPassword("Bm#dev"),
      agencyOpsUsername: existing.agencyOpsUsername || `ops_${c.slug}`,
      agencyOpsPassword: existing.agencyOpsPassword || randomPassword("Op#dev"),
    };
    if (!existing.brandManagerPassword || credentialsOut) printed.push(`company ${c.slug}: /portal/${c.slug}  ${creds.brandManagerUsername} / ${creds.brandManagerPassword}`);
    if (!existing.agencyOpsPassword || credentialsOut) printed.push(`company ${c.slug}: /ops/${c.slug}     ${creds.agencyOpsUsername} / ${creds.agencyOpsPassword}`);
    put("companies", c.slug, {
      name: c.name, slug: c.slug, logoUrl: "", productsCount: data.products.filter((p) => p.companySlug === c.slug).length,
      brandCredentialVersion: existing.brandCredentialVersion || 1, agencyCredentialVersion: existing.agencyCredentialVersion || 1,
      createdAt: existing.createdAt || new Date(), ...creds,
    });
  }
  for (const ch of data.chains) {
    put("retail_chains", ch.id, { name: ch.name, slug: ch.slug, branchesCount: data.branches.filter((b) => b.retailChainId === ch.id).length, createdAt: new Date() });
  }
  for (const b of data.branches) {
    const { id, ...rest } = b;
    put("branches", id, { ...rest, address: "عنوان تجريبي", createdAt: new Date() });
  }
  for (const p of data.products) {
    const { id, ...rest } = p;
    put("company_products", id, { ...rest, createdAt: new Date() });
  }
  for (const g of data.gifts) {
    const { id, ...rest } = g;
    put("company_gifts", id, {
      ...rest, availableQuantity: g.totalQuantity, allocatedInOtherCampaigns: 0, orderIndex: 0, lowStockThreshold: 5,
      batches: [{ id: `${id}-b1`, batchNumber: "DEV-1", quantity: g.totalQuantity, supplyDate: new Date(), referenceNumber: "DEV", notes: "بيانات تجربة", addedBy: "seed_dev" }],
      createdAt: new Date(),
    });
  }
  for (const e of data.events) {
    const { id, ...rest } = e;
    put("events", id, { ...rest, createdAt: new Date() });
  }
  for (const d of data.drafts) {
    const { id, ...rest } = d;
    put("event_drafts", id, { ...rest, updatedAt: new Date() });
  }
  await batch.commit();
  console.log("Firestore: written.");

  if (!skipAuth) {
    const auth = getAuth(app);
    for (const u of data.users) {
      let user;
      try {
        user = await auth.getUserByEmail(u.email);
        if (resetPasswords) {
          const password = randomPassword("Dev#");
          await auth.updateUser(user.uid, { password });
          printed.push(`${u.key}: ${u.email} / ${password} (reset)`);
        }
      } catch (err) {
        if (err.code !== "auth/user-not-found") throw err;
        const password = process.env.DEV_ADMIN_PASSWORD || randomPassword("Dev#");
        user = await auth.createUser({ email: u.email, password, displayName: u.displayName, emailVerified: true });
        printed.push(`${u.key}: ${u.email} / ${process.env.DEV_ADMIN_PASSWORD ? "(DEV_ADMIN_PASSWORD)" : password}`);
      }
      await auth.setCustomUserClaims(user.uid, { ...(user.customClaims || {}), ...u.claims });
      if (u.adminDoc) {
        await db.collection("admins").doc(u.email).set({ uid: user.uid, email: u.email, role: u.claims.role, ...FIXTURE, seededAt: now }, { merge: true });
      }
    }
    console.log("Auth: test users ready.");
  }
  writeCredentials();

  if (!skipStorage && receipts.length) {
    const bucket = getStorage(app).bucket(bucketName);
    const [bucketExists] = await bucket.exists();
    if (!bucketExists) {
      console.log(`::warning::Storage bucket gs://${bucketName} does not exist. Open https://console.firebase.google.com/project/${target.projectId}/storage and click "Get started", then seed again. Sample receipts were NOT uploaded.`);
    }
    for (const f of bucketExists ? receipts : []) {
      await bucket.upload(path.join(RECEIPTS_DIR, f), { destination: `dev_fixtures/receipts/${f}`, metadata: { contentType: "image/png", metadata: { devFixture: "true" } } });
    }
    if (bucketExists) console.log(`Storage: ${receipts.length} sample receipts uploaded to gs://${bucketName}/dev_fixtures/receipts/`);
  }

  const site = target.emulator ? "http://127.0.0.1:<port>" : `https://${target.projectId}.web.app`;
  console.log("\nPromoter (مندوب) links - anonymous, no password:");
  for (const e of data.events.filter((x) => x.isActive)) console.log(`  ${e.eventName}: ${site}/c/${e.companySlug}?event=${e.id}`);
  writeCredentials();
}

main().catch((err) => {
  console.error(err && err.stack ? err.stack : err);
  process.exit(1);
});
