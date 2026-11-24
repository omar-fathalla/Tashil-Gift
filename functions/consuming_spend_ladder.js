"use strict";

function norm(value) {
  return String(value || "")
    .replace(/[أإآ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/[^\u0600-\u06FFa-zA-Z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function netLine(product) {
  const qty = Number(product.quantity) > 0 ? Number(product.quantity) : 1;
  const price = Number(product.price) || 0;
  const line = price > 0 ? price * qty : 0;
  const discount = Number(product.discountAmount) || 0;
  const original = product.originalPrice == null ? null : Number(product.originalPrice);
  if (discount <= 0) return line;
  if (original != null && original > price && Math.abs(price + discount - original) < 1.5) return line;
  if (discount >= price && discount < line) return Math.max(0, line - discount);
  if (discount < price) return Math.max(0, (price - discount) * qty);
  return line;
}

function explicitMember(product, rule) {
  const barcode = String(product.barcode || "").trim();
  const barcodes = Array.isArray(rule.selectedBarcodes) ? rule.selectedBarcodes : [];
  if (barcode && barcodes.some((b) => String(b).trim() === barcode)) return true;
  if (barcode.length >= 10 && barcodes.some((b) => {
    const code = String(b).trim();
    return code.startsWith(barcode) || barcode.startsWith(code);
  })) return true;
  const name = norm(product.name);
  if (!name) return false;
  const names = Array.isArray(rule.selectedProductNames) ? rule.selectedProductNames : [];
  if (names.some((sel) => norm(sel) === name && norm(sel))) return true;
  const brands = []
    .concat(rule.requiredBrands || [])
    .concat(String(rule.triggerProduct || "").trim().split(/\s+/).length <= 3 ? [rule.triggerProduct] : []);
  return brands.some((brand) => {
    const token = norm(brand);
    return token.length >= 3 && name.includes(token);
  });
}

function isSpend(rule) {
  return rule && rule.conditionType !== "by_quantity" && Number(rule.minSpend) > 0;
}

function optionValue(option) {
  if (!option) return 0;
  if (option.kind === "voucher") return Number(option.voucherAmount || option.unitValue) || 0;
  return option.giftType === "voucher" ? Number(option.unitValue) || 0 : 0;
}

function poolKey(rule) {
  const codes = (Array.isArray(rule.selectedBarcodes) ? rule.selectedBarcodes : [])
    .map((code) => String(code).trim())
    .filter(Boolean)
    .sort();
  if (codes.length) return `barcodes:${codes.join(",")}`;
  const brands = (Array.isArray(rule.requiredBrands) ? rule.requiredBrands : []).map(norm).filter(Boolean).sort();
  if (brands.length) return `brands:${brands.join("|")}`;
  return `trigger:${norm(rule.triggerProduct || rule.id)}`;
}

function giftLists(rule) {
  const names = [];
  const giftIds = [];
  const unitValues = [];
  const options = Array.isArray(rule.rewardOptions) ? rule.rewardOptions : [];
  if (options.length) {
    for (const option of options) {
      const label = String(option.label || option.giftName || "").trim();
      names.push(label || `قسيمة شراء ${optionValue(option)} جنيه`);
      giftIds.push(String(option.giftId || ""));
      unitValues.push(optionValue(option));
    }
  } else {
    const gifts = Array.isArray(rule.linkedGifts) ? rule.linkedGifts : [];
    for (const gift of gifts) {
      names.push(String(gift.giftName || ""));
      giftIds.push(String(gift.giftId || ""));
      unitValues.push(Number(gift.unitValue) || 0);
    }
  }
  return { names, giftIds, unitValues };
}

function consumeGroup(tiers, products, allowMultiple) {
  const remaining = new Map();
  for (const product of products) {
    if (!tiers.some((rule) => explicitMember(product, rule))) continue;
    remaining.set(product, (remaining.get(product) || 0) + netLine(product));
  }
  const rounds = [];
  let pool = 0;
  for (const value of remaining.values()) pool += value;
  for (const rule of tiers) {
    const minimum = Number(rule.minSpend) || 0;
    if (minimum <= 0) continue;
    let eligible = 0;
    for (const [product, left] of remaining) {
      if (left > 0 && explicitMember(product, rule)) eligible += left;
    }
    const tolerance = Number(rule.discountTolerance) || 0;
    let count = allowMultiple ? Math.floor(eligible / minimum) : 0;
    if (!allowMultiple && eligible + tolerance >= minimum) count = 1;
    else if (allowMultiple && count < 1 && tolerance > 0 && eligible + tolerance >= minimum) count = 1;
    if (count < 1) continue;
    let toConsume = minimum * count;
    for (const [product, left] of remaining) {
      if (toConsume <= 0) break;
      if (!explicitMember(product, rule) || left <= 0) continue;
      const take = Math.min(left, toConsume);
      remaining.set(product, left - take);
      toConsume -= take;
    }
    const lists = giftLists(rule);
    for (let i = 0; i < count; i++) {
      rounds.push({
        ruleId: String(rule.id || ""),
        tierMinSpend: minimum,
        prizeNames: lists.names,
        giftIds: lists.giftIds,
        unitValues: lists.unitValues,
      });
    }
    if (!allowMultiple) break;
  }
  return { pool, rounds };
}

function roundsFromRules(rules, products, allowMultiple) {
  const groups = new Map();
  for (const rule of rules.filter(isSpend)) {
    const key = poolKey(rule);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(rule);
  }
  const rounds = [];
  let pool = 0;
  for (const tiers of groups.values()) {
    tiers.sort((a, b) => Number(b.minSpend) - Number(a.minSpend));
    const consumed = consumeGroup(tiers, products, allowMultiple);
    pool += consumed.pool;
    rounds.push(...consumed.rounds);
  }
  rounds.sort((a, b) => b.tierMinSpend - a.tierMinSpend);
  return { pool, rounds };
}

function applyCap(rounds, maxChances) {
  const cap = Number(maxChances);
  if (!Number.isFinite(cap) || cap <= 0) return rounds;
  return rounds.slice(0, cap);
}

function canonicalIds(round) {
  return (round.giftIds || []).map((id) => String(id || "").trim()).filter(Boolean);
}

// Authorization is the gift id on this round. The caller's unit value, label,
// and claimed_gifts array are not consulted.
function canonicalGift(round, claim) {
  const ids = canonicalIds(round);
  const explicitId = String(claim.giftId || "").trim();
  const identifier = String(claim.prizeIdentifier || "").trim();
  const id = explicitId || (ids.includes(identifier) ? identifier : "");
  if (!id || !ids.includes(id)) return null;
  const index = round.giftIds.findIndex((giftId) => String(giftId || "").trim() === id);
  return {
    giftId: id,
    giftName: String(round.prizeNames[index] || ""),
    quantity: 1,
    unitValue: Number(round.unitValues[index]) || 0,
    ruleId: round.ruleId,
    tierMinSpend: round.tierMinSpend,
    isVoucher: (Number(round.unitValues[index]) || 0) > 0,
    branchId: claim.branchId || "",
  };
}

function roundAllows(round, claim) {
  return canonicalGift(round, claim) != null;
}

function claimedEntryUnits(gift) {
  if (!gift || typeof gift !== "object") return 1;
  const raw = gift.quantity;
  if (raw == null) return 1;
  if (typeof raw === "string" && raw.trim() === "") return 1;
  const count = Number(raw);
  if (!Number.isFinite(count) || count <= 0) return 1;
  const units = Math.floor(count);
  return units > 0 ? units : 1;
}

function keptLedgerEntry(gift) {
  return {
    giftId: String((gift && gift.giftId) || ""),
    giftName: String((gift && gift.giftName) || ""),
    quantity: claimedEntryUnits(gift),
    unitValue: Number(gift && gift.unitValue) || 0,
    ruleId: String((gift && gift.ruleId) || ""),
    tierMinSpend: Number(gift && gift.tierMinSpend) || 0,
    isVoucher: !!(gift && gift.isVoucher),
  };
}

function hasSpendRule(event) {
  const rules = Array.isArray(event && event.promotionalRules) ? event.promotionalRules : [];
  return rules.some(isSpend);
}

function claimSlotOf(decrement) {
  if (!decrement || decrement.claimSlot == null || decrement.claimSlot === "") return null;
  const slot = Number(decrement.claimSlot);
  if (!Number.isInteger(slot) || slot < 0) return null;
  return slot;
}

function unitGiftIds(entries) {
  const ids = [];
  for (const gift of entries) {
    const units = claimedEntryUnits(gift);
    for (let i = 0; i < units; i++) ids.push(String(gift.giftId || ""));
  }
  return ids;
}

// claimSlot is the ledger unit index this action is for. The same gift id may
// be legal on the next round, so a retry is recognized by the slot, not by
// the gift id. A request without a slot cannot tell a retry from the next
// round and is refused. Exclusive claims never reach this function.
function planConsumingClaim(event, receipt, decrements) {
  if (!event || event.spendLadderMode !== "consuming") return { skip: true };
  if (!Array.isArray(decrements) || decrements.length === 0) return { skip: true };
  if (!hasSpendRule(event)) return { reason: "missing_spend_rules" };
  const products = receipt && receipt.extracted_products;
  if (!Array.isArray(products) || products.length === 0) return { reason: "missing_lines" };
  const allow = event.allowMultipleChances === true;
  const computed = roundsFromRules(event.promotionalRules || [], products, allow);
  const rounds = applyCap(computed.rounds, allow ? event.maxChancesPerReceipt : 1);
  const existing = (Array.isArray(receipt.claimed_gifts) ? receipt.claimed_gifts : []).map(keptLedgerEntry);
  const occupiedIds = unitGiftIds(existing);
  const occupied = occupiedIds.length;
  const requests = [];
  for (const decrement of decrements) {
    const start = claimSlotOf(decrement);
    const count = Math.floor(Number(decrement.count || decrement.quantity || 1));
    if (start == null || !Number.isInteger(count) || count < 1) return { reason: "round_unbound" };
    for (let n = 0; n < count; n++) requests.push({ slot: start + n, decrement });
  }
  if (requests.length === 0) return { reason: "round_unbound" };
  for (let i = 1; i < requests.length; i++) {
    if (requests[i].slot !== requests[0].slot + i) return { reason: "round_unbound" };
  }
  const start = requests[0].slot;
  const end = start + requests.length;
  const played = receipt && receipt.game_played === true;
  const remaining = Number(receipt && receipt.remaining_chances != null ? receipt.remaining_chances : 0);
  if (played && remaining <= 0 && occupied >= rounds.length && start >= rounds.length) {
    return { reason: "already_claimed" };
  }
  if (occupied === end) {
    for (let i = 0; i < requests.length; i++) {
      const round = rounds[start + i];
      if (!round) return { reason: "extra_quantity" };
      const gift = canonicalGift(round, requests[i].decrement);
      if (!gift) return { reason: "tier_mismatch" };
      if (!occupiedIds[start + i] || occupiedIds[start + i] !== gift.giftId) {
        return { reason: "round_conflict" };
      }
    }
    return {
      reason: null,
      idempotent: true,
      claimed_gifts: existing,
      prizes_won: existing.map((gift) => gift.giftName).filter(Boolean),
      remaining_chances: Math.max(0, rounds.length - occupied),
      decrements: [],
    };
  }
  if (occupied > end) return { reason: "stale_round" };
  if (occupied > start) return { reason: "round_conflict" };
  if (occupied < start) return { reason: "round_gap" };
  const added = [];
  const stockDecrements = [];
  for (let i = 0; i < requests.length; i++) {
    const round = rounds[start + i];
    if (!round) return { reason: "extra_quantity" };
    const gift = canonicalGift(round, requests[i].decrement);
    if (!gift) return { reason: "tier_mismatch" };
    added.push(gift);
    stockDecrements.push({
      prizeIdentifier: gift.giftId,
      count: 1,
      unitValue: gift.unitValue,
      isVoucher: gift.isVoucher,
      branchId: requests[i].decrement.branchId || "",
      gameType: requests[i].decrement.gameType || "chooseGift",
      // The tier option's giftId is authoritative for the stock row too.
      giftName: gift.giftName,
      ladder: true,
    });
  }
  const claimed = existing.concat(added);
  return {
    reason: null,
    claimed_gifts: claimed,
    prizes_won: claimed.map((gift) => gift.giftName).filter(Boolean),
    remaining_chances: Math.max(0, rounds.length - end),
    decrements: stockDecrements,
  };
}

function verifyConsumingDecrements(event, receipt, decrements) {
  const plan = planConsumingClaim(event, receipt, decrements);
  if (!plan || plan.skip) return null;
  return plan.reason || null;
}

module.exports = {
  norm,
  netLine,
  explicitMember,
  roundsFromRules,
  applyCap,
  verifyConsumingDecrements,
  planConsumingClaim,
  claimedEntryUnits,
};
