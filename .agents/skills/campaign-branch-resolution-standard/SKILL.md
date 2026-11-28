---
name: campaign-branch-resolution-standard
description: Mandatory standard for canonical campaign branch resolution, geographic parenthetical striping, zero-collision branch deduplication, strict canonical filter equality, isolated KPI metrics, and single campaign branch governance across Flutter & Firebase.
---

# Campaign Branch Resolution & Canonical Governance Standard

## 1. Core Architectural Principle: Strict Canonical Scoping

1. **Zero Rogue Branch Invariant**:
   - In all screens (`InvoicesLogScreen`, `CampaignReportsScreen`, `CompanyPrizesStockReportScreen`), branch dropdown filters, selection chips, and analytics tables MUST strictly derive their available branch lists (`availableBranches`) from the **official canonical branches configured in the campaign** (`event.branchNames`).
   - **NEVER** collect or dump raw `branch_detected` strings from receipts into the UI filters or available branch lists.

2. **Scoped Campaign Hierarchy**:
   - When a specific campaign is selected (`selectedCampaignId != 'all'`), the available branches must be **strictly and exclusively** the branch list of that campaign (`eventsMap[campaignId].branchNames`, e.g. the exact 12 branches).
   - When viewing all campaigns under a company, the available branches must be the deduplicated union of `event.branchNames` across the company's campaigns.
   - The dropdown button and header must display the clean count of official branches (e.g. `كافة الفروع (12)`).

---

## 2. Geographic Parenthetical Striping & Anti-Collision Rule

### ⚠️ The City False-Positive Collision Trap:
- In supermarket retail campaigns, multiple distinct branches frequently share the same parent governorate or city suffix in parentheses:
  - Cairo: `التجمع (Tagmoo) (القاهرة)` vs `عمارات العبور - صلاح سالم (القاهرة)`
  - Alexandria: `فرع جاردينيا (الإسكندرية)` vs `فرع سموحة (الإسكندرية)` vs `جناكليس (الإسكندرية)` vs `المنتزه (الإسكندرية)`
- **CRITICAL RULE**: City and governorate names in parentheses MUST NEVER be used as matching tokens. If a fuzzy matcher compares `(القاهرة)` with `(القاهرة)`, all Cairo branches mistakenly merge into a false single group (e.g. 55 receipts instead of 17).
- **Mandatory Striping**: Always strip governorates `\((القاهرة|الإسكندرية|الاسكندرية|الجيزة|الغربية|الدقهلية|المنوفية|الشرقية|البحيرة|كفر الشيخ|دمياط|بورسعيد|السويس|الإسماعيلية|الفيوم|بني سويف|المنيا|أسيوط|سوهاج|قنا|الأقصر|أسوان|مطروح|cairo|alexandria|giza)\)` prior to any root or token comparison.

---

## 3. Multi-Tier Intelligent Branch Normalization Engine

All incoming receipts and invoices undergo automatic multi-tier normalization (`_normalizeBranchName` & `_cleanBranchForComparison`) to map any OCR variation, store code, or noisy string into its canonical counterpart:

```
Raw OCR Receipt String ──► Clean & Strip Cities ──► Precision Area Routing ──► Canonical Campaign Branch
(e.g. "Store: 418")      (Strip (القاهرة)/(الإسكندرية)) (Gardenia, Agamy, Tagmoo) ("المنتزه")
```

### Resolution Pipeline:
1. **Direct Case-Insensitive Match**:
   - Exact string comparison after trimming whitespace.
2. **Phonetic & Geographic Cleaning (`_cleanBranchForComparison`)**:
   - Strip Arabic diacritics (`[\u064B-\u065F\u0670]`).
   - Unify Alef variations (`[أإآ]` ➔ `ا`).
   - Unify Taa Marbouta / Haa (`ة` ➔ `ه`) and Yaa / Alef Maqsura (`ى` ➔ `ي`).
   - Strip parenthetical city/governorate suffixes.
   - Strip punctuation, brackets, parentheses (`()`, `[]`, `{}`, `-`, `_`, `/`).
   - Remove prefixes and noise words (`\b(فرع|سلسلة|store|branch|مفرع|pos|كود|محافظة|مدينة)\b`).
