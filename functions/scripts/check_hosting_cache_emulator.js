#!/usr/bin/env node
"use strict";

/**
 * Asserts Cache-Control on the local Hosting emulator.
 *
 * Run only against a demo project (see run_hosting_cache_emulator.sh).
 * This script never deploys and never selects the tashil-gift project.
 *
 * Hosting emulator hub: http://127.0.0.1:4400/emulators
 */

const LONG_CACHE = "public, max-age=300, s-maxage=3600";
const NO_CACHE = "no-cache, no-store, must-revalidate, max-age=0";
const REVALIDATE = "public, max-age=0, must-revalidate";

const PROJECT = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
if (PROJECT === "tashil-gift" || PROJECT.includes("tashil-gift")) {
  console.error("Refusing to run against the production project.");
  process.exit(1);
}

const previewGets = [
  "/c/469",
  "/c/469/",
  "/c/almarai",
  "/c/coca-cola",
  "/c/7up",
  "/portal/unilever",
  "/client/adco",
  "/promoter/512",
  "/ops/unilever",
  "/agency/adco",
  "/p/juhayna",
  "/ep/y5ujNVYJxsYIEgK1xmQL",
  "/event/y5ujNVYJxsYIEgK1xmQL",
  "/share/almarai",
];

const cases = [
  ...previewGets.map((urlPath) => ({
    method: "GET",
    urlPath,
    status: 200,
    cache: LONG_CACHE,
    body: /og:title/,
  })),
  {
    method: "HEAD",
    urlPath: "/c/469",
    status: 200,
    cache: LONG_CACHE,
  },
  {
    method: "GET",
    urlPath: "/c/999999",
    status: 200,
    cache: LONG_CACHE,
    body: /og:title/,
  },
  {
    method: "POST",
    urlPath: "/c/469",
    status: 404,
    cache: LONG_CACHE,
    body: /^Not Found$/,
  },
  ...[
    "/c",
    "/c/",
    "/portal",
    "/portal/",
    "/client/",
    "/promoter",
    "/ops/",
    "/agency",
    "/p/",
    "/ep",
    "/event/",
    "/share",
    "/share/",
    "/c/469/subadmin",
    "/~user",
    "/c/not_a_slug",
    "/portal/unilever/extra",
    "/",
    "/index.html",
  ].map((urlPath) => ({
    method: "GET",
    urlPath,
    status: 200,
    cache: NO_CACHE,
    body: /FIXTURE_SHELL/,
  })),
  ...["/c/469/sugarcrm/index.php", "/index.cgi", "/c/469/foo.cgi", "/c/foo.cgi"].map((urlPath) => ({
    method: "GET",
    urlPath,
    status: 200,
    cache: null,
    body: /FIXTURE_SHELL/,
  })),
  {
    method: "GET",
    urlPath: "/~user/.cgi",
    status: 404,
    cache: null,
  },
  ...[
    "/flutter.js",
    "/flutter_bootstrap.js",
    "/flutter_service_worker.js",
    "/version.json",
    "/manifest.json",
  ].map((urlPath) => ({
    method: "GET",
    urlPath,
    status: 200,
    cache: NO_CACHE,
  })),
  ...[
    "/main.dart.js",
    "/canvaskit/canvaskit.js",
    "/assets/keep.png",
    "/assets/extensionless",
    "/icons/keep.png",
    "/fonts/keep.ttf",
  ].map((urlPath) => ({
    method: "GET",
    urlPath,
    status: 200,
    cache: REVALIDATE,
  })),
];

async function hostingOrigin() {
  if (process.env.HOSTING_ORIGIN) return process.env.HOSTING_ORIGIN.replace(/\/$/, "");
  const res = await fetch("http://127.0.0.1:4400/emulators");
  if (!res.ok) throw new Error(`emulator hub HTTP ${res.status}`);
  const body = await res.json();
  const hosting = body.hosting;
  if (!hosting || !hosting.port) throw new Error(`hosting emulator missing in hub: ${JSON.stringify(body)}`);
  const host = hosting.host || "127.0.0.1";
  return `http://${host}:${hosting.port}`;
}

async function request(origin, entry) {
  const response = await fetch(`${origin}${entry.urlPath}`, {
    method: entry.method,
    redirect: "manual",
    headers: {
      "user-agent": "facebookexternalhit/1.1",
      "content-type": "text/plain",
    },
    body: entry.method === "POST" ? "" : undefined,
  });
  const text = entry.method === "HEAD" ? "" : await response.text();
  return {
    status: response.status,
    cache: response.headers.get("cache-control"),
    csp: response.headers.get("content-security-policy"),
    location: response.headers.get("location"),
    body: text.slice(0, 180).replace(/\s+/g, " "),
    text,
  };
}

async function main() {
  const origin = await hostingOrigin();
  console.log(`Hosting origin: ${origin}`);
  console.log(`Project env: ${PROJECT || "(unset)"}`);
  const rows = [];
  let failed = 0;
  for (const entry of cases) {
    let observed;
    try {
      observed = await request(origin, entry);
    } catch (error) {
      observed = { status: "ERR", cache: "", csp: "", location: "", body: String(error), text: "" };
    }
    const problems = [];
    if (observed.status !== entry.status) problems.push(`status ${observed.status} != ${entry.status}`);
    if (observed.cache !== entry.cache) problems.push(`cache ${JSON.stringify(observed.cache)} != ${JSON.stringify(entry.cache)}`);
    if (entry.body && !entry.body.test(observed.text || "")) problems.push("body mismatch");
    if (entry.urlPath.startsWith("/c/") && entry.method === "GET" && entry.cache === LONG_CACHE) {
      if (!observed.csp || !observed.csp.includes("default-src")) problems.push("missing CSP");
    }
    if (problems.length) failed += 1;
    rows.push({
      method: entry.method,
      path: entry.urlPath,
      status: observed.status,
      cache: observed.cache,
      location: observed.location || "",
      ok: problems.length === 0,
      problems: problems.join("; "),
      body: observed.body,
    });
  }

  console.log("\n| method | path | status | cache-control | ok |");
  console.log("| --- | --- | --- | --- | --- |");
  for (const row of rows) {
    console.log(`| ${row.method} | \`${row.path}\` | ${row.status} | \`${row.cache}\` | ${row.ok ? "yes" : "NO"} |`);
    if (!row.ok) {
      console.log(`  FAIL ${row.problems}`);
      if (row.location) console.log(`  location: ${row.location}`);
      console.log(`  body: ${row.body}`);
    }
  }
  console.log(`\n${rows.length - failed}/${rows.length} passed`);
  if (failed) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
