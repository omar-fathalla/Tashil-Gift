/**
 * sendWinnerWhatsApp callable: sends the winner congratulation WhatsApp for one
 * accepted, handed-over receipt. All message data (phone, name, gift, branch,
 * company, campaign, receipt no.) comes from the stored receipt/event/company docs,
 * never from the client. Anonymous reps allowed (App Check enforced by callableOptions).
 * At most once per receipt (transactional claim flag). WAHA key stays server-side.
 */
const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const { consumeRateLimit, clientKey, RateLimitError } = require("./rate_limit");

// Same default as WhatsAppGatewayConfigModel.defaultWinnerTemplate (client).
const DEFAULT_TEMPLATE =
  "🎉 ألف مبروك يا {customer_name}! 🎁\n" +
  "📱 رقم الواتساب: {phone}\n\n" +
  "يسر {retail_chain} - {branch_name}\n" +
  "بالتعاون مع {company_name}\n" +
  "تهنئتكم بالفوز بـ:\n" +
  "✨ {prize_name} ✨\n" +
  "{voucher_details}" +
  "📌 تفاصيل المشاركة:\n" +
  "• الحملة: {campaign_name}\n" +
  "• رقم الفاتورة: {receipt_number}\n" +
  "• تاريخ الاستلام: {claim_date}\n\n" +
  "سعداء جداً بخدمتكم ونتمنى لكم تجربة تسوق ممتعة ومميزة دائماً! 🛍️✨";

const s = (v) => (v === undefined || v === null ? "" : String(v).trim());

function toWesternDigits(x) {
  return x.replace(/[٠-٩]/g, (d) => "٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/[۰-۹]/g, (d) => "۰۱۲۳۴۵۶۷۸۹".indexOf(d));
}

/** Same rules as WhatsAppGatewayService.formatInternationalPhone. */
function formatInternationalPhone(raw) {
  let c = toWesternDigits(s(raw)).replace(/\D/g, "");
  if (c.startsWith("00")) c = c.substring(2);
  if (c.startsWith("01") && c.length === 11) c = "2" + c;
  return c;
}

function isWinner(d) {
  if (!d) return false;
  const st = s(d.status).toLowerCase();
  if (st === "rejected" || d.is_valid === false) return false;
  if (!(st === "accepted" || d.is_valid === true)) return false;
  const gifts = Array.isArray(d.claimed_gifts) ? d.claimed_gifts : [];
  return s(d.claim_status) === "handed_over" || !!d.claimed_at || gifts.length > 0 ||
    (s(d.prize_won) && s(d.prize_won) !== "None");
}

function giftInfo(d) {
  const gifts = Array.isArray(d.claimed_gifts) ? d.claimed_gifts : [];
  const names = [];
  const serials = [];
  for (const g of gifts) {
    if (!g || typeof g !== "object") continue;
    const n = s(g.giftName || g.name);
    const q = Number(g.quantity || 1);
    if (n) names.push(q > 1 ? `${q} × ${n}` : n);
    for (const k of ["voucherSerials", "voucher_serials", "serials"]) {
      if (Array.isArray(g[k])) g[k].forEach((x) => s(x) && serials.push(s(x)));
    }
  }
  for (const k of ["voucher_serials", "voucherSerials"]) {
    if (Array.isArray(d[k])) d[k].forEach((x) => s(x) && !serials.includes(s(x)) && serials.push(s(x)));
  }
  let prize = s(d.prize_won);
  if (!prize || prize === "None") prize = names.join(" + ");
  if (!prize && Array.isArray(d.prizes_won)) prize = d.prizes_won.map(s).filter(Boolean).join(" + ");
  return { prize, serials };
}

function formatClaimDate(v) {
  let dt;
  if (v && typeof v.toDate === "function") dt = v.toDate();
  else if (typeof v === "string" && v) {
    // Client writes local (Cairo) wall time without zone: format it as-is.
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(v);
    if (m) {
      let h = Number(m[4]);
      const ap = h >= 12 ? "م" : "ص";
      h = h % 12 || 12;
      return `${m[1]}/${m[2]}/${m[3]} - ${String(h).padStart(2, "0")}:${m[5]} ${ap}`;
    }
  }
  dt = dt || new Date();
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Cairo", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: true,
  }).formatToParts(dt).map((x) => [x.type, x.value]));
  return `${p.year}/${p.month}/${p.day} - ${p.hour}:${p.minute} ${s(p.dayPeriod).toLowerCase() === "pm" ? "م" : "ص"}`;
}

