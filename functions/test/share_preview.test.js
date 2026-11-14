const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  matchSharePreviewRoute,
  handleSharePreview,
  clearSharePreviewCache,
  SHARE_PREVIEW_MAX_INSTANCES,
} = require("../share_preview");

const LONG_CACHE = "public, max-age=300, s-maxage=3600";
const SHORT_CACHE = "public, max-age=60, s-maxage=300";

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

test("matchSharePreviewRoute allows only /c/<digits> with one optional slash", () => {
  assert.deepEqual(matchSharePreviewRoute("GET", "/c/469"), { id: "469" });
  assert.deepEqual(matchSharePreviewRoute("get", "/c/469"), { id: "469" });
  assert.deepEqual(matchSharePreviewRoute("HEAD", "/c/469/"), { id: "469" });
  assert.deepEqual(matchSharePreviewRoute("HEAD", "/c/469/?event=abc"), { id: "469" });
  assert.deepEqual(matchSharePreviewRoute("GET", "/c/469?event=abc"), { id: "469" });

  const rejected = [
    ["POST", "/c/469"],
    ["PUT", "/c/469"],
    ["DELETE", "/c/469"],
    ["PATCH", "/c/469"],
    ["OPTIONS", "/c/469"],
    ["GET", "/c/almarai"],
    ["GET", "/c/469abc"],
    ["GET", "/c/46.9"],
    ["GET", "/c/469/subadmin"],
    ["GET", "/c/469/sugarcrm/index.php"],
    ["GET", "/c/469/~user"],
    ["GET", "/~user"],
    ["GET", "/~user/.cgi"],
    ["GET", "/index.cgi"],
    ["GET", "/c/469/foo.cgi"],
    ["GET", "/c/469%2Fsubadmin"],
    ["GET", "/c/469%2fsugarcrm/index.php"],
    ["GET", "/c/469/../470"],
    ["GET", "/c/469//"],
    ["GET", "/portal/469"],
    ["GET", "/event/469"],
    ["GET", "/ops/469"],
    ["GET", "/"],
    ["GET", "/c"],
    ["GET", "/c/"],
  ];
  for (const [method, reqPath] of rejected) {
    assert.equal(matchSharePreviewRoute(method, reqPath), null, `${method} ${reqPath}`);
  }
});

test("GET /c/<id> renders the preview when the event exists", async () => {
  const { res, db } = await invoke({
    path: "/c/469",
    seed: { "events/469": { eventName: "Campaign 469", targetCompany: "Acme" } },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.headers["cache-control"], LONG_CACHE);
  assert.equal(res.headers["content-type"], "text/html; charset=utf-8");
  assert.match(res.body, /Campaign 469/);
  assert.match(res.body, /og:title/);
  assert.match(res.body, /flutter_bootstrap\.js/);
  assert.ok(db.reads > 0);
});

test("trailing slash is the same preview", async () => {
  const { res, db } = await invoke({
    path: "/c/469/",
    seed: { "events/469": { eventName: "Campaign 469", targetCompany: "Acme" } },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.headers["cache-control"], LONG_CACHE);
  assert.match(res.body, /Campaign 469/);
  assert.ok(db.reads > 0);
});

test("HEAD /c/<id> is a preview response", async () => {
  const { res, db } = await invoke({
    method: "HEAD",
    path: "/c/469",
    seed: { "events/469": { eventName: "Campaign 469", targetCompany: "Acme" } },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.headers["cache-control"], LONG_CACHE);
  assert.match(res.body, /Campaign 469/);
  assert.ok(db.reads > 0);
});

test("numeric companySlug still resolves when the doc id does not", async () => {
  const { res } = await invoke({
    path: "/c/469",
    seed: { "events/abc": { companySlug: "469", eventName: "Slug Campaign" } },
  });
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /Slug Campaign/);
});

test("?event= on an exact numeric path still resolves that event", async () => {
  const { res, db } = await invoke({
    path: "/c/512",
    query: { event: "doc1" },
    seed: { "events/doc1": { eventName: "From Query", targetCompany: "Co" } },
  });
  assert.equal(res.statusCode, 200);
  assert.match(res.body, /From Query/);
  assert.ok(db.reads > 0);
});

test("unknown id is 404 after a Firestore lookup", async () => {
  const { res, db } = await invoke({ path: "/c/999999" });
  assert.equal(res.statusCode, 404);
  assert.equal(res.body, "Not Found");
  assert.equal(res.headers["cache-control"], SHORT_CACHE);
  assert.equal(res.headers["content-type"], "text/plain; charset=utf-8");
  assert.equal(res.redirected, undefined);
  assert.ok(db.reads > 0);
});

test("unknown id with a missing ?event= is 404", async () => {
  const { res, db } = await invoke({
    path: "/c/469",
    query: { event: "missing-doc" },
  });
  assert.equal(res.statusCode, 404);
  assert.equal(res.headers["cache-control"], SHORT_CACHE);
  assert.ok(db.reads > 0);
});

const rejectedRequests = [
  ["POST", "/c/469", "POST"],
  ["PUT", "/c/469", "PUT"],
  ["GET", "/c/almarai", "non-numeric slug"],
  ["GET", "/c/469abc", "non-numeric suffix"],
  ["GET", "/c/469/subadmin", "extra segment"],
  ["GET", "/c/469/sugarcrm/index.php", "sugarcrm path"],
  ["GET", "/c/469/~user", "tilde user under id"],
  ["GET", "/~user", "tilde user"],
  ["GET", "/~user/.cgi", "tilde cgi"],
  ["GET", "/index.cgi", "cgi"],
  ["GET", "/c/469/foo.cgi", "cgi under id"],
  ["GET", "/c/469%2Fsubadmin", "encoded extra segment"],
  ["GET", "/portal/469", "other hosting prefix"],
  ["GET", "/event/469", "event prefix"],
  ["GET", "/c/469//", "double slash"],
];

for (const [method, reqPath, label] of rejectedRequests) {
  test(`${label} (${method} ${reqPath}) is 404 with no Firestore read`, async () => {
    const { res, db } = await invoke({
      method,
      path: reqPath,
      query: { event: "doc1" },
      seed: {
        "events/469": { eventName: "Campaign 469", targetCompany: "Acme" },
        "events/doc1": { eventName: "From Query", targetCompany: "Co" },
      },
    });
    assert.equal(res.statusCode, 404, label);
    assert.equal(res.body, "Not Found");
    assert.equal(res.headers["cache-control"], SHORT_CACHE);
    assert.equal(res.redirected, undefined);
    assert.equal(db.reads, 0, `${label} must not read Firestore`);
  });
}

test("sharePreview options cap maxInstances at 5", () => {
  assert.equal(SHARE_PREVIEW_MAX_INSTANCES, 5);
  const indexSrc = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
  assert.match(indexSrc, /maxInstances:\s*SHARE_PREVIEW_MAX_INSTANCES/);
  assert.match(indexSrc, /handleSharePreview\(req,\s*res,\s*db\)/);
});
