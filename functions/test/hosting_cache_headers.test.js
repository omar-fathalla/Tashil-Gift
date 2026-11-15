const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { minimatch } = require("minimatch");
const RE2 = require("re2");
const { SHARE_PREVIEW_REWRITES } = require("../share_preview");

const NO_CACHE = "no-cache, no-store, must-revalidate, max-age=0";
const REVALIDATE = "public, max-age=0, must-revalidate";
const LONG_CACHE = "public, max-age=300, s-maxage=3600";

const firebaseJson = JSON.parse(
  fs.readFileSync(path.join(__dirname, "../../firebase.json"), "utf8"),
);
const headers = firebaseJson.hosting.headers;
const rewrites = firebaseJson.hosting.rewrites;

const SHELL_FILES = [
  "/index.html",
  "/flutter.js",
  "/flutter_bootstrap.js",
  "/flutter_service_worker.js",
  "/version.json",
  "/manifest.json",
];

const ORIGINAL_SOURCES = [
  "**",
  "@(index.html|flutter.js|flutter_bootstrap.js|flutter_service_worker.js|version.json|manifest.json)",
  "/",
  "**/!(*.*)",
  "main.dart.js",
  "canvaskit/**",
  "assets/**",
  "icons/**",
  "fonts/**",
];

/**
 * Same normalization superstatic applies before header and rewrite matching:
 * leading slash, backslashes flipped, duplicate slashes collapsed.
 * A single trailing slash is preserved.
 */
function slashPath(value) {
  let val = String(value);
  if (!val.startsWith("/")) val = `/${val}`;
  return val.replace(/\\/g, "/").replace(/\/+/g, "/");
}

function compile(pattern) {
  return new RE2(pattern, "u");
}

const previewRewriteRes = rewrites
  .filter((rule) => rule.function && rule.function.functionId === "sharePreview")
  .map((rule) => compile(rule.regex));

const previewHeaderRule = headers.at(-1);
const previewHeaderRe = compile(previewHeaderRule.regex);

function ruleMatches(pathname, rule) {
  if (rule.source && rule.regex) {
    throw new Error("header rule sets both source and regex");
  }
  if (typeof rule.source === "string") {
    return minimatch(pathname, slashPath(rule.source));
  }
  if (typeof rule.regex === "string") {
    return compile(rule.regex).test(pathname);
  }
  return false;
}

/**
 * Hosting applies every matching header rule in file order. For a repeated
 * key the later rule overwrites the earlier one.
 */
function effectiveHeaders(rawPath) {
  const pathname = slashPath(rawPath);
  const merged = new Map();
  const hits = [];
  for (const rule of headers) {
    if (!ruleMatches(pathname, rule)) continue;
    hits.push(rule.regex || rule.source);
    for (const header of rule.headers || []) {
      merged.set(String(header.key).toLowerCase(), header.value);
    }
  }
  return { pathname, headers: merged, hits };
}

function cacheControl(rawPath) {
  return effectiveHeaders(rawPath).headers.get("cache-control");
}

function matchesAnyRewrite(pathname) {
  return previewRewriteRes.some((re) => re.test(pathname));
}

/**
 * Spec for the effective Hosting Cache-Control. The final preview rule wins
 * over the earlier extensionless no-cache glob. Asset rules sit between them
 * and still win on their own paths, which are not preview shapes.
 */
function expectedCacheControl(rawPath) {
  const pathname = slashPath(rawPath);
  let value;
  if (SHELL_FILES.includes(pathname)) value = NO_CACHE;
  if (pathname === "/") value = NO_CACHE;
  if (minimatch(pathname, "/**/!(*.*)")) value = NO_CACHE;
  if (pathname === "/main.dart.js") value = REVALIDATE;
  if (minimatch(pathname, "/canvaskit/**")) value = REVALIDATE;
  if (minimatch(pathname, "/assets/**")) value = REVALIDATE;
  if (minimatch(pathname, "/icons/**")) value = REVALIDATE;
  if (minimatch(pathname, "/fonts/**")) value = REVALIDATE;
  if (matchesAnyRewrite(pathname)) value = LONG_CACHE;
  return value;
}

