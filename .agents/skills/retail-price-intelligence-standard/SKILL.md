---
name: retail-price-intelligence-standard
description: Mandatory standard for AI receipt product extraction, unit economics calculation, multi-quantity discount healing, enterprise retail chain consolidation, and cross-chain price intelligence in Flutter & Firebase.
---

# Retail Price Intelligence & Unit Economics Standard

## 📌 Overview & Scope
This standard governs all AI-driven receipt extractions, product pricing algorithms, receipt data post-processing, database storage, and cross-chain retail price comparison across the Tashil Gift / Al-Mraay platform.

---

## 🛑 MANDATORY RULES & EQUATIONS

### 1. The Single Unit Economics Rule (قاعدة سعر بيع القطعة الواحدة)
When a customer purchases a product with `quantity >= 2` (or quantity = 1 with line discount), POS receipts typically display the **gross line total**, **line discount**, and **net line total payable**.
- **`price` (Net Unit Price)**: MUST strictly be the net selling price per **SINGLE** piece (`netLineTotal / quantity`). NEVER store or display the line total as the unit price.
- **`originalPrice` (Gross Unit Price)**: MUST strictly be the regular shelf price before discount per **SINGLE** piece (`grossLineTotal / quantity`).
- **`discountAmount` (Unit Discount)**: MUST strictly be the monetary discount for **ONE** piece (`totalLineDiscount / quantity`).
- **`totalPrice` (Line Total)**: `price * quantity`.

#### Reference Egyptian FMCG POS Example:
> **Clear Shampoo 360ml**:
> - Printed on Receipt: Unit Price `115.00`, Qty `2`, Gross Total `230.00`, Discount `-32.00`, Net Paid `198.00`.
> - **Extracted Model Representation**:
>   - `quantity`: `2`
>   - `originalPrice`: `115.00 EGP` (230.00 / 2)
>   - `discountAmount`: `16.00 EGP` (32.00 / 2)
>   - `price`: `99.00 EGP` (198.00 / 2)
>   - `totalPrice`: `198.00 EGP` (99.00 * 2)

---

### 2. Auto-Healing & Resilience Engine (المعالجة والتصحيح التلقائي)
In `ExtractedProductItem.fromJson` and all data ingestion pipelines, if the AI or receipt payload contains line-level totals where `quantity > 1`:
```dart
if (quantity > 1) {
  // Case A: Both gross and net line totals were captured
  if (rawOriginalPrice != null && rawOriginalPrice > 0) {
    if ((rawPrice + rawDiscount - rawOriginalPrice).abs() < 1.5 && rawPrice > 50) {
      rawPrice = rawPrice / quantity;
      rawOriginalPrice = rawOriginalPrice / quantity;
      if (rawDiscount > 0) rawDiscount = rawDiscount / quantity;
    } else if (rawPrice >= rawOriginalPrice * 1.5) {
      rawPrice = rawPrice / quantity;
    } else if (rawOriginalPrice >= 1.8 * rawPrice && rawOriginalPrice > 50) {
      rawOriginalPrice = rawOriginalPrice / quantity;
    }
  } else if (rawTotalLine != null && rawTotalLine > 0 && (rawPrice == rawTotalLine || rawPrice >= rawTotalLine * 0.95)) {
    rawPrice = rawPrice / quantity;
  }

  if (rawDiscount >= rawPrice && rawDiscount > 0) {
    rawDiscount = rawDiscount / quantity;
  }
}
```

---

### 3. Enterprise Retail Chain Consolidation (توحيد السلاسل على مستوى المؤسسة)
Standard FMCG shelf prices do not vary across branches within the same supermarket chain. Differences seen across branches in legacy systems were artifacts of quantity multiplication math errors.
- **Rule**: All branch names (e.g., `سموحة`, `الهانوفيل`, `فرع 419`, `عجمي ستار`) must resolve to their canonical parent **Enterprise Retail Chain**.
- Comparison matrices, KPI cards, and price intelligence screens must strictly compare **Chain vs Chain** (Enterprise Level).
- **Canonical Chain Resolver (`normalizeRetailChain`)**:
  - `أسواق فتح الله`: `فتح الله`, `فتح الله للجملة`, `اسواق فتح الله`, `fathalla`, `fathalla market`
  - `جملة ماركت`: `جملة ماركت`, `اسواق جملة ماركت`, `gomla`, `gomla market`
  - `بيت الجملة`: `بيت الجملة`, `اسواق بيت الجملة`, `beit el gomla`
  - `كارفور`: `كارفور`, `carrefour`
  - `خير زمان`: `خير زمان`, `kheir zaman`
  - `سبينس`: `سبينس`, `spinneys`
  - `مترو ماركت`: `مترو`, `metro`
  - `كازيون`: `كازيون`, `kazyon`
  - `بيم`: `بيم`, `bim`
  - `سعودي ماركت`: `سعودي`, `seoudi`
  - `لولو هايبرماركت`: `لولو`, `lulu`
  - `أولاد رجب`: `رجب`, `ragab`
  - `المحلاوي`: `محلاوي`, `mahallawy`

---

### 4. Cross-Chain Intelligence Metrics (مؤشرات المقارنة والذكاء التجاري)
For any product SKU:
- `minPrice`: `latestPricesByChain.values.reduce(min)`.
- `cheapestChain`: The enterprise chain matching `minPrice`.
- `maxPrice`: `latestPricesByChain.values.reduce(max)`.
- `mostExpensiveChain`: The enterprise chain matching `maxPrice`.
- `priceVariancePercent`: `((maxPrice - minPrice) / minPrice) * 100`.
- `distinctPriceChangeEvents`: Chronological list of price transition events per chain (eliminating repetitive same-price receipt scans).

---

### 5. UI Presentation Guidelines (Material Design 3)
1. **Chain Cards Matrix (`Enterprise Chains Price Cards`)**:
   - Prominently display canonical selling price per unit.
   - Cross out the original price if discounted (`TextDecoration.lineThrough`).
   - Highlight the lowest market price with a gold star badge (`🌟 الأرخص سعراً في السوق`).
   - Show observation scan count and units sold.
2. **Price Evolution Timeline (`سجل تغيرات وتعديلات الأسعار`)**:
   - Group by distinct historical price changes per chain over time.
3. **Audit Log (`Raw Invoices`)**:
   - Provide receipt number, branch name, and image preview dialog.