3. **Precision Area Routing (Anti-Ambiguity)**:
   - **Gardenia**: `"جاردينيا"` / `"gardenia"` ➔ `"فرع جاردينيا (الإسكندرية)"`
   - **Agamy**: `"عجمي"` / `"agamy"` ➔ `"فرع عجمي ستار (الإسكندرية)"`
   - **Smouha**: `"سموح"` / `"smouha"` ➔ `"فرع سموحة (الإسكندرية)"`
   - **Mahalla**: `"محله"` / `"mahalla"` ➔ `"فرع المحلة الكبرى (الغربية)"`
   - **Shebin**: `"شبين"` / `"شين"` / `"shebin"` ➔ `"شبين الكوم (شبين الكوم)"`
   - **Tagmoo / Fifth Settlement / Park Mall**: `"تجمع"` / `"tagmoo"` / `"park mall"` ➔ `"التجمع (Tagmoo) (القاهرة)"`
   - **October**: `"اكتوبر"` / `"october"` / `"سادس"` ➔ `"أكتوبر (October) (السادس من أكتوبر)"`
   - **Mansoura**: `"منصور"` / `"mansoura"` ➔ `"المنصورة (المنصورة)"`
   - **Obour / Salah Salem**: `"صلاح سالم"` / `"عبور"` / `"obour"` ➔ `"عمارات العبور - صلاح سالم (القاهرة)"`
   - **Montazah & Store Codes**: `"418"` / `"منتزه"` / `"montazah"` ➔ `"المنتزه (الإسكندرية)"`
   - **Miami**: `"ميامي"` / `"miami"` ➔ `"ميامي (الإسكندرية)"`
   - **Janaklis**: `"جناكليس"` / `"janaklis"` ➔ `"جناكليس (الإسكندرية)"`
4. **Store Code & POS Number Resolution**:
   - Extract numeric identifiers (`\b\d+\b`) and match with branch store IDs (e.g. `418` ➔ `"المنتزه"`).
5. **Fallback Containment Matching**:
   - Substring match on sanitized strings without city tokens.

---

## 4. Strict Canonical Filter Equality & Dynamic KPI Isolation

1. **Strict Equality in Filter Execution**:
   - In `filteredInvoices`, when `_selectedBranch != 'all'`:
     ```dart
     if (inv['canonical_branch'] != _selectedBranch) return false;
     ```
   - **NEVER** re-apply loose token or fuzzy substring matching at the filter stage. Because every invoice has already been deterministically normalized to its canonical branch at load time, filtering must strictly be an exact string match.

2. **100% Dynamic KPI Isolation**:
   - When a specific branch is selected:
     - **Invoice Count (`totalInvoicesCount`)**: Must strictly match the badge count next to that branch name in the popup menu.
     - **Promotional Sales (`totalPromoSales`)**: Must strictly sum the promo sales of invoices belonging to that branch alone.
     - **Extracted Items (`totalExtractedItems`)**: Must strictly sum items extracted from receipts of that branch alone.
     - **AI Processing Speed (`avgAiSpeed`)**: Must strictly calculate the average speed of that branch alone.

---

## 5. UI Cleanliness & Invoice Cards Standard

1. **Clean Card Headers**:
   - In `_buildInvoiceCard`, the store/branch pill badge must display the clean `canonical_branch` (e.g. `أسواق فتح الله - المنتزه`).
   - If the raw branch string contains additional diagnostic info, provide it via an M3 `Tooltip` instead of polluting the visible badge text.
2. **Badge Counts & Total Alignment**:
   - In the branch dropdown menu, each popup item displays a live counter badge:
     ```dart
     final count = allInvoices.where((inv) => inv['canonical_branch'] == b).length;
     ```
   - The sum of all branch badge counts must exactly equal the total number of campaign invoices (e.g. 73 + 99 + 179 + 35 + 0 + 17 + 2 + 29 + 38 + 59 + 10 + 37 = 578 invoices).
