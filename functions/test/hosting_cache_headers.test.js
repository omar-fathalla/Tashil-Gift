const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { minimatch } = require("minimatch");
const RE2 = require("re2");
const { SHARE_PREVIEW_REWRITES } = require("../share_preview");

const NO_CACHE = "no-cache, no-store, must-revalidate, max-age=0";
const REVALIDATE = "public, max-age=0, must-revalidate";

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

const previewRes = rewrites
  .filter((rule) => rule.function && rule.function.functionId === "sharePreview")
  .map((rule) => compile(rule.regex));

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
 * key the later rule overwrites the earlier one. A matching rule that does
 * not list Cache-Control leaves a previously set value in place, so omitting
 * the key cannot restore a function header.
 */
function effectiveHeaders(rawPath) {
  const pathname = slashPath(rawPath);
  const merged = new Map();
  const hits = [];
  for (const rule of headers) {
    if (!ruleMatches(pathname, rule)) continue;
    const pattern = rule.regex || rule.source;
    hits.push(pattern);
    for (const header of rule.headers || []) {
      merged.set(String(header.key).toLowerCase(), header.value);
    }
  }
  return { pathname, headers: merged, hits };
}

function cacheControl(rawPath) {
  return effectiveHeaders(rawPath).headers.get("cache-control");
}

function isPreview(pathname) {
  return previewRes.some((re) => re.test(pathname));
}

/**
 * Independent spec: the old extensionless glob, minus exact preview shapes,
 * plus scanner .php/.cgi paths. Later asset rules still win.
 */
function expectedCacheControl(rawPath) {
  const pathname = slashPath(rawPath);
  let value;
  if (SHELL_FILES.includes(pathname)) value = NO_CACHE;
  if (pathname === "/") value = NO_CACHE;
  const preview = isPreview(pathname);
  if (!preview && minimatch(pathname, "/**/!(*.*)")) value = NO_CACHE;
  if (!preview && /\.(?:php|cgi)\/?$/i.test(pathname)) value = NO_CACHE;
  if (pathname === "/main.dart.js") value = REVALIDATE;
  if (minimatch(pathname, "/canvaskit/**")) value = REVALIDATE;
  if (minimatch(pathname, "/assets/**")) value = REVALIDATE;
  if (minimatch(pathname, "/icons/**")) value = REVALIDATE;
  if (minimatch(pathname, "/fonts/**")) value = REVALIDATE;
  return value;
}

const previewSamples = [
  "/c/469",
  "/c/469/",
  "/c/0",
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
  "/event/y5ujNVYJxsYIEgK1xmQL",
  "/event/7up",
  "/share/almarai",
  "/share/almarai/",
];

const noCacheSamples = [
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
];

test("sharePreview rewrites are unchanged and header regexes are RE2", () => {
  const functionRules = rewrites.filter((rule) => rule.function && rule.function !== "wahaProxy");
  assert.deepEqual(
    functionRules.map((rule) => rule.regex),
    SHARE_PREVIEW_REWRITES.map((rule) => rule.regex),
  );
  assert.equal(rewrites[0].source, "/waha/**");
  assert.equal(rewrites.at(-1).source, "**");
  assert.equal(rewrites.at(-1).destination, "/index.html");
  assert.equal(headers.some((rule) => rule.source === "**/!(*.*)"), false);
  for (const rule of headers) {
    assert.equal(rule.source && rule.regex, undefined);
    if (rule.regex) compile(rule.regex);
  }
});

test("a later header that omits Cache-Control does not clear an earlier one", () => {
  const rules = [
    { source: "**", headers: [{ key: "Cache-Control", value: NO_CACHE }] },
    { regex: "^/c/\\d+/?$", headers: [{ key: "X-Test", value: "1" }] },
  ];
  const pathname = "/c/469";
  let cache;
  let sawTest = false;
  for (const rule of rules) {
    const matched = rule.regex
      ? compile(rule.regex).test(pathname)
      : minimatch(pathname, slashPath(rule.source));
    assert.equal(matched, true);
    for (const header of rule.headers) {
      if (header.key.toLowerCase() === "cache-control") cache = header.value;
      if (header.key === "X-Test") sawTest = true;
    }
  }
  assert.equal(cache, NO_CACHE);
  assert.equal(sawTest, true);
});

for (const sample of previewSamples) {
  test(`${sample} matches a sharePreview rewrite and no header sets Cache-Control`, () => {
    const { pathname, headers: merged, hits } = effectiveHeaders(sample);
    assert.equal(isPreview(pathname), true, pathname);
    const cacheRules = headers.filter((rule) => {
      if (!ruleMatches(pathname, rule)) return false;
      return (rule.headers || []).some((header) => header.key.toLowerCase() === "cache-control");
    });
    assert.deepEqual(cacheRules, [], `${pathname} hit ${hits.join(", ")}`);
    assert.equal(merged.get("cache-control"), undefined);
    assert.match(merged.get("content-security-policy") || "", /default-src/);
    assert.equal(cacheControl(sample), expectedCacheControl(sample));
  });
}

for (const sample of noCacheSamples) {
  test(`${sample} keeps Cache-Control no-cache`, () => {
    const { pathname } = effectiveHeaders(sample);
    assert.equal(isPreview(pathname), false, pathname);
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
  test(`${sample} keeps the ${source} cache header (later rule wins)`, () => {
    assert.equal(cacheControl(sample), REVALIDATE);
    assert.equal(cacheControl(sample), expectedCacheControl(sample));
    const { hits } = effectiveHeaders(sample);
    assert.ok(hits.includes(source), hits.join(", "));
  });
}

test("extensionless asset paths do not keep the broad no-cache header", () => {
  const broad = effectiveHeaders("/assets/extensionless");
  assert.ok(broad.hits.some((hit) => hit.startsWith("^/")));
  assert.equal(broad.headers.get("cache-control"), REVALIDATE);
  assert.notEqual(broad.headers.get("cache-control"), NO_CACHE);
});

test("fuzz: effective Cache-Control matches the preview-exclusion spec", () => {
  const rand = mulberry32(0xC0FFEE);
  const alphabet = "abcXYZ019-_~. %.";
  const prefixes = ["c", "portal", "client", "promoter", "ops", "agency", "p", "ep", "event", "share"];
  const failures = [];
  for (let i = 0; i < 2000; i += 1) {
    const depth = 1 + Math.floor(rand() * 4);
    const segs = [];
    for (let d = 0; d < depth; d += 1) {
      let seg = "";
      const len = 1 + Math.floor(rand() * 10);
      for (let k = 0; k < len; k += 1) {
        seg += alphabet[Math.floor(rand() * alphabet.length)];
      }
      if (rand() < 0.05) seg = `.${seg}`;
      segs.push(seg);
    }
    if (rand() < 0.2) segs[0] = prefixes[Math.floor(rand() * prefixes.length)];
    if (rand() < 0.08 && segs.length >= 2) {
      const ids = ["469", "almarai", "coca-cola", "7up", "a-b-c", "_x", "-a", "a-", "a--b", "ok"];
      segs[1] = ids[Math.floor(rand() * ids.length)];
    }
    let sample = `/${segs.join("/")}`;
    if (rand() < 0.25) sample += "/";
    const actual = cacheControl(sample);
    const expected = expectedCacheControl(sample);
    if (actual !== expected) {
      failures.push(`${JSON.stringify(sample)} actual=${actual} expected=${expected}`);
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
