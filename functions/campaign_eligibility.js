"use strict";

/**
 * Server-side campaign eligibility for a gift claim.
 *
 * Before any stock decrement the server re-verifies, from the stored campaign
 * and the stored receipt, what the upload page only checked on the client:
 *   1. the campaign is active and the receipt is inside the date window
 *      (whole Africa/Cairo calendar days, end day inclusive, like the client);
 *   2. required products are present on the invoice lines;
 *   3. the minimum spend is met, counted ONLY over the campaign's own
 *      products, never the invoice total and never other brands of the same
 *      company. On the exclusive path this is the upload page's rule: an
 *      explicit barcode / catalog name / brand token, or a line the page
 *      flagged as the company's (isTargetCompany) that does not name a brand
 *      outside the campaign. The consuming path counts explicit lines only,
 *      like the page;
 *   4. the gift count the invoice earns (`serverUnits`). It reuses the
 *      exclusive-ladder recompute (top tier plus the remainder offer, which
 *      also applies when the campaign hands out one gift per invoice).
 *
 * The server never guesses which product an ambiguous line is: an unflagged
 * line counts only on an explicit match, and a flagged one only on the
 * page's own flag. A receipt that cannot be verified is rejected with a reason code,
 * so the caller throws before it writes anything.
 */
const { explicitMember, netLine, norm } = require("./consuming_spend_ladder");
const { exclusiveLadderUnits, grossLine, reaches, withinMax } = require("./exclusive_spend_ladder");
const { namesBrandOutsideCampaign } = require("./known_brands");

const CAIRO_TZ = "Africa/Cairo";
const HOUR_MS = 3600 * 1000;
const DAY_MS = 24 * HOUR_MS;

const REASONS = Object.freeze({
  CAMPAIGN_INACTIVE: "campaign_inactive",
  CAMPAIGN_NOT_STARTED: "campaign_not_started",
  CAMPAIGN_ENDED: "campaign_ended",
  RECEIPT_DATE_OUTSIDE: "receipt_date_outside_campaign",
  RECEIPT_LINES_MISSING: "receipt_lines_missing",
  REQUIRED_PRODUCTS_MISSING: "required_products_missing",
  MIN_SPEND_NOT_MET: "min_spend_not_met",
  NO_ELIGIBLE_GIFT: "no_eligible_gift",
});

const ELIGIBILITY_REASONS = new Set(Object.values(REASONS));