const previewSamples = [
  "/c/469",
  "/c/469/",
  "/c/0",
  "/c/007",
  "/c/almarai",
  "/c/coca-cola",
  "/c/7up",
  "/c/Coca-Cola",
  "/portal/unilever",
  "/portal/unilever/",
  "/client/adco",
  "/client/adco/",
  "/promoter/512",
  "/ops/unilever",
  "/agency/adco",
  "/p/juhayna",
  "/p/a-b-c",
  "/ep/y5ujNVYJxsYIEgK1xmQL",
  "/ep/y5ujNVYJxsYIEgK1xmQL/",
  "/event/y5ujNVYJxsYIEgK1xmQL",
  "/event/7up",
  "/share/almarai",
  "/share/almarai/",
];

const notPreviewSamples = [
  "/",
  "/c",
  "/c/",
  "/portal",
  "/portal/",
  "/client",
  "/client/",
  "/promoter",
  "/promoter/",
  "/ops",
  "/ops/",
  "/agency",
  "/agency/",
  "/p",
  "/p/",
  "/ep",
  "/ep/",
  "/event",
  "/event/",
  "/share",
  "/share/",
  "/index",
  "/~user",
  "/c/469/subadmin",
  "/c/469/subadmin/",
  "/c/469//",
  "/portal/unilever/extra",
  "/ops/unilever/subadmin",
  "/event/abc/extra",
  "/c/469/~user",
  "/c/_bad",
  "/c/-bad",
  "/c/bad-",
  "/c/a--b",
  "/c/foo_bar",
  "/c/not_a_slug",
  "/share/-x",
  "/other/page",
  "/foo/bar/",
  "/foo.bar/baz",
  "/c/469/sugarcrm/index.php",
  "/index.cgi",
  "/index.PHP",
  "/c/469/foo.cgi",
  "/c/foo.cgi",
  "/~user/.cgi",
  "/foo.CGI",
  "/c/469%2Fsubadmin",
];

test("original header rules stay, with one preview rule appended", () => {
  assert.deepEqual(
    headers.slice(0, -1).map((rule) => rule.source),
    ORIGINAL_SOURCES,
  );
  assert.equal(headers.slice(0, -1).some((rule) => rule.regex), false);
  assert.equal(headers.at(-1), previewHeaderRule);
  assert.equal(previewHeaderRule.source, undefined);
  assert.equal(
    previewHeaderRule.regex,
    "^/(?:c|portal|client|promoter|ops|agency|p|ep|event|share)/[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*/?$",
  );
  assert.deepEqual(previewHeaderRule.headers, [
    { key: "Cache-Control", value: LONG_CACHE },
  ]);
  const extensionless = headers.find((rule) => rule.source === "**/!(*.*)");
  assert.deepEqual(extensionless.headers, [
    { key: "Cache-Control", value: NO_CACHE },
  ]);
});

test("sharePreview rewrites are unchanged", () => {
  const functionRules = rewrites.filter((rule) => rule.function && rule.function !== "wahaProxy");
  assert.deepEqual(
    functionRules.map((rule) => rule.regex),
    SHARE_PREVIEW_REWRITES.map((rule) => rule.regex),
  );
  assert.equal(rewrites[0].source, "/waha/**");
  assert.equal(rewrites.at(-1).source, "**");
  assert.equal(rewrites.at(-1).destination, "/index.html");
});

test("preview header regex matches the same paths as the sharePreview rewrites", () => {
  const samples = [...previewSamples, ...notPreviewSamples];
  for (const sample of samples) {
    assert.equal(
      previewHeaderRe.test(sample),
      matchesAnyRewrite(sample),
      sample,
    );
  }
  for (const sample of previewSamples) {
    assert.equal(previewHeaderRe.test(sample), true, sample);
    assert.equal(matchesAnyRewrite(sample), true, sample);
  }
  for (const sample of notPreviewSamples) {
    assert.equal(previewHeaderRe.test(sample), false, sample);
    assert.equal(matchesAnyRewrite(sample), false, sample);
  }
});

test("the extensionless no-cache rule matches preview paths, and the last rule overwrites it", () => {
  for (const sample of previewSamples) {
    const { hits, headers: merged } = effectiveHeaders(sample);
    assert.ok(hits.includes("**/!(*.*)"), `${sample} hits ${hits.join(", ")}`);
    assert.equal(hits.at(-1), previewHeaderRule.regex);
    assert.equal(merged.get("cache-control"), LONG_CACHE);
    assert.match(merged.get("content-security-policy") || "", /default-src/);
    assert.equal(cacheControl(sample), expectedCacheControl(sample));
  }
});

