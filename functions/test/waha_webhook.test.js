const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { handleWahaWebhook } = require("../waha_webhook");

const SECRET = "webhook-secret";

function createDb(seed = {}) {
  const docs = new Map(Object.entries(seed));
  function refFor(path) {
    return {
      path,
      id: path.split("/").pop(),
      async get() {
        const data = docs.get(path);
        return {
          exists: data !== undefined,
          id: path.split("/").pop(),
          data: () => (data ? Object.assign({}, data) : undefined),
          ref: refFor(path),
        };
      },
      set(data, opts) {
        const prev = docs.get(path) || {};
        docs.set(path, opts && opts.merge ? Object.assign({}, prev, data) : Object.assign({}, data));
        return Promise.resolve();
      },
    };
  }
  function collection(name) {
    return {
      doc(id) {
        return refFor(`${name}/${id}`);
      },
      where(field, _op, value) {
        const query = {
          limit() {
            return query;
          },
          async get() {
            const found = [];
            for (const [path, data] of docs) {
              if (path.startsWith(`${name}/`) && data[field] === value) {
                found.push({
                  id: path.split("/").pop(),
                  data: () => data,
                  ref: refFor(path),
                });
              }
            }
            return { empty: found.length === 0, docs: found };
          },
        };
        return query;
      },
    };
  }
  return {
    docs,
    collection,
    async runTransaction(fn) {
      const tx = {
        get(ref) {
          return ref.get();
        },
        set(ref, data, opts) {
          return ref.set(data, opts);
        },
        update(ref, data) {
          return ref.set(data, { merge: true });
        },
      };
      return fn(tx);
    },
  };
}

function response() {
  const res = {
    statusCode: 200,
    body: null,
    headers: {},
    set(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

function signedRequest(body, { token = SECRET, hmac = false, method = "POST" } = {}) {
  const raw = Buffer.from(JSON.stringify(body));
  const headers = { "x-webhook-token": token };
  if (hmac) {
    headers["x-webhook-hmac"] = crypto.createHmac("sha512", SECRET).update(raw).digest("hex");
  }
  return { method, headers, body, rawBody: raw };
}

function deps(extra = {}) {
  const calls = { verify: [], claim: [] };
  const db = extra.db || createDb();
  return {
    calls,
    db,
    deps: {
      secret: SECRET,
      apiKey: "api-key",
      db,
      baseUrl: "http://waha.internal:3000",
      now: () => 1_700_000_000_000,
      serverTimestamp: () => "ts",
      verifyReceiptImage: async (input) => {
        calls.verify.push(input);
        return extra.verification || { result: { isValid: true, receiptNumber: "R-1", prize_won: "Gift A" } };
      },
      applyCampaignPrizeClaim: async (dbArg, input) => {
        calls.claim.push({ dbArg, input });
        return extra.claimResult || { ok: true, applied: [{ prizeIdentifier: "Gift A", count: 1 }] };
      },
      downloadMedia: async () => ({ bytes: Buffer.from("image-bytes"), contentType: "image/jpeg" }),
      ...extra.deps,
    },
  };
}

test("rejects non-POST", async () => {
  const { deps: d } = deps();
  const res = response();
  await handleWahaWebhook({ method: "GET", headers: {}, body: {} }, res, d);
  assert.equal(res.statusCode, 405);
});

test("rejects a missing or wrong webhook token", async () => {
  const { deps: d } = deps();
  const missing = response();
  await handleWahaWebhook(signedRequest({ event: "message", payload: { id: "m1" } }, { token: "" }), missing, d);
  assert.equal(missing.statusCode, 401);
  assert.equal(missing.body.error, "invalid_webhook_token");

  const wrong = response();
  await handleWahaWebhook(signedRequest({ event: "message", payload: { id: "m1" } }, { token: "nope" }), wrong, d);
  assert.equal(wrong.statusCode, 401);
});

test("rejects a bad HMAC and accepts a sha512 HMAC of the raw body", async () => {
  const bad = response();
  const { deps: d } = deps();
  const req = signedRequest({ event: "message", payload: { id: "m-hmac", from: "201111111111@c.us", body: "hi" } }, { hmac: true });
  req.headers["x-webhook-hmac"] = "ab".repeat(32);
  await handleWahaWebhook(req, bad, d);
  assert.equal(bad.statusCode, 401);
  assert.equal(bad.body.error, "invalid_webhook_hmac");

  const ok = response();
  const good = signedRequest({
    event: "message",
    payload: { id: "m-hmac-ok", from: "201111111111@c.us", body: "hello", fromMe: false },
  }, { hmac: true });
  await handleWahaWebhook(good, ok, d);
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.body.stored, true);
});

test("stores text and ignores fromMe, groups, and status broadcasts", async () => {
  const bag = deps();
  const text = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    payload: { id: "text-1", from: "01012345678@c.us", body: "invoice please", fromMe: false },
  }), text, bag.deps);
  assert.equal(text.body.kind, "text");
  assert.equal(bag.db.docs.get("whatsapp_inbound_messages/text-1").phone, "201012345678");
  assert.equal(bag.db.docs.get("whatsapp_inbound_messages/text-1").status, "stored");

  for (const [id, from, extra] of [
    ["me-1", "201012345678@c.us", { fromMe: true }],
    ["grp-1", "120363@g.us", {}],
    ["st-1", "status@broadcast", {}],
  ]) {
    const res = response();
    await handleWahaWebhook(signedRequest({
      event: "message",
      payload: Object.assign({ id, from, body: "x" }, extra),
    }), res, bag.deps);
    assert.equal(res.body.ignored, true, id);
    assert.equal(bag.db.docs.get(`whatsapp_inbound_messages/${id}`).status, "ignored");
  }
  assert.equal(bag.calls.verify.length, 0);
  assert.equal(bag.calls.claim.length, 0);
});

