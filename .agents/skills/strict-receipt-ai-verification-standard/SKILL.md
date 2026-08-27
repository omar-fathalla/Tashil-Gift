---
name: strict-receipt-ai-verification-standard
description: Mandatory standard for zero-hallucination receipt extraction, strict OCR verification, blurry receipt rejection, deterministic zero temperature AI logic, and zero-fallback prize qualification governance in Flutter & Firebase.
---

# Strict Receipt AI Verification & Zero-Hallucination Standard

## 🎯 Core Principles

1. **Zero Hallucination & Exact Line Verification**:
   - The AI vision model (Gemini 3.7 Flash) must operate at **`temperature: 0.0`** (deterministic mode).
   - The model must strictly extract only what is visibly printed on the receipt.
   - If a product line item, name, barcode, or quantity is blurry, truncated, folded, or unreadable, the system MUST NOT guess or assume the product identity.
   - It MUST reject the receipt with `isValid = false` and output the helpful Arabic message:
     `"صورة الفاتورة غير واضحة أو اسم المنتج غير مقروء بدقة، برجاء إعادة تصوير الفاتورة بوضوح مع إظهار سطر المنتج والكمية"`.

2. **Strict Promotional Rule Qualification (No Default Fallback Prize)**:
   - When a campaign defines promotional rules (`event.promotionalRules.isNotEmpty`):
     - A gift/voucher can **ONLY** be awarded if one or more promotional rules are genuinely matched (`matchedRulesList.isNotEmpty`).
     - If the customer bought an item that belongs to the company but did not meet the rule requirement (e.g. bought 1 bottle of Tresemme 400ml when the rule requires 2 bottles), `matchedRulesList` is EMPTY.
     - The system MUST NEVER fall back to awarding `prizeNames.first` (e.g. Clear 90ml).
     - The receipt MUST be classified as non-qualifying, and the customer/promoter must be shown the detailed unfulfilled condition dialog explaining the exact discrepancy (e.g. `تم شراء 1 قطعة تريزيمي 400 مل، والمطلوب 2 قطعة للحصول على هدية تريزيمي 250 مل`).

3. **Multi-Offer Basket & Family Grouping Invariant**:
   - Cross-product bundling strictly separates product families (`spray_family`, `rollon_family`, `clear_family`, `tresemme_family`, `sunsilk_family`, `dove_family`).
   - A product in one family can NEVER trigger or satisfy a rule belonging to another family.

4. **Trilingual Diagnostic Messaging**:
   - Arabic (`ar`): `"الفاتورة غير مستوفية لشروط العرض الترويجي (الكمية المشتراة غير كافية أو المنتجات غير مشمولة)"`
   - English (`en`): `"Receipt does not meet promotional conditions (insufficient quantity or unincluded products)"`
   - Hindi (`hi`): `"रसीद प्रचार शर्तों को पूरा नहीं करती है (अपर्याप्त मात्रा या गैर-शामिल उत्पाद)"`
