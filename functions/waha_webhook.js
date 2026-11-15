const { consumeRateLimit, RateLimitError } = require("./rate_limit");
const crypto = require("node:crypto");
const { componentReceiptNumbers } = require("./receipt_duplicate_check");

const TOKEN_HEADER = "x-webhook-token";
const HMAC_HEADER = "x-webhook-hmac";
const TERMINAL_STATUSES = new Set([
  "stored",
  "ignored",
  "pending_review",
  "awarded",
  "rejected",
  "not_allowed",
  "registered",
]);

const DEFAULT_TEMPLATES = {
  // 2.0.158: never name the gift to the customer (all companies).
  verified: "🎉 ألف مبروك يا {name}! كسبت معانا. تم التحقق من فاتورتك رقم {receipt} - {campaign}.",
  pendingReview: "مرحباً {name}، استلمنا رسالتك وهي قيد المراجعة لحملة {campaign}.",
  rejected: "تعذر قبول الفاتورة {receipt}. {campaign}",
  notAllowed: "هذا الرقم غير مسموح به. اطلب رابط الدعوة من المسؤول للانضمام.",
  registered: "تم تسجيلك يا {name} في حملة {campaign}. أرسل صورة الفاتورة الآن.",
};
const PROCESSING_LEASE_MS = 2 * 60 * 1000;

const ACK_NAMES = {
  0: "ERROR",
  1: "PENDING",
  2: "SERVER",
  3: "DEVICE",
  4: "READ",
  5: "PLAYED",
};

function headerValue(req, name) {
  const raw = req.headers && (req.headers[name] || req.headers[name.toLowerCase()]);
  if (Array.isArray(raw)) return String(raw[0] || "");
  return raw == null ? "" : String(raw);
}

function timingSafeEqualString(left, right) {
  const a = Buffer.from(String(left));
  const b = Buffer.from(String(right));
  if (a.length !== b.length) {
    crypto.timingSafeEqual(a, Buffer.alloc(a.length));
    return false;
  }
  return crypto.timingSafeEqual(a, b);
}

function rawBodyBuffer(req) {
  if (req.rawBody == null) return null;
  return Buffer.isBuffer(req.rawBody) ? req.rawBody : Buffer.from(req.rawBody);
}

function verifyWebhookAuth(req, secret) {
  const token = headerValue(req, TOKEN_HEADER).trim();
  if (!secret || !token || !timingSafeEqualString(token, secret)) {
    return { ok: false, status: 401, error: "invalid_webhook_token" };
  }

  const providedHmac = headerValue(req, HMAC_HEADER).trim();
  if (!providedHmac) return { ok: true };

  const raw = rawBodyBuffer(req);
  if (!raw) {
    return { ok: false, status: 401, error: "missing_raw_body" };
  }
  const expected = crypto.createHmac("sha512", secret).update(raw).digest("hex");
  if (!timingSafeEqualString(providedHmac.toLowerCase(), expected.toLowerCase())) {
    return { ok: false, status: 401, error: "invalid_webhook_hmac" };
  }
  return { ok: true };
}

function formatInternationalPhone(rawPhone) {
  let clean = String(rawPhone || "").trim();
  clean = clean.replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)));
  clean = clean.replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)));
  clean = clean.replace(/\D/g, "");
  if (clean.startsWith("00")) clean = clean.slice(2);
  if (clean.startsWith("01") && clean.length === 11) clean = `2${clean}`;
  return clean;
}

function phoneFromJid(jid) {
  const local = String(jid || "").split("@")[0].split(":")[0];
  return formatInternationalPhone(local);
}

function phoneVariants(phone) {
  const variants = [];
  const push = (value) => {
    if (value && !variants.includes(value)) variants.push(value);
  };
  push(phone);
  if (phone.startsWith("20") && phone.length === 12) push(phone.slice(1));
  if (phone.startsWith("0") && phone.length === 11) push(`2${phone}`);
  return variants;
}

function safeDocId(messageId) {
  const clean = String(messageId || "").trim().replace(/[/\s]/g, "_");
  if (!clean) return crypto.createHash("sha256").update(String(messageId)).digest("hex");
  return clean.slice(0, 700);
}

