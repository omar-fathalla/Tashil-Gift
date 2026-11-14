const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  matchSharePreviewRoute,
  handleSharePreview,
  clearSharePreviewCache,
  SHARE_PREVIEW_MAX_INSTANCES,
  SHARE_PREVIEW_REWRITES,
} = require("../share_preview");

const LONG_CACHE = "public, max-age=300, s-maxage=3600";
const SHORT_CACHE = "public, max-age=60, s-maxage=300";
const EVENT_ID = "y5ujNVYJxsYIEgK1xmQL";

const firebaseJson = JSON.parse(
  fs.readFileSync(path.join(__dirname, "../../firebase.json"), "utf8"),
);
const hostingRewrites = firebaseJson.hosting.rewrites;

function createDb(seed = {}) {
  const docs = new Map(Object.entries(seed));
  let reads = 0;
  const db = {
    get reads() {
      return reads;
    },
    collection(name) {
      return {
        doc(id) {
          return {
            async get() {
              reads += 1;
              const data = docs.get(`${name}/${id}`);
              return {
                exists: data !== undefined,
                data: () => (data === undefined ? undefined : { ...data }),
              };
            },
          };
        },
        where(field, _op, value) {
          const query = {
            limit() {
              return query;
            },
            async get() {
              reads += 1;
              const found = [];
              for (const [docPath, data] of docs) {
                if (docPath.startsWith(`${name}/`) && data[field] === value) {
                  found.push({ data: () => ({ ...data }) });
                }
              }
              return { empty: found.length === 0, docs: found };
            },
          };
          return query;
        },
      };
    },
  };
  return db;
}

function mockRes() {
  const res = {
    statusCode: 200,
    body: undefined,
    redirected: undefined,
    headers: {},
    set(name, value) {
      res.headers[String(name).toLowerCase()] = value;
      return res;
    },
    status(code) {
      res.statusCode = code;
      return res;
    },
    send(body) {
      res.body = body;
      return res;
    },
    redirect(url) {
      res.redirected = url;
      res.statusCode = 302;
      return res;
    },
  };
  return res;
}

async function invoke({ method = "GET", path: reqPath, query = {}, headers = {}, seed = {} }) {
  clearSharePreviewCache();
  const db = createDb(seed);
  const res = mockRes();
  await handleSharePreview({ method, path: reqPath, query, headers }, res, db);
  return { res, db };
}

function globSourceMatches(source, pathname) {
  if (source === "**") return true;
  if (source.endsWith("/**")) {
    const base = source.slice(0, -3);
    return pathname.startsWith(`${base}/`);
  }
  return false;
}

/** First matching hosting rewrite, same order as firebase.json. */
function resolveHostingRewrite(pathname) {
  for (const rule of hostingRewrites) {
    if (typeof rule.regex === "string" && new RegExp(rule.regex).test(pathname)) return rule;
    if (typeof rule.source === "string" && globSourceMatches(rule.source, pathname)) return rule;
  }
  return null;
}

function isSharePreviewRule(rule) {
  return Boolean(
    rule
    && rule.function
    && rule.function.functionId === "sharePreview"
    && rule.function.region === "us-central1",
  );
}

const previewSamples = [
  { path: "/c/469", manager: false, eventName: "Campaign 469", company: "Acme" },
  { path: "/c/469/", manager: false, eventName: "Campaign 469", company: "Acme" },
  { path: "/c/almarai", manager: false, eventName: "Almarai Offer", company: "Almarai" },
  { path: "/c/coca-cola", manager: false, eventName: "Coke Offer", company: "Coca-Cola" },
  { path: "/c/7up", manager: false, eventName: "7up Offer", company: "7up" },
  { path: "/client/adco", manager: false, eventName: "Adco Offer", company: "Adco" },
  { path: "/promoter/512", manager: false, eventName: "Promoter 512", company: "Branch" },
  { path: "/portal/unilever", manager: true, eventName: "Portal Event", company: "Unilever" },
  { path: "/ops/unilever", manager: true, eventName: "Ops Event", company: "Unilever" },
  { path: "/agency/adco", manager: true, eventName: "Agency Event", company: "Adco" },
  { path: "/p/juhayna", manager: true, eventName: "Brand Event", company: "Juhayna" },
  { path: `/ep/${EVENT_ID}`, manager: true, eventName: "EP Event", company: "Agency Co" },
  { path: `/event/${EVENT_ID}`, manager: false, eventName: "Direct Event", company: "Direct Co" },
  { path: "/share/almarai", manager: false, eventName: "Share Event", company: "Almarai" },
];

function seedFor(sample) {
  const id = sample.path.split("?")[0].split("/").filter(Boolean)[1];
  return {
    [`events/${id}`]: {
      eventName: sample.eventName,
      targetCompany: sample.company,
      companySlug: id.toLowerCase(),
    },
  };
}

test("firebase.json regex rewrites match the function allowlist, in order", () => {
  const functionRules = hostingRewrites.filter((rule) => rule.function && rule.function !== "wahaProxy");
  assert.deepEqual(
    functionRules.map((rule) => rule.regex),
    SHARE_PREVIEW_REWRITES.map((rule) => rule.regex),
  );
  for (const rule of functionRules) {
    assert.equal(rule.function.functionId, "sharePreview");
    assert.equal(rule.function.region, "us-central1");
    assert.equal(rule.source, undefined);
  }
  assert.equal(hostingRewrites[0].source, "/waha/**");
  assert.equal(hostingRewrites[0].function, "wahaProxy");
  assert.equal(hostingRewrites.at(-1).source, "**");
  assert.equal(hostingRewrites.at(-1).destination, "/index.html");
  assert.equal(hostingRewrites.some((rule) => rule.function === "sharePreview"), false);
});