const cairoFormat = new Intl.DateTimeFormat("en-CA", {
  timeZone: CAIRO_TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

function cairoParts(ms) {
  const out = {};
  for (const part of cairoFormat.formatToParts(new Date(ms))) {
    if (part.type !== "literal") out[part.type] = Number(part.value);
  }
  return { y: out.year, m: out.month, d: out.day, h: out.hour, mi: out.minute };
}

function dayKey(y, m, d) {
  return y * 10000 + m * 100 + d;
}

function keyParts(key) {
  return { y: Math.floor(key / 10000), m: Math.floor((key % 10000) / 100), d: key % 100 };
}

function cairoDayKey(ms) {
  const p = cairoParts(ms);
  return dayKey(p.y, p.m, p.d);
}

/** UTC ms of Cairo 00:00 on calendar day (y, m, d); handles Egypt summer time. */
function cairoMidnightMs(y, m, d) {
  const base = Date.UTC(y, m - 1, d);
  for (const offsetHours of [3, 2]) {
    const candidate = base - offsetHours * HOUR_MS;
    const p = cairoParts(candidate);
    if (p.y === y && p.m === m && p.d === d && p.h === 0 && p.mi === 0) return candidate;
  }
  return base - 2 * HOUR_MS;
}

function nextDayParts(key) {
  const { y, m, d } = keyParts(key);
  const next = new Date(Date.UTC(y, m - 1, d + 1));
  return { y: next.getUTCFullYear(), m: next.getUTCMonth() + 1, d: next.getUTCDate() };
}

function toMillis(value) {
  if (value == null) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value.getTime();
  if (typeof value.toMillis === "function") {
    const ms = value.toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof value.toDate === "function") return toMillis(value.toDate());
  const seconds = value.seconds != null ? value.seconds : value._seconds;
  if (seconds != null && Number.isFinite(Number(seconds))) {
    const nanos = Number(value.nanoseconds != null ? value.nanoseconds : value._nanoseconds) || 0;
    return Number(seconds) * 1000 + Math.floor(nanos / 1e6);
  }
  return null;
}

/**
 * Campaign window in Cairo calendar days. Both days are inclusive: the
 * campaign opens at Cairo 00:00 of the start day and closes at Cairo 00:00 of
 * the day after the end day (the same cutoff as receipt_date_window.dart).
 */
function campaignWindow(event) {
  const startMs = toMillis(event && event.startDate);
  const endMs = toMillis(event && event.endDate);
  const firstKey = startMs == null ? null : cairoDayKey(startMs);
  const lastKey = endMs == null ? null : cairoDayKey(endMs);
  let opensAtMs = null;
  let cutoffMs = null;
  if (firstKey != null) {
    const f = keyParts(firstKey);
    opensAtMs = cairoMidnightMs(f.y, f.m, f.d);
  }
  if (lastKey != null) {
    const n = nextDayParts(lastKey);
    cutoffMs = cairoMidnightMs(n.y, n.m, n.d);
  }
  return { firstKey, lastKey, opensAtMs, cutoffMs };
}

/** True once Cairo time has reached the day after the campaign's end day. */
function isCampaignEnded(event, nowMs) {
  const { cutoffMs } = campaignWindow(event);
  return cutoffMs != null && nowMs >= cutoffMs;
}

function dayLabel(key) {
  const { y, m, d } = keyParts(key);
  return `${d}/${m}/${y}`;
}

const EASTERN_DIGITS = "٠١٢٣٤٥٦٧٨٩";
const PERSIAN_DIGITS = "۰۱۲۳۴۵۶۷۸۹";

function westernDigits(text) {
  return String(text == null ? "" : text)
    .replace(/[٠-٩]/g, (d) => String(EASTERN_DIGITS.indexOf(d)))
    .replace(/[۰-۹]/g, (d) => String(PERSIAN_DIGITS.indexOf(d)));
}

function validDay(y, m, d) {
  if (!(m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 2000 && y <= 2100)) return false;
  const check = new Date(Date.UTC(y, m - 1, d));
  return check.getUTCFullYear() === y && check.getUTCMonth() === m - 1 && check.getUTCDate() === d;
}

/**
 * Calendar days the printed date can mean. yyyy/mm/dd and an unambiguous
 * dd/mm/yy give one day; an ambiguous dd/mm vs mm/dd gives both and is never
 * resolved by guessing. Returns [] when no date can be read.
 */
function receiptDayCandidates(raw) {
  const text = westernDigits(raw);
  const out = [];
  const add = (y, m, d) => {
    if (validDay(y, m, d)) {
      const key = dayKey(y, m, d);
      if (!out.includes(key)) out.push(key);
    }
  };
  const ymd = /(\d{4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,2})(?!\d)/.exec(text);
  if (ymd) {
    add(Number(ymd[1]), Number(ymd[2]), Number(ymd[3]));
    return out;
  }
  const dmy = /(?<!\d)(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})(?!\d)/.exec(text);
  if (!dmy) return out;
  const a = Number(dmy[1]);
  const b = Number(dmy[2]);
  let y = Number(dmy[3]);
  if (y < 100) y += 2000;
  if (a > 12 && b <= 12) add(y, b, a);
  else if (b > 12 && a <= 12) add(y, a, b);
  else if (a <= 12 && b <= 12) {
    add(y, b, a);
    add(y, a, b);
  }
  return out;
}

/**
 * Whether the printed purchase date lies inside the campaign window.
 * "unknown" when the date cannot be read: the client lets that through too, and
 * the server does not guess. When the printed year is before the campaign
 * start, the client heals a single misread digit by trying the campaign year;
 * the same candidate is accepted here so the server never rejects a date the
 * client accepted.
 */
function purchaseDateVerdict(raw, window, nowMs) {
  if (window.firstKey == null && window.lastKey == null) return { status: "unknown" };
  const printed = String(raw == null ? "" : raw).trim();
  if (!printed) return { status: "unknown" };
  const candidates = receiptDayCandidates(printed);
  if (candidates.length === 0) return { status: "unknown" };
  const tomorrowKey = cairoDayKey(nowMs + DAY_MS);
  const all = candidates.slice();
  if (window.firstKey != null) {
    const first = keyParts(window.firstKey);
    for (const key of candidates) {
      const p = keyParts(key);
      if (key < window.firstKey && p.y !== first.y && validDay(first.y, p.m, p.d)) {
        const healed = dayKey(first.y, p.m, p.d);
        const inside = healed >= window.firstKey &&
          (window.lastKey == null || healed <= window.lastKey) && healed <= tomorrowKey;
        if (inside && !all.includes(healed)) all.push(healed);
      }
    }
  }
  const inWindow = (key) =>
    (window.firstKey == null || key >= window.firstKey) && (window.lastKey == null || key <= window.lastKey);
  if (all.some(inWindow)) return { status: "in" };
  const primary = candidates[0];
  return {
    status: "out",
    side: window.firstKey != null && primary < window.firstKey ? "before" : "after",
    printed,
  };
}

function isSpendRule(rule) {
  return !!rule && rule.conditionType !== "by_quantity" && Number(rule.minSpend) > 0;
}

function isComboRule(rule) {
  const brands = Array.isArray(rule.requiredBrands) ? rule.requiredBrands : [];
  return rule.conditionType === "combo_spend" || (rule.matchMode === "AND" && brands.length > 1);
}

function nonEmpty(list) {
  return (Array.isArray(list) ? list : []).map((v) => String(v == null ? "" : v).trim()).filter(Boolean);
}

function ruleHasScope(rule) {
  if (!rule) return false;
  if (nonEmpty(rule.selectedBarcodes).length || nonEmpty(rule.selectedProductNames).length ||
      nonEmpty(rule.requiredBrands).length) return true;
  const trigger = String(rule.triggerProduct || "").trim();
  return !!trigger && trigger.split(/\s+/).length <= 3 && norm(trigger).length >= 3;
}

/**
 * A campaign-level required product matches a line by exact catalog name,
 * the name containing it, or every word of it appearing in the line name.
 */
function requiredProductMatches(line, required) {
  const name = norm(line && line.name);
  if (!name) return false;
  const barcode = String((line && line.barcode) || "").trim();
  return required.some((entry) => {
    const text = String(entry || "").trim();
    if (!text) return false;
    if (barcode && barcode === text) return true;
    const token = norm(text);
    if (!token) return false;
    if (name === token) return true;
    if (token.length >= 3 && name.includes(token)) return true;
    const words = token.split(" ").filter((w) => w.length >= 2);
    const nameWords = new Set(name.split(" "));
    return words.length > 1 && words.every((w) => nameWords.has(w));
  });
}

function usableLines(receipt) {
  const products = receipt && receipt.extracted_products;
  if (!Array.isArray(products)) return [];
  return products.filter((p) => p && typeof p === "object");
}

function scopeOf(event) {
  const rules = Array.isArray(event && event.promotionalRules) ? event.promotionalRules.filter(Boolean) : [];
  const required = nonEmpty(event && event.requiredProducts);
  const scopedRules = rules.filter(ruleHasScope);
  const texts = required.slice();
  for (const rule of scopedRules) {
    texts.push(...nonEmpty(rule.requiredBrands), ...nonEmpty(rule.selectedProductNames));
    const trigger = String(rule.triggerProduct || "").trim();
    if (trigger) texts.push(trigger);
  }
  // Products named only by barcode: a line with another barcode is another product.
  const barcodeScoped = required.length === 0 && scopedRules.length > 0 && scopedRules.every((rule) =>
    nonEmpty(rule.selectedBarcodes).length > 0 && nonEmpty(rule.requiredBrands).length === 0);
  return { rules, required, scopedRules, texts, barcodeScoped, hasScope: scopedRules.length > 0 || required.length > 0 };
}

function memberOfScope(line, scope) {
  return scope.scopedRules.some((rule) => explicitMember(line, rule)) ||
    (scope.required.length > 0 && requiredProductMatches(line, scope.required));
}

/**
 * A line the upload page counts as the company's without an explicit match:
 * the stored company flag. It is left out when the line is identifiably
 * something else: a brand the campaign does not cover, a barcode outside a
 * barcode-only campaign, or no readable name at all. The server never
 * decides a line's product itself.
 */
function pageCompanyLine(line, scope) {
  if (line.isTargetCompany !== true || !/[\p{L}\p{N}]/u.test(norm(line.name))) return false;
  if (scope.barcodeScoped && String(line.barcode || "").trim() && !memberOfScope(line, scope)) return false;
  return !namesBrandOutsideCampaign(line.name, scope.texts);
}

/**
 * Lines a spend rule counts, as PromotionalRuleMatcher does: explicit members,
 * plus page-counted company lines for a by_spend rule unless the line
 * strictly belongs to another scoped spend rule. In the strict receipt the
 * flag already means "page-counted".
 */
function spendRuleMembers(lines, rule, scope) {
  return lines.filter((line) => {
    if (explicitMember(line, rule)) return true;
    if (line.isTargetCompany !== true || rule.conditionType !== "by_spend") return false;
    return !(ruleHasScope(rule) && scope.scopedRules.some((other) =>
      other !== rule && isSpendRule(other) && explicitMember(line, other)));
  });
}

function effectiveMin(rule) {
  return Math.max(0, Number(rule.minSpend) - (Number(rule.discountTolerance) || 0));
}

function minPositive(values) {
  const positive = values.filter((v) => Number.isFinite(v) && v > 0);
  return positive.length ? Math.min(...positive) : 0;
}

function sum(lines, lineFn) {
  return lines.reduce((total, line) => total + lineFn(line), 0);
}

/**
 * Gift units for an exclusive campaign. The ladder recompute is reused when it
 * can read the rules. Other rule shapes get an upper bound that is never below
 * what the client can compute: each scoped rule counted on its own. Returns
 * null when the rules cannot be read (combo or unscoped rule): no opinion.
 */
function exclusiveUnits(event, strictReceipt, scope) {
  const ladder = exclusiveLadderUnits(event, strictReceipt);
  if (ladder != null) return ladder;
  const lines = usableLines(strictReceipt);
  const allowMulti = event.allowMultipleChances === true;
  if (scope.rules.length > 0) {
    if (scope.rules.some((rule) => !ruleHasScope(rule) || isComboRule(rule))) return null;
    let total = 0;
    for (const rule of scope.rules) {
      const multiply = allowMulti && rule.allowMultipliers !== false;
      if (isSpendRule(rule)) {
        const spend = sum(spendRuleMembers(lines, rule, scope), grossLine);
        if (!reaches(rule, spend) || !withinMax(rule, spend)) continue;
        const min = Number(rule.minSpend);
        const tolerance = Math.max(0, Number(rule.discountTolerance) || 0);
        total += multiply ? Math.max(1, Math.floor((spend + tolerance) / min)) : 1;
      } else {
        const minQty = Math.max(1, Math.floor(Number(rule.minQuantity) || 1));
        const members = lines.filter((line) => explicitMember(line, rule));
        // Twin-pack lines count as two pieces on the client; never below that.
        const pieces = sum(members, (line) => (Number(line.quantity) > 0 ? Math.floor(Number(line.quantity)) : 1) * 2);
        if (pieces < minQty) continue;
        total += multiply ? Math.max(1, Math.floor(pieces / minQty)) : 1;
      }
    }
    return total;
  }
  const min = Number(event.minimumSpend) || 0;
  if (!(min > 0) && scope.required.length === 0) return null;
  if (!allowMulti) return 1;
  const basis = String(event.multiplierBasis || "both");
  if (basis !== "spend" || !(min > 0)) return null;
  const members = lines.filter((line) => memberOfScope(line, scope) || line.isTargetCompany === true);
  return Math.max(1, Math.floor(sum(members, grossLine) / min));
}

function fail(code, message, details) {
  return { ok: false, code, message, details: details || {} };
}

function money(value) {
  const n = Math.round(Number(value) * 100) / 100;
  return Number.isInteger(n) ? String(n) : n.toFixed(2);
}

/**
 * @param {object} args
 * @param {object} args.event     campaign document data
 * @param {object} args.receipt   stored receipt (or the receipt being created)
 * @param {number} args.nowMs     claim time
 * @param {boolean} [args.system] server-created receipt (WhatsApp): lines may be absent
 * @returns {{ok:true, serverUnits:(number|null)} | {ok:false, code:string, message:string, details:object}}
 */
function evaluateClaimEligibility({ event, receipt, nowMs, system }) {
  const ev = event || {};
  const rec = receipt || {};
  if (ev.isActive !== true) {
    return fail(REASONS.CAMPAIGN_INACTIVE, "الحملة غير نشطة حالياً، لا يمكن صرف هدية هذه الفاتورة.");
  }

  const window = campaignWindow(ev);
  const uploadedMs = toMillis(rec.timestamp) != null ? toMillis(rec.timestamp) : nowMs;
  if (window.opensAtMs != null && uploadedMs < window.opensAtMs) {
    return fail(
      REASONS.CAMPAIGN_NOT_STARTED,
      `الحملة لم تبدأ بعد، وتبدأ يوم ${dayLabel(window.firstKey)}. لا يمكن صرف هدية هذه الفاتورة.`,
      { firstDay: dayLabel(window.firstKey) },
    );
  }
  if (window.cutoffMs != null && uploadedMs >= window.cutoffMs) {
    return fail(
      REASONS.CAMPAIGN_ENDED,
      `انتهت الحملة وكان آخر يوم فيها ${dayLabel(window.lastKey)}. لا يمكن صرف هدية هذه الفاتورة.`,
      { lastDay: dayLabel(window.lastKey) },
    );
  }
  const purchase = purchaseDateVerdict(rec.receipt_date, window, nowMs);
  if (purchase.status === "out") {
    return fail(
      REASONS.RECEIPT_DATE_OUTSIDE,
      `تاريخ الشراء في الفاتورة (${purchase.printed}) خارج فترة الحملة، ولم يُصرف أي مخزون.`,
      { side: purchase.side },
    );
  }

  const consuming = ev.spendLadderMode === "consuming";
  const scope = scopeOf(ev);
  const rules = scope.rules;
  const minimumSpend = Number(ev.minimumSpend) || 0;
  const verifiable = scope.hasScope || minimumSpend > 0 || rules.some(isSpendRule);
  const lines = usableLines(rec);
  if (!verifiable) return { ok: true, serverUnits: null };
  if (lines.length === 0) {
    // The consuming planner reports its own missing_lines reason, and a
    // server-created WhatsApp receipt carries no lines to verify.
    if (consuming || system) return { ok: true, serverUnits: null };
    return fail(
      REASONS.RECEIPT_LINES_MISSING,
      "تعذر التحقق من شروط الحملة لأن أصناف الفاتورة غير محفوظة. يرجى إعادة رفع الفاتورة من المندوب، ولم يُصرف أي مخزون.",
    );
  }

  const lineSpend = consuming ? netLine : grossLine;
  // Product presence needs an explicit match; the company flag alone proves it
  // only for a campaign (or a rule) that names no brand or product at all.
  // The spend total also counts the lines the page counts (pageCompanyLine).
  const flagCounts = !scope.hasScope || rules.some((rule) => !ruleHasScope(rule));
  const isMember = (line) => memberOfScope(line, scope) || (flagCounts && line.isTargetCompany === true);
  const members = lines.filter(isMember);
  const pageCounts = (line) => !consuming && scope.hasScope && pageCompanyLine(line, scope);
  const spendMembers = lines.filter((line) => isMember(line) || pageCounts(line));

  if (scope.hasScope && members.length === 0) {
    return fail(
      REASONS.REQUIRED_PRODUCTS_MISSING,
      "الفاتورة لا تحتوي على أي من منتجات الحملة المطلوبة، ولم يُصرف أي مخزون.",
    );
  }

  const spendOnly = rules.length > 0 && rules.every(isSpendRule);
  let threshold = 0;
  if (rules.length === 0) threshold = minimumSpend;
  else if (spendOnly) threshold = minPositive([minimumSpend, ...rules.map(effectiveMin)]);
  if (threshold > 0) {
    const counted = sum(spendMembers, lineSpend);
    if (counted + 0.005 < threshold) {
      return fail(
        REASONS.MIN_SPEND_NOT_MET,
        `قيمة مشتريات منتجات الحملة في الفاتورة (${money(counted)} جنيه) أقل من الحد الأدنى المطلوب (${money(threshold)} جنيه)، ولم يُصرف أي مخزون.`,
        { required: threshold, counted },
      );
    }
  }

  if (consuming) return { ok: true, serverUnits: null };

  const strictReceipt = Object.assign({}, rec, {
    extracted_products: lines.map((line) => Object.assign({}, line, scope.hasScope ? { isTargetCompany: pageCounts(line) } : {})),
  });
  const units = exclusiveUnits(ev, strictReceipt, scope);
  if (units === 0) {
    return fail(
      REASONS.NO_ELIGIBLE_GIFT,
      "الفاتورة لا تستوفي شروط أي عرض في الحملة، لذلك لا تُصرف هدية.",
    );
  }
  return { ok: true, serverUnits: units };
}

module.exports = {
  REASONS,
  ELIGIBILITY_REASONS,
  evaluateClaimEligibility,
  campaignWindow,
  isCampaignEnded,
  cairoDayKey,
  cairoMidnightMs,
  receiptDayCandidates,
  purchaseDateVerdict,
  toMillis,
};