function receiptDocId(campaignId, receiptNumber) {
  const cleanCampaign = String(campaignId || "").trim().replace(/[/\\?%*:|"<>\s]/g, "_");
  const cleanReceipt = String(receiptNumber || "").trim().replace(/\s+/g, "").replace(/[/\\?%*:|"<>\s]/g, "_") || "UNKNOWN";
  return `rcpt_${cleanCampaign}_${cleanReceipt}`;
}

function isGroupOrStatus(payload) {
  const from = String((payload && (payload.from || payload.chatId)) || "");
  if (payload && (payload.fromMe === true || payload.fromMe === "true")) return "from_me";
  if (from === "status@broadcast" || from.endsWith("@broadcast")) return "status";
  if (from.endsWith("@g.us") || payload.isGroup === true || payload.isGroupMsg === true) return "group";
  return "";
}

function mediaMime(payload) {
  const media = payload && payload.media;
  return String(
    (media && (media.mimetype || media.mimeType))
    || payload.mimetype
    || payload.mimeType
    || "",
  ).toLowerCase();
}

function isImageMessage(payload) {
  if (!payload || payload.hasMedia !== true) return false;
  return mediaMime(payload).startsWith("image/");
}

function resolveMediaUrl(baseUrl, mediaUrl) {
  if (!mediaUrl) return null;
  let base;
  try {
    base = new URL(baseUrl);
    const parsed = new URL(mediaUrl, base);
    if (!parsed.pathname.startsWith("/api/")) return null;
    return new URL(`${parsed.pathname}${parsed.search}`, base).toString();
  } catch (_) {
    return null;
  }
}

async function downloadWahaMedia({ baseUrl, apiKey, session, messageId, payload, fetchImpl }) {
  const fetchFn = fetchImpl || fetch;
  const direct = resolveMediaUrl(baseUrl, payload.media && payload.media.url);
  const fallback = new URL(
    `/api/${encodeURIComponent(session || "default")}/messages/${encodeURIComponent(messageId)}/download`,
    baseUrl,
  ).toString();
  const url = direct || fallback;
  const response = await fetchFn(url, {
    method: "GET",
    headers: { "x-api-key": apiKey || "" },
  });
  if (!response.ok) {
    throw new Error(`WAHA media download failed (${response.status})`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  const contentType = (response.headers && response.headers.get && response.headers.get("content-type")) || mediaMime(payload);
  return { bytes, contentType: String(contentType || "") };
}

function decrementsForAward(result, link) {
  const decrements = [];
  const branchId = String((link && link.branchId) || "");
  const push = (prizeIdentifier, extra) => {
    const id = String(prizeIdentifier || "").trim();
    if (!id) return;
    decrements.push({
      prizeIdentifier: id,
      branchId: (extra && extra.branchId) || branchId,
      count: (extra && extra.count) || 1,
      unitValue: extra && typeof extra.unitValue === "number" ? extra.unitValue : null,
      isVoucher: !!(extra && extra.isVoucher),
      gameType: "whatsapp",
    });
  };

  if (result && Array.isArray(result.prizes_won)) {
    for (const prize of result.prizes_won) {
      if (typeof prize === "string") push(prize);
      else if (prize) push(prize.prizeIdentifier || prize.name || prize.giftId, prize);
    }
  }
  if (result && result.prize_won) push(result.prize_won);
  if (!decrements.length && link && link.prizeIdentifier) {
    push(link.prizeIdentifier, {
      count: Number(link.prizeCount) || 1,
      unitValue: typeof link.unitValue === "number" ? link.unitValue : null,
      isVoucher: link.isVoucher === true,
      branchId,
    });
  }
  return decrements;
}

async function findSenderLink(db, phone) {
  for (const variant of phoneVariants(phone)) {
    const snap = await db.collection("whatsapp_sender_links").doc(variant).get();
    if (snap.exists) {
      const data = snap.data() || {};
      if (data.campaignId) return Object.assign({ phone: variant }, data);
    }
  }
  return null;
}

function json(res, status, body) {
  res.status(status).json(body);
}

function stripPrizePlaceholder(template) {
  return String(template)
    .replace(/(?:جائزتك|جائزتكم|الجائزة|هديتك|هديتكم|الهدية|your\s+prize|prize|gift)\s*[:：-]?\s*\{prize\}\s*[.،,!]?/giu, "")
    .replaceAll("{prize}", "")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\s+([.،,!])/g, "$1")
    .trim();
}

function renderTemplate(config, key, vars) {
  const custom = config && config.templates && config.templates[key];
  const template = String((custom && String(custom).trim()) || DEFAULT_TEMPLATES[key] || "");
  const values = vars || {};
  // 2.0.158: the prize/gift name is never sent; saved custom templates that
  // still use {prize} lose it together with its label (e.g. "جائزتك: ").
  return stripPrizePlaceholder(template)
    .replaceAll("{name}", String(values.name || "").trim() || "عميلنا العزيز")
    .replaceAll("{receipt}", String(values.receipt || ""))
    .replaceAll("{campaign}", String(values.campaign || ""));
}

function extractJoinCode(body) {
  const text = String(body || "").trim();
  if (!text || text.length > 80) return "";
  const prefixed = text.match(/^(?:join|code|انضم|كود)\s*[:#-]?\s*([A-Za-z0-9]{4,16})$/i);
  if (prefixed) return prefixed[1].toUpperCase();
  if (/^[A-Za-z0-9]{4,16}$/.test(text)) return text.toUpperCase();
  return "";
}

async function loadWebhookConfig(db) {
  const snap = await db.collection("whatsapp_webhook_config").doc("default").get();
  const data = snap.exists ? (snap.data() || {}) : {};
  return {
    enabled: data.enabled !== false,
    autoRepliesEnabled: data.autoRepliesEnabled === true,
    allowListOnly: data.allowListOnly === true,
    templates: data.templates && typeof data.templates === "object" ? data.templates : {},
    businessDisplayName: String(data.businessDisplayName || ""),
  };
}

async function stampWebhookHealth(db, fields) {
  await db.collection("whatsapp_webhook_config").doc("default").set(fields, { merge: true });
}

function analysisFromResult(result) {
  const value = result || {};
  return {
    isValid: value.isValid === true,
    verdict: value.isValid === true ? "valid" : "rejected",
    receiptNumber: value.receiptNumber || null,
    message: value.message || null,
    storeChainDetected: value.storeChainDetected || null,
    branchDetected: value.branchDetected || null,
    isBranchMatched: value.isBranchMatched === true,
    confidence: typeof value.confidence === "number" ? value.confidence : null,
    prizeWon: value.prize_won || null,
    prizesWon: Array.isArray(value.prizes_won) ? value.prizes_won : null,
  };
}

function linkIsActive(link) {
  return !!(link && link.campaignId && link.active !== false);
}

async function findOpenCampaign(db, code) {
  if (!code) return null;
  const snap = await db.collection("whatsapp_webhook_campaigns")
    .where("joinCode", "==", code)
    .limit(5)
    .get();
  const docs = snap && snap.docs ? snap.docs : [];
  for (const docSnap of docs) {
    const data = docSnap.data() || {};
    if (data.selfRegistrationEnabled === true) {
      return Object.assign({ campaignId: docSnap.id }, data);
    }
  }
  return null;
}

async function sendWahaText({ baseUrl, apiKey, session, phone, text, fetchImpl }) {
  const fetchFn = fetchImpl || fetch;
  const url = new URL("/api/sendText", baseUrl).toString();
  const response = await fetchFn(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey || "",
    },
    body: JSON.stringify({
      session: session || "default",
      chatId: `${phone}@c.us`,
      text,
    }),
  });
  if (!response.ok) {
    const errText = typeof response.text === "function" ? await response.text() : "";
    throw new Error(`WAHA sendText failed (${response.status}) ${String(errText).slice(0, 180)}`);
  }
  const payload = typeof response.json === "function" ? await response.json() : {};
  const rawId = payload && payload.id;
  const messageId = typeof rawId === "string"
    ? rawId
    : (rawId && (rawId.id || rawId._serialized)) || (payload && payload.key && payload.key.id) || "";
  return { id: String(messageId || "") };
}

async function completeInbound(deps, ctx, fields, templateKey, vars) {
  const replyText = templateKey ? renderTemplate(ctx.config, templateKey, vars) : "";
  let replyMessageId = "";
  let replySent = false;
  let replyError = "";
  if (ctx.config.autoRepliesEnabled && replyText && ctx.phone) {
    try {
      const sender = deps.sendText || sendWahaText;
      const sent = await sender({
        baseUrl: deps.baseUrl,
        apiKey: deps.apiKey,
        session: ctx.session,
        phone: ctx.phone,
        text: replyText,
        fetchImpl: deps.fetchImpl,
      });
      replyMessageId = sent && sent.id ? sent.id : "";
      replySent = true;
    } catch (err) {
      replyError = String(err && err.message || err).slice(0, 300);
    }
  }
  await saveMessage(deps.db, ctx.messageId, Object.assign({}, fields, {
    replyText: replyText || null,
    replyMessageId: replyMessageId || null,
    replySent,
    replyError: replyError || null,
    updatedAt: ctx.stamp,
  }));
  return { replyText, replyMessageId, replySent };
}

async function handleWahaWebhook(req, res, deps) {
  if (req.method !== "POST") {
    res.set("Allow", "POST");
    return json(res, 405, { ok: false, error: "method_not_allowed" });
  }

  const auth = verifyWebhookAuth(req, deps.secret);
  if (!auth.ok) return json(res, auth.status, { ok: false, error: auth.error });

  let event;
  try {
    if (req.body && typeof req.body === "object" && !Buffer.isBuffer(req.body)) {
      event = req.body;
    } else {
      const raw = rawBodyBuffer(req);
      event = raw ? JSON.parse(raw.toString("utf8")) : {};
    }
  } catch (_) {
    return json(res, 400, { ok: false, error: "invalid_json" });
  }

  const name = String(event.event || "");
  const payload = event.payload || {};
  const session = String(event.session || payload.session || "default");
  const now = typeof deps.now === "function" ? deps.now() : Date.now();
  const stamp = typeof deps.serverTimestamp === "function" ? deps.serverTimestamp() : new Date(now).toISOString();

  let config;
  try {
    config = await loadWebhookConfig(deps.db);
  } catch (err) {
    console.error("WAHA config read failed", err);
    return json(res, 500, { ok: false, error: "config_unavailable" });
  }

  const sessionStatus = payload.status || payload.state || "";
  const health = {
    lastEventAt: stamp,
    lastEventAtMs: now,
    lastEventName: name || "unknown",
    updatedAt: stamp,
  };
  if (name === "session.status") health.lastSessionStatus = String(sessionStatus || "");
  await stampWebhookHealth(deps.db, health).catch((err) => console.error("WAHA health stamp failed", err));

  if (!config.enabled) {
    return json(res, 200, { ok: true, ignored: true, reason: "webhook_disabled" });
  }

  if (name === "session.status") {
    console.log("WAHA session.status", session, sessionStatus || payload);
    return json(res, 200, { ok: true, ignored: true, event: name, sessionStatus: String(sessionStatus || "") });
  }

  if (name === "message.ack") {
    return recordAck(req, res, deps, { event, payload, session, stamp });
  }

  if (name !== "message") {
    return json(res, 200, { ok: true, ignored: true, event: name || "unknown" });
  }

  const messageId = String(payload.id || payload.key && payload.key.id || "").trim();
  if (!messageId) return json(res, 400, { ok: false, error: "missing_message_id" });

  const claim = await claimMessage(deps.db, messageId, {
    event: name,
    session,
    from: payload.from || null,
    receivedAt: stamp,
    updatedAt: stamp,
  }, now);
  if (claim.duplicate) {
    return json(res, 200, { ok: true, duplicate: true, messageId, status: claim.status });
  }

  const skip = isGroupOrStatus(payload);
  if (skip) {
    await saveMessage(deps.db, messageId, { status: "ignored", reason: skip, updatedAt: stamp });
    return json(res, 200, { ok: true, ignored: true, reason: skip, messageId });
  }

  const phone = phoneFromJid(payload.from);
  // Per-sender rate limit: drop floods from one number before any Gemini/media work.
  try {
    const consume = deps.consumeRateLimit || consumeRateLimit;
    await consume({ db: deps.db, scope: "wahaSender", key: "phone:" + (phone || payload.from || "unknown"), now });
  } catch (err) {
    if (err instanceof RateLimitError) {
      await saveMessage(deps.db, messageId, { status: "ignored", reason: "rate_limited", updatedAt: stamp });
      return json(res, 200, { ok: true, ignored: true, reason: "rate_limited", messageId });
    }
    console.warn("wahaSender rate limit check failed (fail-open):", err && err.message);
  }
  const ctx = { config, messageId, phone, session, stamp };
  try {
    if (!isImageMessage(payload)) {
      const joinCode = extractJoinCode(payload.body);
      const campaign = joinCode ? await findOpenCampaign(deps.db, joinCode) : null;
      if (campaign) {
        await deps.db.collection("whatsapp_sender_links").doc(phone).set({
          phone,
          campaignId: campaign.campaignId,
          companySlug: campaign.companySlug || "",
          campaignName: campaign.campaignName || campaign.campaignId,
          prizeIdentifier: campaign.prizeIdentifier || "",
          active: true,
          registeredVia: "join_code",
          updatedAt: stamp,
        }, { merge: true });
        await completeInbound(deps, ctx, {
          kind: "text",
          status: "registered",
          reason: "join_code",
          phone,
          body: String(payload.body || "").slice(0, 4000),
          campaignId: campaign.campaignId,
          joinCode,
        }, "registered", {
          name: phone,
          campaign: campaign.campaignName || campaign.campaignId,
        });
        return json(res, 200, { ok: true, registered: true, messageId, campaignId: campaign.campaignId });
      }

      const known = linkIsActive(await findSenderLink(deps.db, phone));
      if (!known && config.allowListOnly) {
        await completeInbound(deps, ctx, {
          kind: "text",
          status: "not_allowed",
          reason: "not_allowed",
          phone,
          body: String(payload.body || "").slice(0, 4000),
        }, "notAllowed", { name: phone });
        return json(res, 200, { ok: true, notAllowed: true, messageId });
      }

      console.log("WAHA text message", messageId, phone);
      await saveMessage(deps.db, messageId, {
        kind: "text",
        status: "stored",
        phone,
        body: String(payload.body || "").slice(0, 4000),
        updatedAt: stamp,
      });
      return json(res, 200, { ok: true, stored: true, kind: "text", messageId });
    }

    const link = await findSenderLink(deps.db, phone);
    if (!linkIsActive(link)) {
      if (config.allowListOnly) {
        await completeInbound(deps, ctx, {
          kind: "image",
          status: "not_allowed",
          reason: "not_allowed",
          phone,
          mimetype: mediaMime(payload),
        }, "notAllowed", { name: (link && link.displayName) || phone });
        return json(res, 200, { ok: true, notAllowed: true, messageId });
      }
      await completeInbound(deps, ctx, {
        kind: "image",
        status: "pending_review",
        reason: "no_sender_link",
        phone,
        mimetype: mediaMime(payload),
      }, "pendingReview", { name: phone });
      return json(res, 200, { ok: true, pendingReview: true, messageId });
    }

    const download = deps.downloadMedia || downloadWahaMedia;
    const media = await download({
      baseUrl: deps.baseUrl,
      apiKey: deps.apiKey,
      session,
      messageId,
      payload,
      fetchImpl: deps.fetchImpl,
    });
    const imagePayload = media.bytes.toString("base64");
    const verified = await deps.verifyReceiptImage({
      db: deps.db,
      campaignId: link.campaignId,
      imagePayload,
      forceRefresh: false,
    });
    const result = (verified && verified.result) || {};
    const analysis = analysisFromResult(result);
    const campaignLabel = link.campaignName || link.campaignId;
    const senderName = link.displayName || phone;
    if (result.isValid !== true) {
      await completeInbound(deps, ctx, {
        kind: "image",
        status: "rejected",
        reason: "invoice_not_valid",
        phone,
        campaignId: link.campaignId,
        message: result.message || null,
        analysis,
      }, "rejected", {
        name: senderName,
        receipt: result.receiptNumber || "",
        campaign: campaignLabel,
      });
      return json(res, 200, { ok: true, rejected: true, messageId });
    }

    const decrements = decrementsForAward(result, link);
    if (!decrements.length) {
      await completeInbound(deps, ctx, {
        kind: "image",
        status: "pending_review",
        reason: "verified_without_prize",
        phone,
        campaignId: link.campaignId,
        receiptNumber: result.receiptNumber || null,
        analysis,
      }, "pendingReview", {
        name: senderName,
        receipt: result.receiptNumber || "",
        campaign: campaignLabel,
      });
      return json(res, 200, { ok: true, pendingReview: true, reason: "verified_without_prize", messageId });
    }

    const receiptNumber = String(result.receiptNumber || messageId);
    const receiptId = receiptDocId(link.campaignId, receiptNumber);
    const prizeNames = decrements.map((item) => item.prizeIdentifier);
    const claimResult = await deps.applyCampaignPrizeClaim(deps.db, {
      eventId: link.campaignId,
      receiptId,
      decrements,
      receiptCreate: {
        campaignId: link.campaignId,
        event_id: link.campaignId,
        companySlug: link.companySlug || "",
        receipt_number: receiptNumber,
        component_receipt_numbers: componentReceiptNumbers(receiptNumber),
        customerPhone: phone,
        submittedByUid: `whatsapp:${phone}`,
        source: "waha_webhook",
        waha_message_id: messageId,
        is_valid: true,
        timestamp: stamp,
        ...(result.receiptDate ? { receipt_date: String(result.receiptDate) } : {}),
        ...(Array.isArray(result.extractedProducts) && result.extractedProducts.length
          ? { extracted_products: result.extractedProducts }
          : {}),
      },
      receiptPatch: {
        game_played: true,
        game_type: "whatsapp",
        prize_won: prizeNames[0],
        prizes_won: prizeNames,
        claim_status: "claimed",
        claimed_at: stamp,
      },
      actor: {
        staff: false,
        partner: false,
        anonymous: false,
        system: true,
        allowCreateReceipt: true,
        uid: "waha-webhook",
        token: {},
      },
    });

    await completeInbound(deps, ctx, {
      kind: "image",
      status: "awarded",
      phone,
      campaignId: link.campaignId,
      receiptId,
      receiptNumber,
      prize: prizeNames.join(", "),
      applied: claimResult.applied || [],
      analysis,
    }, "verified", {
      name: senderName,
      prize: prizeNames.join(", "),
      receipt: receiptNumber,
      campaign: campaignLabel,
    });
    return json(res, 200, { ok: true, awarded: true, messageId, receiptId });
  } catch (err) {
    console.error("WAHA message handling failed", messageId, err);
    await saveMessage(deps.db, messageId, {
      status: "error",
      error: String(err && err.message || err).slice(0, 500),
      updatedAt: stamp,
    }).catch(() => {});
    return json(res, 500, { ok: false, error: "processing_failed", messageId });
  }
}

async function claimMessage(db, messageId, fields, now) {
  const ref = db.collection("whatsapp_inbound_messages").doc(safeDocId(messageId));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      const data = snap.data() || {};
      const status = data.status || "";
      const updatedAtMs = Number(data.updatedAtMs || 0);
      const stale = status === "processing" && now - updatedAtMs > PROCESSING_LEASE_MS;
      if (TERMINAL_STATUSES.has(status) || (status === "processing" && !stale)) {
        return { duplicate: true, status };
      }
    }
    tx.set(ref, Object.assign({}, fields, {
      messageId,
      status: "processing",
      updatedAtMs: now,
    }), { merge: true });
    return { duplicate: false, status: "processing" };
  });
}

async function saveMessage(db, messageId, fields) {
  await db.collection("whatsapp_inbound_messages").doc(safeDocId(messageId)).set(
    Object.assign({ messageId }, fields),
    { merge: true },
  );
}

async function recordAck(req, res, deps, { payload, session, stamp }) {
  const messageId = String(payload.id || "").trim();
  if (!messageId) return json(res, 400, { ok: false, error: "missing_message_id" });
  const ack = Number(payload.ack);
  const ackName = String(payload.ackName || ACK_NAMES[ack] || "UNKNOWN");
  const status = {
    messageId,
    session,
    ack: Number.isFinite(ack) ? ack : null,
    ackName,
    updatedAt: stamp,
  };
  console.log("WAHA message.ack", messageId, ackName);
  await deps.db.collection("whatsapp_message_status").doc(safeDocId(messageId)).set(status, { merge: true });

  const outboxRef = deps.db.collection("whatsapp_outbox").doc(safeDocId(messageId));
  const outbox = await outboxRef.get();
  if (outbox.exists) {
    await outboxRef.set({
      ack: status.ack,
      ackName,
      whatsapp_ack: status.ack,
      whatsapp_ack_name: ackName,
      updatedAt: stamp,
    }, { merge: true });
  }

  const receipts = await deps.db.collection("receipts_transactions")
    .where("whatsapp_message_id", "==", messageId)
    .limit(5)
    .get();
  const docs = receipts && receipts.docs ? receipts.docs : [];
  await Promise.all(docs.map((docSnap) => {
    const ref = docSnap.ref || deps.db.collection("receipts_transactions").doc(docSnap.id);
    return ref.set({
      whatsapp_ack: status.ack,
      whatsapp_ack_name: ackName,
      whatsapp_ack_at: stamp,
    }, { merge: true });
  }));

  return json(res, 200, { ok: true, ack: ackName, messageId });
}

module.exports = {
  stripPrizePlaceholder,
  renderTemplate,
  TOKEN_HEADER,
  HMAC_HEADER,
  formatInternationalPhone,
  phoneFromJid,
  safeDocId,
  receiptDocId,
  verifyWebhookAuth,
  timingSafeEqualString,
  decrementsForAward,
  resolveMediaUrl,
  renderTemplate,
  extractJoinCode,
  DEFAULT_TEMPLATES,
  handleWahaWebhook,
};