function buildMessage(template, f) {
  const voucherDetails = f.serials.length ? `🎟️ كود الفواتشر / الرقم التسلسلي: ${f.serials.join(" ، ")}\n` : "";
  return (s(template) || DEFAULT_TEMPLATE)
    .split("{customer_name}").join(f.customerName || "عميلنا العزيز")
    .split("{phone}").join(f.phone || "")
    .split("{whatsapp}").join(f.phone || "")
    .split("{retail_chain}").join(f.chain || "المتجر")
    .split("{branch_name}").join(f.branch)
    .split("{company_name}").join(f.company || "إدارة العروض الترويجية")
    .split("{campaign_name}").join(f.campaign || "حملة الهدايا الفورية")
    .split("{prize_name}").join(f.prize)
    .split("{voucher_details}").join(voucherDetails)
    .split("{voucher_code}").join(f.serials[0] || "")
    .split("{receipt_number}").join(f.receipt || "بون الشراء المعتمد")
    .split("{claim_date}").join(f.claimDate);
}

async function wahaSend({ apiKey, base, session, phone, text }) {
  const headers = { "x-api-key": apiKey, "content-type": "application/json", accept: "application/json" };
  let chatId = `${phone}@c.us`;
  try {
    const r = await fetch(`${base}/api/contacts/check-exists?phone=${encodeURIComponent(phone)}&session=${encodeURIComponent(session)}`,
      { headers, signal: AbortSignal.timeout(10000) });
    if (r.ok) {
      const j = await r.json();
      if (j && j.numberExists === false) return { ok: false, code: "not-on-whatsapp", status: 404 };
      if (j && s(j.chatId)) chatId = s(j.chatId);
    }
  } catch (_) { /* fall back to phone@c.us */ }
  const r = await fetch(`${base}/api/sendText`, {
    method: "POST", headers, body: JSON.stringify({ session, chatId, text }),
    signal: AbortSignal.timeout(15000),
  });
  let j = null;
  try { j = await r.json(); } catch (_) { /* ignore */ }
  if (!r.ok) return { ok: false, code: "waha-error", status: r.status, chatId };
  const id = j && (j._data && j._data.id ? j._data.id._serialized || j._data.id.id :
    (j.id && typeof j.id === "object" ? j.id._serialized || j.id.id : j.id));
  const ack = j ? (j.ack !== undefined ? j.ack : (j._data ? j._data.ack : undefined)) : undefined;
  return { ok: true, status: r.status, chatId, messageId: s(id), ack: ack === undefined ? null : ack };
}

