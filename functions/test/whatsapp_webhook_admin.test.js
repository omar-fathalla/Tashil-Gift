const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assertWebhookStaff,
  applyWebhookConfigUpdate,
  applySenderLinkChange,
  updateWhatsappWebhookConfig,
  manageWhatsappSenderLink,
} = require("../whatsapp_webhook_admin");

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
        };
      },
      set(data, opts) {
        const prev = docs.get(path) || {};
        docs.set(path, opts && opts.merge ? Object.assign({}, prev, data) : Object.assign({}, data));
        return Promise.resolve();
      },
      delete() {
        docs.delete(path);
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
  return { docs, collection };
}

function staffRequest(role) {
  return {
    app: { appId: "test" },
    auth: { uid: "staff-1", token: { role } },
    data: {},
  };
}

test("staff check allows super_admin and admin and rejects everyone else", () => {
  assert.doesNotThrow(() => assertWebhookStaff(staffRequest("super_admin")));
  assert.doesNotThrow(() => assertWebhookStaff(staffRequest("admin")));
  assert.throws(() => assertWebhookStaff(staffRequest("partner")), /super_admin or admin/);
  assert.throws(() => assertWebhookStaff({ app: {}, auth: null }), /Sign-in/);
  assert.throws(() => assertWebhookStaff({ app: null, auth: { uid: "x", token: { role: "admin" } } }), /App Check/);
});

test("config update writes toggles, number, templates, and a campaign join code", async () => {
  const db = createDb();
  const result = await applyWebhookConfigUpdate(db, {
    enabled: false,
    autoRepliesEnabled: true,
    allowListOnly: true,
    businessNumber: "01012345678",
    businessDisplayName: "Tashil Desk",
    templates: { verified: "Hello {name}", ignored: "nope" },
    campaign: {
      campaignId: "camp-1",
      campaignName: "Durra",
      companySlug: "Acme",
      selfRegistrationEnabled: true,
      joinCode: "join1",
      prizeIdentifier: "Gift A",
    },
  }, () => "stamp");
  assert.equal(result.ok, true);
  const config = db.docs.get("whatsapp_webhook_config/default");
  assert.equal(config.enabled, false);
  assert.equal(config.autoRepliesEnabled, true);
  assert.equal(config.allowListOnly, true);
  assert.equal(config.businessNumber, "201012345678");
  assert.equal(config.businessDisplayName, "Tashil Desk");
  assert.equal(config.templates.verified, "Hello {name}");
  assert.equal(config.templates.ignored, undefined);
  const campaign = db.docs.get("whatsapp_webhook_campaigns/camp-1");
  assert.equal(campaign.joinCode, "JOIN1");
  assert.equal(campaign.selfRegistrationEnabled, true);
  assert.equal(campaign.companySlug, "acme");
});

test("join codes cannot collide and sender links upsert and delete", async () => {
  const db = createDb({
    "whatsapp_webhook_campaigns/other": { joinCode: "JOIN1" },
  });
  await assert.rejects(
    () => applyWebhookConfigUpdate(db, {
      campaign: { campaignId: "camp-2", joinCode: "JOIN1", selfRegistrationEnabled: true },
    }, () => "stamp"),
    /already used/,
  );

  const saved = await applySenderLinkChange(db, {
    action: "upsert",
    phone: "01099998877",
    campaignId: "camp-2",
    campaignName: "Durra",
    prizeIdentifier: "Voucher 50",
    displayName: "Sara",
    active: false,
    companySlug: "Acme",
  }, () => "stamp");
  assert.equal(saved.phone, "201099998877");
  const link = db.docs.get("whatsapp_sender_links/201099998877");
  assert.equal(link.campaignId, "camp-2");
  assert.equal(link.active, false);
  assert.equal(link.prizeIdentifier, "Voucher 50");
  assert.equal(link.registeredVia, "admin");

  const removed = await applySenderLinkChange(db, {
    action: "delete",
    phone: "201099998877",
  }, () => "stamp");
  assert.equal(removed.deleted, true);
  assert.equal(db.docs.get("whatsapp_sender_links/201099998877"), undefined);
});

test("admin callables enforce App Check and are gen2", () => {
  for (const fn of [updateWhatsappWebhookConfig, manageWhatsappSenderLink]) {
    assert.equal(fn.__endpoint.platform, "gcfv2");
    assert.deepEqual(fn.__endpoint.region, ["us-central1"]);
    assert.equal(fn.__endpoint.availableMemoryMb, 256);
  }
});