const extensionlessNoCache = [
  "/",
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
  "/index",
  "/~user",
  "/c/469/subadmin",
  "/portal/unilever/extra",
  "/c/not_a_slug",
  "/c/_bad",
  "/c/a--b",
  "/other/page",
];

for (const sample of extensionlessNoCache) {
  test(`${sample} keeps the extensionless no-cache header`, () => {
    assert.equal(previewHeaderRe.test(slashPath(sample)), false);
    assert.equal(cacheControl(sample), NO_CACHE);
    assert.equal(cacheControl(sample), expectedCacheControl(sample));
  });
}

for (const sample of SHELL_FILES) {
  test(`${sample} keeps the shell no-cache headers`, () => {
    const { headers: merged } = effectiveHeaders(sample);
    assert.equal(merged.get("cache-control"), NO_CACHE);
    assert.equal(merged.get("pragma"), "no-cache");
    assert.equal(merged.get("expires"), "0");
    assert.equal(cacheControl(sample), expectedCacheControl(sample));
  });
}

const unchangedExtensionSamples = [
  "/index.cgi",
  "/c/foo.cgi",
  "/c/469/foo.cgi",
  "/c/469/sugarcrm/index.php",
  "/~user/.cgi",
  "/index.PHP",
];

for (const sample of unchangedExtensionSamples) {
  test(`${sample} does not get a Hosting Cache-Control rule`, () => {
    assert.equal(cacheControl(sample), undefined);
    assert.equal(cacheControl(sample), expectedCacheControl(sample));
  });
}

const assetSamples = [
  ["/main.dart.js", "main.dart.js"],
  ["/canvaskit/canvaskit.js", "canvaskit/**"],
  ["/canvaskit/chromium/canvaskit.wasm", "canvaskit/**"],
  ["/canvaskit/pkg", "canvaskit/**"],
  ["/assets/AssetManifest.bin", "assets/**"],
  ["/assets/extensionless", "assets/**"],
  ["/assets/file.php", "assets/**"],
  ["/icons/Icon-192.png", "icons/**"],
  ["/fonts/MaterialIcons-Regular.otf", "fonts/**"],
];

for (const [sample, source] of assetSamples) {
  test(`${sample} keeps the ${source} cache header`, () => {
    assert.equal(cacheControl(sample), REVALIDATE);
    assert.equal(cacheControl(sample), expectedCacheControl(sample));
    const { hits } = effectiveHeaders(sample);
    assert.ok(hits.includes(source), hits.join(", "));
    assert.equal(hits.includes(previewHeaderRule.regex), false);
  });
}

test("fuzz: header regex and rewrite regexes accept the same paths", () => {
  const rand = mulberry32(0xC0FFEE);
  const alphabet = "abcXYZ019-_~. %.";
  const prefixes = ["c", "portal", "client", "promoter", "ops", "agency", "p", "ep", "event", "share"];
  const failures = [];
  for (let i = 0; i < 2000; i += 1) {
    const depth = 1 + Math.floor(rand() * 4);
    const segs = [];
    for (let d = 0; d < depth; d += 1) {
      let seg = "";
      const len = 1 + Math.floor(rand() * 12);
      for (let k = 0; k < len; k += 1) {
        seg += alphabet[Math.floor(rand() * alphabet.length)];
      }
      if (rand() < 0.05) seg = `.${seg}`;
      segs.push(seg);
    }
    if (rand() < 0.25) segs[0] = prefixes[Math.floor(rand() * prefixes.length)];
    if (rand() < 0.1 && segs.length >= 2) {
      const ids = ["469", "007", "almarai", "coca-cola", "7up", "a-b-c", "_x", "-a", "a-", "a--b", "ok", "foo.cgi"];
      segs[1] = ids[Math.floor(rand() * ids.length)];
    }
    let sample = `/${segs.join("/")}`;
    if (rand() < 0.25) sample += "/";
    const headerHit = previewHeaderRe.test(sample);
    const rewriteHit = matchesAnyRewrite(sample);
    if (headerHit !== rewriteHit) {
      failures.push(`${JSON.stringify(sample)} header=${headerHit} rewrite=${rewriteHit}`);
    }
    const normalized = slashPath(sample);
    if (cacheControl(normalized) !== expectedCacheControl(normalized)) {
      failures.push(
        `${JSON.stringify(normalized)} cache ${cacheControl(normalized)} != ${expectedCacheControl(normalized)}`,
      );
    }
  }
  assert.deepEqual(failures, []);
});

function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