test("stores an image without a sender link as pending and does not award", async () => {
  const bag = deps();
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    payload: {
      id: "img-pending",
      from: "201012345678@c.us",
      fromMe: false,
      hasMedia: true,
      media: { mimetype: "image/jpeg" },
    },
  }), res, bag.deps);
  assert.equal(res.body.pendingReview, true);
  assert.equal(bag.db.docs.get("whatsapp_inbound_messages/img-pending").reason, "no_sender_link");
  assert.equal(bag.calls.verify.length, 0);
  assert.equal(bag.calls.claim.length, 0);
});

test("verifies a linked image and decrements with the shared claim", async () => {
  const bag = deps({
    db: createDb({
      "whatsapp_sender_links/201012345678": {
        campaignId: "camp-1",
        companySlug: "acme",
        prizeIdentifier: "Gift A",
        branchId: "smouha",
      },
    }),
  });
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    session: "default",
    payload: {
      id: "img-award",
      from: "01012345678@c.us",
      fromMe: false,
      hasMedia: true,
      media: { mimetype: "image/jpeg", url: "http://evil.example/api/files/x" },
    },
  }), res, bag.deps);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.awarded, true);
  assert.equal(bag.calls.verify.length, 1);
  assert.equal(bag.calls.verify[0].campaignId, "camp-1");
  assert.equal(bag.calls.claim.length, 1);
  assert.equal(bag.calls.claim[0].input.eventId, "camp-1");
  assert.equal(bag.calls.claim[0].input.receiptId, "rcpt_camp-1_R-1");
  assert.equal(bag.calls.claim[0].input.decrements[0].prizeIdentifier, "Gift A");
  assert.equal(bag.calls.claim[0].input.decrements[0].branchId, "smouha");
  assert.equal(bag.calls.claim[0].input.actor.system, true);
  assert.equal(bag.db.docs.get("whatsapp_inbound_messages/img-award").status, "awarded");
});

test("does not decrement when verification rejects the invoice", async () => {
  const bag = deps({
    db: createDb({
      "whatsapp_sender_links/201012345678": { campaignId: "camp-1", companySlug: "acme", prizeIdentifier: "Gift A" },
    }),
    verification: { result: { isValid: false, message: "blurry" } },
  });
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    payload: {
      id: "img-bad",
      from: "201012345678@c.us",
      hasMedia: true,
      media: { mimetype: "image/png" },
    },
  }), res, bag.deps);
  assert.equal(res.body.rejected, true);
  assert.equal(bag.calls.claim.length, 0);
  assert.equal(bag.db.docs.get("whatsapp_inbound_messages/img-bad").status, "rejected");
});

test("dedupes a second delivery of the same message id", async () => {
  const bag = deps({
    db: createDb({
      "whatsapp_sender_links/201012345678": { campaignId: "camp-1", prizeIdentifier: "Gift A" },
    }),
  });
  const payload = {
    event: "message",
    payload: {
      id: "img-once",
      from: "201012345678@c.us",
      hasMedia: true,
      media: { mimetype: "image/jpeg" },
    },
  };
  const first = response();
  const second = response();
  await handleWahaWebhook(signedRequest(payload), first, bag.deps);
  await handleWahaWebhook(signedRequest(payload), second, bag.deps);
  assert.equal(first.body.awarded, true);
  assert.equal(second.body.duplicate, true);
  assert.equal(bag.calls.claim.length, 1);
});

test("records message.ack and updates an existing outbox row", async () => {
  const bag = deps({
    db: createDb({
      "whatsapp_outbox/true_2010_ABC": { to: "2010", body: "you won" },
      "receipts_transactions/rcpt-1": { whatsapp_message_id: "true_2010_ABC", prize_won: "Gift A" },
    }),
  });
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message.ack",
    session: "default",
    payload: { id: "true_2010_ABC", ack: 4, ackName: "READ" },
  }), res, bag.deps);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ack, "READ");
  assert.equal(bag.db.docs.get("whatsapp_message_status/true_2010_ABC").ackName, "READ");
  assert.equal(bag.db.docs.get("whatsapp_outbox/true_2010_ABC").whatsapp_ack_name, "READ");
  assert.equal(bag.db.docs.get("receipts_transactions/rcpt-1").whatsapp_ack, 4);
});