for (const sample of previewSamples) {
  test(`${sample.path} keeps its pre-change preview and is rewritten to sharePreview`, async () => {
    const pathname = sample.path.split("?")[0];
    const rule = resolveHostingRewrite(pathname);
    assert.equal(isSharePreviewRule(rule), true, pathname);

    const route = matchSharePreviewRoute("GET", sample.path);
    assert.equal(route.manager, sample.manager);
    assert.equal(route.id, pathname.split("/").filter(Boolean)[1]);

    const { res, db } = await invoke({ path: sample.path, seed: seedFor(sample) });
    assert.equal(res.statusCode, 200);
    assert.equal(res.headers["cache-control"], LONG_CACHE);
    assert.equal(res.headers["content-type"], "text/html; charset=utf-8");
    assert.match(res.body, /flutter_bootstrap\.js/);
    assert.match(res.body, /og:title/);
    const company = sample.company.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const eventName = sample.eventName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (sample.manager) {
      assert.match(res.body, new RegExp(`${company} • بوابة الشريك`));
    } else {
      assert.match(res.body, new RegExp(eventName));
      assert.equal(res.body.includes("بوابة الشريك"), false);
    }
    assert.ok(db.reads > 0);
  });
}

test("?event= on /c/<slug> and /ops/<slug> still selects that event", async () => {
  const seed = {
    "events/doc1": { eventName: "From Query", targetCompany: "Queried Co", companySlug: "other" },
  };
  const customer = await invoke({ path: "/c/almarai", query: { event: "doc1" }, seed });
  assert.equal(customer.res.statusCode, 200);
  assert.match(customer.res.body, /From Query/);
  assert.equal(customer.res.body.includes("بوابة الشريك"), false);

  const manager = await invoke({ path: "/ops/unilever", query: { event: "doc1" }, seed });
  assert.equal(manager.res.statusCode, 200);
  assert.match(manager.res.body, /بوابة الشريك/);
  assert.match(manager.res.body, /Queried Co/);
});

test("a word slug missed by doc id still resolves through companySlug", async () => {
  const { res } = await invoke({
    path: "/c/almarai",
    seed: { "events/abc": { companySlug: "almarai", eventName: "Slug Hit", targetCompany: "Almarai" } },
  });
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /Slug Hit/);
  assert.equal(res.body.includes("بوابة الشريك"), false);
});

test("a well-formed missing id still serves the generic preview shell", async () => {
  const { res, db } = await invoke({ path: "/c/999999" });
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /flutter_bootstrap\.js/);
  assert.equal(res.headers["cache-control"], LONG_CACHE);
  assert.ok(db.reads > 0);
});

test("HEAD /c/<id> is a preview response", async () => {
  const { res } = await invoke({
    method: "HEAD",
    path: "/c/469",
    seed: { "events/469": { eventName: "Campaign 469", targetCompany: "Acme", companySlug: "469" } },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.headers["cache-control"], LONG_CACHE);
  assert.match(res.body, /Campaign 469/);
});

const staticPaths = [
  "/c/469/subadmin",
  "/c/469/sugarcrm/index.php",
  "/c/469/~user",
  "/~user",
  "/~user/.cgi",
  "/index.cgi",
  "/c/469/foo.cgi",
  "/c/foo.cgi",
  "/c/469%2Fsubadmin",
  "/c/469//",
  "/portal/unilever/extra",
  "/ops/unilever/subadmin",
  "/event/abc/extra",
];

for (const reqPath of staticPaths) {
  test(`GET ${reqPath} misses every function rewrite and 404s with no Firestore read`, async () => {
    const rawPath = reqPath.split("?")[0];
    const decoded = decodeURIComponent(rawPath);
    for (const pathname of new Set([rawPath, decoded])) {
      const rule = resolveHostingRewrite(pathname);
      assert.equal(isSharePreviewRule(rule), false, pathname);
      assert.equal(rule && rule.destination, "/index.html");
    }

    const { res, db } = await invoke({
      path: reqPath,
      query: { event: "doc1" },
      seed: {
        "events/469": { eventName: "Campaign 469", targetCompany: "Acme", companySlug: "469" },
        "events/doc1": { eventName: "From Query", targetCompany: "Co", companySlug: "doc1" },
      },
    });
    assert.equal(res.statusCode, 404);
    assert.equal(res.body, "Not Found");
    assert.equal(res.headers["cache-control"], SHORT_CACHE);
    assert.equal(res.redirected, undefined);
    assert.equal(db.reads, 0);
  });
}

for (const method of ["POST", "PUT", "DELETE"]) {
  test(`${method} /c/469 is 404 with no Firestore read`, async () => {
    const { res, db } = await invoke({
      method,
      path: "/c/469",
      seed: { "events/469": { eventName: "Campaign 469", targetCompany: "Acme", companySlug: "469" } },
    });
    assert.equal(res.statusCode, 404);
    assert.equal(res.headers["cache-control"], SHORT_CACHE);
    assert.equal(db.reads, 0);
  });
}

test("sharePreview options cap maxInstances at 5", () => {
  assert.equal(SHARE_PREVIEW_MAX_INSTANCES, 5);
  const indexSrc = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
  assert.match(indexSrc, /maxInstances:\s*SHARE_PREVIEW_MAX_INSTANCES/);
  assert.match(indexSrc, /handleSharePreview\(req,\s*res,\s*db\)/);
});
