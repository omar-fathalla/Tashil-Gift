---
name: promotional-rules-single-resolution-standard
description: Mandatory architectural standard for promotional rules matching, multi-offer bundling, absolute single-resolution gift allocation, prevention of double-multiplication bugs, POS Arabic phonetic normalization, and automatic AI campaign rule synthesis in Tashil Gift.
---

# Promotional Rules & Multi-Gift Single-Resolution Standard

## 1. Core Architectural Principle: Single Resolution & Absolute Quantities

When an invoice or receipt is validated against campaign promotional rules:
1. **Self-Contained & Absolute Multiplied Quantities**:
   - `PromotionalRuleMatcher.matchAllWithMultipliers()` computes all matched rule items and scales `LinkedGiftAllocation.quantity` according to the exact number of qualifying trigger products in the customer's receipt.
   - For example, if the rule is "1 Clear 360ml ➔ 1 Clear 90ml gift", and the customer bought 3 bottles of Clear 360ml, `multipliedLinkedGifts` contains `[LinkedGiftAllocation(giftName: 'كلير 90 مل هدية', quantity: 3)]`.
2. **Zero Double-Multiplication Invariant**:
   - Presentation layers (`DirectGiftClaimScreen`, `WinnerCelebrationDialog`), claim transaction records (`receipts_transactions.claimed_gifts`), and inventory decrement operations (`CompanyGiftsService.decrementCampaignPrize`) MUST treat `linkedGifts` allocations as **absolute, fully-resolved quantities**.
   - **NEVER** re-multiply `giftAlloc.quantity` by `effectiveQuantity` or `totalChances` when `linkedGifts.isNotEmpty`.
   - The general basket chances multiplier (`widget.quantity` / `totalChances`) applies **ONLY** to legacy single prizes when `linkedGifts.isEmpty`.

---

## 2. Multi-Offer Composite Bundling Architecture

When a customer's receipt satisfies multiple distinct rules simultaneously (e.g. 1 Axe Spray ➔ 50 EGP Voucher, and 2 Rexona Roll-ons ➔ 50 EGP Voucher, and 3 Clear Shampoo ➔ 3 Clear 90ml):
1. **Rule Grouping**:
   - Tiered rules of the same product family (e.g. 1 Spray vs 2 Sprays) select the highest qualified tier.
   - Rules of different product families accumulate concurrently into `CompositePromotionalBundle`.
2. **Composite UI Presentation**:
   - `isMultiBundle` is activated when `cleanPrizeName.contains('+')` or when `linkedGifts` contains multiple distinct allocations.
   - The UI presents:
     - **Multi-Bundle Header Badge**: `سلة هدايا مجمعة (X هدايا مستحقة)`
     - **Combined Voucher Amount Banner**: `إجمالي قيمة الفواتشرات: X ج.م`
     - **Itemized Gift Cards**: Clean, individual cards for each gift with its exact quantity badge (e.g. `3 ×`, `2 ×`, `1 ×`).
     - **Accurate Stock Decrement**: Each SKU in the company/branch inventory is decremented by its exact allocated quantity.

---

## 3. POS Arabic Phonetic Normalization & Fuzzy Matching Standard

All receipt scanning, OCR extraction, and rule evaluation must strictly apply POS Arabic phonetic normalization before matching:
- **Long Vowel Normalization & POS Compression**:
  - `روول` / `رووول` ⟷ `رول` / `رول اون`
  - `اسبراى` / `اسبرى` / `اسبري` / `بخاخ` ⟷ `اسبراي`
  - `صنسلك` ⟷ `صنسيلك`
  - `تريزمي` / `تريزميه` ⟷ `تريزيمي`
  - `ركسونا` ⟷ `ريكسونا`
  - `دوفه` ⟷ `دوف`
- **Fuzzy Token Matching**:
  - Compare normalized tokens using Levenshtein edit distance ($\le 1$ edit distance for short words, $\le 2$ for longer words) to ensure 100% match rate even with printer noise, missing dots, or slight OCR variance.

---

## 4. Automatic AI Campaign Assistant Configuration

When creating new campaigns via `CampaignAiAssistantService`:
1. The AI assistant must automatically decompose any monetary voucher rewards into discrete stock voucher denominations (e.g. 125 EGP ➔ 2x 50 EGP + 1x 25 EGP).
2. The AI assistant must link physical gifts with `quantity: 1` allocations.
3. Every new campaign generated or updated must adhere to `PromotionalRuleItem` with `linkedGifts` populated, ensuring that future campaigns immediately execute with zero manual reconfiguration.
