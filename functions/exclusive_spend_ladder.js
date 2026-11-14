"use strict";

const { explicitMember } = require("./consuming_spend_ladder");

/**
 * Server bound for exclusive spend ladders (spendLadderMode unset/"exclusive").
 * Mirrors PromotionalRuleMatcher in lib/core/services/ai_receipt_service.dart:
 * rules sharing one barcode set form a ladder; the receipt gets the highest
 * tier it reaches (multiplied only for the top tier when Smart Multipliers is
 * ON). The spend left after that tier's threshold buys the highest strictly
 * lower tier it reaches, once, whether or not Smart Multipliers is on. With
 * it off the top tier counts once, so a ladder is at most two offers.
 *
 * Membership is a barcode/name/brand match OR the stored company flag, and the
 * line is the gross line the client uses, so the bound is never below a count
 * the client could legitimately compute. It only stops chances_earned from
 * exceeding what the stored lines can pay for.
 *
 * Returns null (no opinion) unless every rule is a non-combo spend rule with a
 * barcode set, because only then is the client grouping reproducible here.
 */
function isExclusiveSpendRule(rule) {
  return !!rule && rule.conditionType !== "by_quantity" && Number(rule.minSpend) > 0;
}

function barcodeKey(rule) {
  const codes = (Array.isArray(rule.selectedBarcodes) ? rule.selectedBarcodes : [])
    .map((code) => String(code).trim())
    .filter(Boolean);
  return codes.length ? [...new Set(codes)].sort().join(",") : "";
}

function isCombo(rule) {
  const brands = Array.isArray(rule.requiredBrands) ? rule.requiredBrands : [];
  return rule.conditionType === "combo_spend" || (rule.matchMode === "AND" && brands.length > 1);
}

function grossLine(product) {
  const rawQty = Number(product && product.quantity);
  const price = Number(product && product.price) || 0;
  const total = price * (Number.isFinite(rawQty) ? rawQty : 0);
  if (total > 0) return total;
  const qty = rawQty > 0 ? rawQty : 1;
  const unit = price > 0 ? price : (Number(product && product.originalPrice) || 0);
  return unit * qty;
}

function tolerance(rule) {
  return Number(rule.discountTolerance) || 0;
}

function reaches(rule, spend) {
  const min = Number(rule.minSpend);
  const effective = Math.max(0, min - tolerance(rule));
  return effective > 0 && spend >= effective;
}

function withinMax(rule, spend) {
  const min = Number(rule.minSpend);
  const max = rule.maxSpend == null ? null : Number(rule.maxSpend);
  if (max == null || !Number.isFinite(max) || max <= 0 || max <= min) return true;
  return spend <= max + tolerance(rule);
}

function poolUnits(tiers, spend, allowMultiple) {
  const ladder = tiers.length > 1;
  for (let i = 0; i < tiers.length; i++) {
    const rule = tiers[i];
    const top = i === 0;
    if (!reaches(rule, spend) || (!top && !withinMax(rule, spend))) continue;
    const min = Number(rule.minSpend);
    let count = 1;
    if (top && allowMultiple) {
      count = Math.max(1, Math.floor((spend + Math.max(0, tolerance(rule))) / min));
    }
    if (!ladder) return count;
    const remainder = Math.max(0, spend - min * count);
    const lower = tiers.slice(i + 1).find((r) => Number(r.minSpend) < min && reaches(r, remainder));
    return count + (lower ? 1 : 0);
  }
  return 0;
}

function exclusiveLadderUnits(event, receipt) {
  if (!event || event.spendLadderMode === "consuming") return null;
  const rules = Array.isArray(event.promotionalRules) ? event.promotionalRules : [];
  if (!rules.length) return null;
  if (!rules.every((rule) => isExclusiveSpendRule(rule) && !isCombo(rule) && barcodeKey(rule))) return null;
  const products = receipt && receipt.extracted_products;
  if (!Array.isArray(products) || products.length === 0) return null;

  const pools = new Map();
  for (const rule of rules) {
    const key = barcodeKey(rule);
    if (!pools.has(key)) pools.set(key, []);
    pools.get(key).push(rule);
  }
  const allowMultiple = event.allowMultipleChances === true;
  const companyTotal = Number(receipt.target_company_total);
  let units = 0;
  for (const tiers of pools.values()) {
    tiers.sort((a, b) => Number(b.minSpend) - Number(a.minSpend));
    let spend = 0;
    for (const product of products) {
      if (!product || typeof product !== "object") continue;
      const member = product.isTargetCompany === true || tiers.some((rule) => explicitMember(product, rule));
      if (member) spend += grossLine(product);
    }
    if (Number.isFinite(companyTotal) && companyTotal > 0 && spend > companyTotal) spend = companyTotal;
    units += poolUnits(tiers, spend, allowMultiple);
  }
  return units;
}

module.exports = { exclusiveLadderUnits, poolUnits };
