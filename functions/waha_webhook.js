const crypto = require("node:crypto");

const TOKEN_HEADER = "x-webhook-token";
const HMAC_HEADER = "x-webhook-hmac";
const TERMINAL_STATUSES = new Set([
  "stored",
  "ignored",
  "pending_review",
  "awarded",
  "rejected",
]);
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

  if (name === "session.status") {
    console.log("WAHA session.status", session, payload.status || payload);
    return json(res, 200, { ok: true, ignored: true, event: name });
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
  try {
    if (!isImageMessage(payload)) {
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
    if (!link) {
      await saveMessage(deps.db, messageId, {
        kind: "image",
        status: "pending_review",
        reason: "no_sender_link",
        phone,
        mimetype: mediaMime(payload),
        updatedAt: stamp,
      });
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
    if (result.isValid !== true) {
      await saveMessage(deps.db, messageId, {
        kind: "image",
        status: "rejected",
        reason: "invoice_not_valid",
        phone,
        campaignId: link.campaignId,
        message: result.message || null,
        updatedAt: stamp,
      });
      return json(res, 200, { ok: true, rejected: true, messageId });
    }

    const decrements = decrementsForAward(result, link);
    if (!decrements.length) {
      await saveMessage(deps.db, messageId, {
        kind: "image",
        status: "pending_review",
        reason: "verified_without_prize",
        phone,
        campaignId: link.campaignId,
        receiptNumber: result.receiptNumber || null,
        updatedAt: stamp,
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
        customerPhone: phone,
        submittedByUid: `whatsapp:${phone}`,
        source: "waha_webhook",
        waha_message_id: messageId,
        is_valid: true,
        timestamp: stamp,
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

    await saveMessage(deps.db, messageId, {
      kind: "image",
      status: "awarded",
      phone,
      campaignId: link.campaignId,
      receiptId,
      applied: claimResult.applied || [],
      updatedAt: stamp,
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
  handleWahaWebhook,
};
