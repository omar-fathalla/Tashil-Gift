/**
 * Per-environment values for Cloud Functions (TAG-9).
 *
 * The same source deploys to production (`tashil-gift`) and development
 * (`tashil-gift-dev`). Anything that differs is derived from the project id
 * the function runs in, or read from `functions/.env.<projectId>` (loaded by
 * firebase-tools at deploy time; see functions/.env.tashil-gift-dev).
 * Secrets never live here: they come from Secret Manager via defineSecret.
 *
 * Production behaviour is unchanged: there is no env file for tashil-gift,
 * and every value below equals what the code hard-coded before.
 */
const PROD_PROJECT_ID = "tashil-gift";
const DEV_PROJECT_ID = "tashil-gift-dev";

function readFirebaseConfigProject(env) {
  try {
    const cfg = JSON.parse(env.FIREBASE_CONFIG || "{}");
    return typeof cfg.projectId === "string" ? cfg.projectId : "";
  } catch (_) {
    return "";
  }
}

/** Project id the function runs in. Unknown (unit tests) -> production. */
function projectId(env = process.env) {
  return (
    env.GCLOUD_PROJECT ||
    env.GOOGLE_CLOUD_PROJECT ||
    readFirebaseConfigProject(env) ||
    PROD_PROJECT_ID
  );
}

/** "dev" for tashil-gift-dev (or TASHIL_ENV=dev), "prod" otherwise. */
function envLabel(env = process.env) {
  const explicit = String(env.TASHIL_ENV || "").trim().toLowerCase();
  if (explicit === "dev" || explicit === "prod") return explicit;
  return projectId(env) === DEV_PROJECT_ID ? "dev" : "prod";
}

function isDev(env = process.env) {
  return envLabel(env) === "dev";
}

/** Public Hosting origin, e.g. https://tashil-gift.web.app (prod). */
function publicSiteOrigin(env = process.env) {
  const fromEnv = String(env.PUBLIC_SITE_ORIGIN || "").trim().replace(/\/+$/, "");
  if (/^https:\/\/[a-z0-9.-]+$/i.test(fromEnv)) return fromEnv;
  return `https://${projectId(env)}.web.app`;
}

const PROD_ALLOWED_ORIGINS = Object.freeze([
  "https://tashil-gift.web.app",
  "https://tashil-gift.firebaseapp.com",
  "https://gift.sw-point.com",
  "https://www.gift.sw-point.com",
]);

/**
 * Browser origins allowed to call the WAHA proxy directly (CORS).
 * prod: exactly the list it always had. dev: the dev site and its preview
 * channels (https://tashil-gift-dev--<channel>.web.app); never the prod hosts.
 */
function wahaProxyAllowedOrigins(env = process.env) {
  if (!isDev(env)) return new Set(PROD_ALLOWED_ORIGINS);
  const id = projectId(env);
  return new Set([`https://${id}.web.app`, `https://${id}.firebaseapp.com`]);
}

function isWahaProxyOriginAllowed(origin, env = process.env) {
  if (!origin || typeof origin !== "string") return false;
  if (wahaProxyAllowedOrigins(env).has(origin)) return true;
  if (!isDev(env)) return false;
  const id = projectId(env).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^https://${id}--[a-z0-9-]+\\.web\\.app$`).test(origin);
}

module.exports = {
  PROD_PROJECT_ID,
  DEV_PROJECT_ID,
  projectId,
  envLabel,
  isDev,
  publicSiteOrigin,
  wahaProxyAllowedOrigins,
  isWahaProxyOriginAllowed,
};
