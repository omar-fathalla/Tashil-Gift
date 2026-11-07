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

test("ignores messages when the webhook config is turned off", async () => {
  const bag = deps({
    db: createDb({
      "whatsapp_webhook_config/default": { enabled: false, autoRepliesEnabled: true },
      "whatsapp_sender_links/201012345678": { campaignId: "camp-1", prizeIdentifier: "Gift A" },
    }),
  });
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    payload: {
      id: "img-off",
      from: "201012345678@c.us",
      hasMedia: true,
      media: { mimetype: "image/jpeg" },
    },
  }), res, bag.deps);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ignored, true);
  assert.equal(res.body.reason, "webhook_disabled");
  assert.equal(bag.db.docs.get("whatsapp_inbound_messages/img-off"), undefined);
  assert.equal(bag.calls.verify.length, 0);
  assert.equal(bag.db.docs.get("whatsapp_webhook_config/default").lastEventName, "message");
});

test("rejects an unknown number when allow-list only is on and sends the reply", async () => {
  const sent = [];
  const bag = deps({
    db: createDb({
      "whatsapp_webhook_config/default": { enabled: true, allowListOnly: true, autoRepliesEnabled: true },
    }),
    deps: {
      sendText: async (input) => {
        sent.push(input);
        return { id: "waha-reply-1" };
      },
    },
  });
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    payload: {
      id: "img-blocked",
      from: "201099988877@c.us",
      hasMedia: true,
      media: { mimetype: "image/jpeg" },
    },
  }), res, bag.deps);
  assert.equal(res.body.notAllowed, true);
  const stored = bag.db.docs.get("whatsapp_inbound_messages/img-blocked");
  assert.equal(stored.status, "not_allowed");
  assert.equal(stored.replySent, true);
  assert.equal(stored.replyMessageId, "waha-reply-1");
  assert.match(stored.replyText, /غير مسموح/);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].phone, "201099988877");
  assert.equal(bag.calls.verify.length, 0);
});

test("registers an unknown number when the text is an open join code", async () => {
  const bag = deps({
    db: createDb({
      "whatsapp_webhook_config/default": { enabled: true, autoRepliesEnabled: true },
      "whatsapp_webhook_campaigns/camp-9": {
        joinCode: "JOIN9",
        selfRegistrationEnabled: true,
        campaignName: "Summer",
        companySlug: "acme",
      },
    }),
    deps: {
      sendText: async () => ({ id: "reg-1" }),
    },
  });
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    payload: { id: "join-1", from: "01055556666@c.us", body: "join JOIN9" },
  }), res, bag.deps);
  assert.equal(res.body.registered, true);
  assert.equal(res.body.campaignId, "camp-9");
  const link = bag.db.docs.get("whatsapp_sender_links/201055556666");
  assert.equal(link.campaignId, "camp-9");
  assert.equal(link.active, true);
  assert.equal(link.registeredVia, "join_code");
  const stored = bag.db.docs.get("whatsapp_inbound_messages/join-1");
  assert.equal(stored.status, "registered");
  assert.equal(stored.replyMessageId, "reg-1");
  assert.match(stored.replyText, /Summer/);
});

test("stores the Gemini analysis and the verified reply on an awarded invoice", async () => {
  const bag = deps({
    db: createDb({
      "whatsapp_webhook_config/default": {
        enabled: true,
        autoRepliesEnabled: true,
        templates: { verified: "Prize {prize} receipt {receipt}" },
      },
      "whatsapp_sender_links/201012345678": {
        campaignId: "camp-1",
        campaignName: "Durra",
        prizeIdentifier: "Gift A",
        displayName: "Nour",
        active: true,
      },
    }),
    verification: {
      result: {
        isValid: true,
        receiptNumber: "R-77",
        confidence: 0.91,
        storeChainDetected: "Gomla",
        message: "ok",
        prize_won: "Gift A",
      },
    },
    deps: {
      sendText: async () => ({ id: "award-reply" }),
    },
  });
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "message",
    payload: {
      id: "img-analysis",
      from: "201012345678@c.us",
      hasMedia: true,
      media: { mimetype: "image/jpeg" },
    },
  }), res, bag.deps);
  assert.equal(res.body.awarded, true);
  const stored = bag.db.docs.get("whatsapp_inbound_messages/img-analysis");
  assert.equal(stored.analysis.confidence, 0.91);
  assert.equal(stored.analysis.verdict, "valid");
  assert.equal(stored.analysis.receiptNumber, "R-77");
  assert.equal(stored.replyText, "receipt R-77");
  assert.ok(!stored.replyText.includes("Gift A"));
  assert.equal(stored.replyMessageId, "award-reply");
});

test("records session status onto the webhook health doc", async () => {
  const bag = deps();
  const res = response();
  await handleWahaWebhook(signedRequest({
    event: "session.status",
    session: "default",
    payload: { status: "WORKING" },
  }), res, bag.deps);
  assert.equal(res.statusCode, 200);
  assert.equal(bag.db.docs.get("whatsapp_webhook_config/default").lastSessionStatus, "WORKING");
  assert.equal(bag.db.docs.get("whatsapp_webhook_config/default").lastEventName, "session.status");
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

test("drops messages from a sender over the per-sender rate limit", async () => {
  const { RateLimitError } = require("../rate_limit");
  const seen = [];
  const { deps: d, calls } = deps({
    deps: {
      consumeRateLimit: async (args) => {
        seen.push(args);
        throw new RateLimitError("wahaSender", "min", 30);
      },
    },
  });
  const res = response();
  await handleWahaWebhook(
    signedRequest({ event: "message", session: "default", payload: { id: "rl1", from: "201000000000@c.us", hasMedia: true, body: "" } }),
    res,
    d,
  );
  assert.equal(seen.length, 1);
  assert.equal(seen[0].scope, "wahaSender");
  assert.equal(calls.verify.length, 0);
  assert.equal(calls.claim.length, 0);
});

test("2.0.158: verified reply never includes the prize name", () => {
  const { renderTemplate } = require("../waha_webhook");
  const vars = { name: "نور", prize: "Gift A", receipt: "R-1", campaign: "Durra" };
  const def = renderTemplate({}, "verified", vars);
  assert.ok(!def.includes("Gift A"));
  assert.ok(def.includes("ألف مبروك يا نور! كسبت معانا"));
  const old = renderTemplate({ templates: { verified: "تم التحقق من فاتورتك رقم {receipt}. جائزتك: {prize}. حملة {campaign}." } }, "verified", vars);
  assert.equal(old, "تم التحقق من فاتورتك رقم R-1. حملة Durra.");
});