async function sendWinnerWhatsAppHandler(db, request, apiKey) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const receiptId = s(request.data && request.data.receiptId);
  if (!receiptId || receiptId.length > 200 || receiptId.includes("/")) {
    throw new HttpsError("invalid-argument", "receiptId is required.");
  }
  try {
    await consumeRateLimit({ db, scope: "winnerWa", key: clientKey({ uid: request.auth.uid, rawRequest: request.rawRequest }) });
  } catch (e) {
    if (e instanceof RateLimitError) throw new HttpsError("resource-exhausted", e.message);
    throw e;
  }

  const ref = db.collection("receipts_transactions").doc(receiptId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Receipt not found.");
  const d = snap.data();
  if (!isWinner(d)) throw new HttpsError("failed-precondition", "Receipt is not an accepted winning receipt.");

  const phone = formatInternationalPhone(d.customerPhone || d.customer_phone || d.phone);
  if (phone.length < 8) return { sent: false, reason: "no-phone" };

  const slug = s(d.companySlug);
  const eventId = s(d.campaignId || d.event_id);
  const [evSnap, coSnap] = await Promise.all([
    eventId ? db.collection("events").doc(eventId).get() : null,
    slug ? db.collection("companies").doc(slug).get() : null,
  ]);
  const ev = evSnap && evSnap.exists ? evSnap.data() : {};
  if (ev.enableWhatsAppWinnerNotification === false || ev.enable_whatsapp_winner_notification === false) {
    return { sent: false, reason: "disabled-for-campaign" };
  }
  const cfg = (coSnap && coSnap.exists && coSnap.data().whatsappGatewayConfig) || {};
  if (cfg.isEnabled === false || cfg.autoNotifyWinnersOnGiftHandover === false) {
    return { sent: false, reason: "disabled-for-company" };
  }
  const provider = s(cfg.provider || "waha").toLowerCase();
  if (provider && provider !== "waha") return { sent: false, reason: "provider-not-supported" };

  try {
    await consumeRateLimit({ db, scope: "winnerWaCompany", key: "co:" + (slug || "none") });
  } catch (e) {
    if (e instanceof RateLimitError) throw new HttpsError("resource-exhausted", e.message);
    throw e;
  }

  // Idempotency: claim the send slot atomically (once per receipt).
  const claimed = await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data() || {};
    const w = cur.whatsapp_winner || {};
    if (cur.whatsapp_notification_sent === true || w.status === "sent") return "already";
    const startedMs = w.startedAt && w.startedAt.toMillis ? w.startedAt.toMillis() : 0;
    if (w.status === "sending" && Date.now() - startedMs < 120000) return "inflight";
    tx.set(ref, { whatsapp_winner: { status: "sending", startedAt: FieldValue.serverTimestamp(), byUid: request.auth.uid } }, { merge: true });
    return "ok";
  });
  if (claimed !== "ok") return { sent: false, reason: claimed === "already" ? "already-sent" : "in-progress", alreadySent: claimed === "already" };

  const { prize, serials } = giftInfo(d);
  const text = buildMessage(cfg.winnerNotificationTemplate, {
    customerName: s(d.customerName || d.customer_name),
    phone: toWesternDigits(s(d.customerPhone || d.customer_phone || d.phone)) || phone,
    chain: s(d.retail_chain_name || ev.retailChainName || d.store_chain_detected),
    branch: s(d.canonical_branch || d.branch_detected),
    company: s(d.targetCompany || ev.targetCompany),
    campaign: s(ev.title || ev.name || ev.eventName),
    prize, serials,
    receipt: s(d.receipt_number || d.receiptNumber),
    claimDate: formatClaimDate(d.claimed_at),
  });

  const session = s(cfg.instanceId) || "default";
  const base = process.env.WAHA_BACKEND_URL || "https://waha.sw-point.com";
  let res;
  try {
    res = await wahaSend({ apiKey, base, session, phone, text });
  } catch (e) {
    res = { ok: false, code: "network", status: 0 };
  }
  const masked = phone.slice(0, 4) + "****" + phone.slice(-3);
  if (res.ok) {
    await ref.set({
      whatsapp_notification_sent: true,
      whatsapp_sent_at: FieldValue.serverTimestamp(),
      whatsapp_message_id: res.messageId || null,
      whatsapp_recipient_phone: phone,
      whatsapp_winner: { status: "sent", sentAt: FieldValue.serverTimestamp(), ack: res.ack, via: "sendWinnerWhatsApp" },
    }, { merge: true });
    console.log("sendWinnerWhatsApp sent", { receiptId, to: masked, status: res.status, messageId: res.messageId, ack: res.ack });
    return { sent: true, recipientPhone: s(d.customerPhone || phone), messageId: res.messageId || null, ack: res.ack };
  }
  await ref.set({ whatsapp_winner: { status: "failed", failedAt: FieldValue.serverTimestamp(), code: res.code, httpStatus: res.status } }, { merge: true });
  console.warn("sendWinnerWhatsApp failed", { receiptId, to: masked, code: res.code, status: res.status });
  return { sent: false, reason: res.code, recipientPhone: s(d.customerPhone || phone) };
}

module.exports = { sendWinnerWhatsAppHandler, buildMessage, formatInternationalPhone, isWinner, giftInfo, formatClaimDate };
