# GEMINI.md — Tashil Gift Workspace Guidelines

## 🛑 MANDATORY RULES

### 1. Deployment & Git Push Permission Rule
- **NEVER autonomously push to GitHub or deploy to Firebase**:
  - The agent MUST NEVER execute `git push` or `firebase deploy` (`npx -y firebase-tools@latest deploy ...`) automatically or as an unprompted final step of a task.
  - Verification with `flutter analyze` and `flutter test` can and should be done locally.
  - Remote publishing / deployments to Firebase or pushing to GitHub are **STRICTLY FORBIDDEN** unless the user gives an explicit affirmative instruction in the active chat turn (e.g., *"ارفع على جيت هب"*, *"اعمل deploy"*, *"ارفع للفايربيز"*, *"انشر التحديث"*).

### 2. Automated Version & Build Counter Increment Rule
- Whenever the user explicitly authorizes a deployment/push:
  - The agent MUST automatically increment the `patch` version (e.g. `2.0.1` -> `2.0.2`) and `buildNumber` (e.g. `56` -> `57`) in [app_version_config.dart](file:///Users/fathalla/Development/Tashil%20Gift/lib/core/constants/app_version_config.dart).
  - The agent MUST synchronize [pubspec.yaml](file:///Users/fathalla/Development/Tashil%20Gift/pubspec.yaml) `version: <major>.<minor>.<patch>+<buildNumber>`.
  - The Header badge (`SwitchPointHeader`) will automatically reflect the new version across mobile and desktop.

### 3. Firebase Admin Console Link Requirement
- In every response following an authorized deployment to Firebase or push to GitHub, the agent MUST ALWAYS include:
  - 📦 **Current Version & Build**: e.g. `v2.0.1 (Build #56)`
  - 🔗 **Firebase Admin Console**: `https://console.firebase.google.com/project/tashil-gift/overview`
  - 🌐 **Live Web Application**: `https://tashil-gift.web.app`

### 4. Retail Price Intelligence & Unit Economics Rule (استخراج الأسعار ومقارنة السلاسل)
- **Single Unit Economics**: Whenever processing receipt items where `quantity >= 2`, `price` MUST strictly be the net selling price per single piece (`netLineTotal / quantity`), `originalPrice` MUST strictly be the gross regular price per single piece (`grossLineTotal / quantity`), and `discountAmount` MUST be the unit discount (`lineDiscount / quantity`). Never store or present line totals as unit prices.
- **Enterprise Chain Consolidation**: Supermarket branches must resolve to their canonical parent Retail Chain (`normalizeRetailChain`: `أسواق فتح الله`, `جملة ماركت`, `بيت الجملة`, `كارفور`, `خير زمان`, `سبينس`, إلخ). Comparisons in tables, KPI cards, and dialogs must strictly be between Enterprise Chains.
- Full details and auto-healing specifications are documented in [.agents/skills/retail-price-intelligence-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/retail-price-intelligence-standard/SKILL.md).

### 5. Standard AI Model Architecture Rule (معيار نموذج الذكاء الاصطناعي Gemini 3.7 Flash)
- **Primary Model**: All AI services across the project (`AiReceiptService`, `CampaignAiAssistantService`, `BranchSignatureAiService`, `AiProductCatalogService`, `AiProductDiscoveryService`) MUST strictly use **`gemini-3.7-flash`** as the standard primary model.
- **Fallbacks**: Secondary fallback models must follow `gemini-3.6-flash` and `gemini-2.5-flash`.
- **API Key**: Gemini API calls must strictly use the authorized Tier 1 Google AI Studio API key provided in `AiConfig.geminiApiKey`.

### 6. Promotional Rules & Single-Resolution Architecture Rule (معيار حوكمة احتساب هدايا العروض ومنع المضاعفة المكررة)
- **Absolute Multiplied Allocations**: `PromotionalRuleMatcher.matchAllWithMultipliers` calculates exact, final, multiplied item quantities based on the qualifying items in the customer's receipt.
- **Zero Double-Multiplication Invariant**: All screens (`DirectGiftClaimScreen`, `WinnerCelebrationDialog`, `CompanyGiftsService.decrementCampaignPrize`) MUST treat `linkedGifts` item counts as absolute values. Never re-multiply `giftAlloc.quantity` by basket chances or `effectiveQuantity` when `linkedGifts.isNotEmpty`.
- **Automatic AI Campaign Configuration**: When creating or suggesting new campaigns with `CampaignAiAssistantService`, promotional rules MUST automatically decompose voucher values into stock denominations (`LinkedGiftAllocation`) and configure single-resolution gift structures so every newly created campaign executes flawlessly without manual re-explanation.
- Full details documented in [.agents/skills/promotional-rules-single-resolution-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/promotional-rules-single-resolution-standard/SKILL.md).

### 7. Trilingual Directionality & Navigation Placement Rule (معيار اتجاه القوائم والملاحة RTL مقابل LTR)
- **Natural Start Alignment**: Primary navigation sidebars, rails, and master-detail splits MUST strictly be positioned at the natural layout **START**:
  - In **Arabic (`ar` / RTL)**: The navigation sidebar is visually on the **RIGHT** side of the screen.
  - In **English (`en` / LTR)** & **Hindi (`hi` / LTR)**: The navigation sidebar is visually on the **LEFT** side of the screen.
- **Flutter Row Convention**: Always place the sidebar as the **first child** in the parent `Row(children: [ sidebar, Expanded(child: content) ])` so Flutter's ambient `Directionality` handles proper mirroring across all languages automatically.
- **Directional Styling**: Use `BorderDirectional(end: ...)` for inner dividers, `EdgeInsetsDirectional` for insets, and dynamic shadow offsets (`Offset(isAr ? -2 : 2, 0)`).
- Full details documented in [.agents/skills/trilingual-localization-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/trilingual-localization-standard/SKILL.md).

### 8. Canonical Campaign Branch Governance & OCR Resolution Rule (معيار حوكمة واسترداد فروع الحملات المعتمدة ومنع التكرار)
- **Strict Canonical Scoping**: Dropdown filters, reporting tables, and branch pickers across all screens (`InvoicesLogScreen`, `CampaignReportsScreen`, `CompanyPrizesStockReportScreen`, `ValidationScreen`) MUST strictly display ONLY the canonical branches configured in the campaign (`event.branchNames`). Raw OCR variations, store codes, or noise strings must NEVER leak into available branch lists.
- **Geographic Parenthetical Striping & Anti-Collision**: Always strip parenthetical governorates (`(القاهرة)`, `(الإسكندرية)`, `(الغربية)`) prior to token comparisons. Different branches in the same city (e.g. `التجمع` vs `عمارات العبور`) must NEVER collide or group together based on city names.
- **Strict Filter Equality**: Once invoices are enriched with `canonical_branch` at load time, UI branch filtering MUST strictly use exact equality (`inv['canonical_branch'] == selectedBranch`) to prevent false-positive leakage.
- **Dynamic KPI Isolation**: Selecting any branch must dynamically recalculate all metric KPI cards (`totalInvoicesCount`, `totalPromoSales`, `totalExtractedItems`, `avgAiSpeed`) strictly for that specific branch.
- **Zero Rogue Branches & 100% Invoice Distribution**: Total invoices (e.g. 578 receipts) must distribute cleanly across the exact campaign branches (e.g. 12 branches) with accurate counts per branch and zero duplicates.
- Full details documented in [.agents/skills/campaign-branch-resolution-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/campaign-branch-resolution-standard/SKILL.md).

### 9. Ultra-Fast Performance, Lazy Loading & Firestore Indexing Rule (معيار الأداء والسرعة الفائقة والتحميل الكسول وفهرسة الاستعلامات)
- **On-Demand Lazy Loading**: Tab navigation and multi-view screens (`CompanyManagerPortalScreen`, etc.) MUST strictly use lazy on-demand instantiation (`_loadedTabs`) combined with `Offstage` + `TickerMode(enabled: isCurrentTab)`. NEVER use eager `IndexedStack` that mounts all heavy child views and triggers concurrent Firestore streams on initial load.
- **RepaintBoundary Animation Isolation**: Always wrap collapsible navigation sidebars, drawers, and heavy data viewports in independent `RepaintBoundary` widgets to guarantee 60 FPS transitions without triggering full-screen repaints during width/height animations.
- **Server-Side Scoped Firestore Queries**: Real-time streams and database reads MUST strictly apply server-side filtering (`.where('companySlug', isEqualTo: slug)`, `.where('campaignId', isEqualTo: eventId)`) before streaming data to the client. Never stream entire database collections to the client for client-side filtering.
- **O(1) Memoized Computation Caching**: Heavy data aggregation loops, product ranking sorting, and branch normalization regexes MUST NEVER run synchronously inside raw `build()` methods. All heavy metrics MUST be memoized with lightweight cache keys (`_cachedMetrics` + `_lastMetricsCacheKey`) to ensure rebuilds on scroll, hover, or resize return in 0.001ms.
- **Declared Cloud Firestore Composite Indexes**: All compound queries combining equality filters with sorting/inequality MUST be declared in [firestore.indexes.json](file:///Users/fathalla/Development/Tashil%20Gift/firestore.indexes.json) and linked in [firebase.json](file:///Users/fathalla/Development/Tashil%20Gift/firebase.json) for single-digit millisecond query responses.
### 10. Strict Receipt AI Verification & Zero-Hallucination Governance Rule (معيار الصرامة الفائقة ومنع التخمين وحوكمة عدم استحقاق الهدايا)
- **Zero Hallucination & Deterministic AI**: All Gemini 3.7 Flash extraction calls MUST strictly operate at `temperature: 0.0`. Never guess or hallucinate product identities, brands, or quantities.
- **Blurry & Illegible Image Rejection**: If a receipt is blurry, cropped, folded, or product names/quantities are illegible, the AI MUST strictly reject the receipt with `isValid = false` and `unfulfilledConditions: ['صورة الفاتورة غير واضحة أو اسم المنتج غير مقروء بدقة، برجاء إعادة تصوير الفاتورة بوضوح وإظهار سطر المنتج والكمية']`.
- **Zero Fallback Prize Invariant**: When a campaign has promotional rules (`event.promotionalRules.isNotEmpty`), gifts/vouchers can ONLY be awarded if a promotional rule is matched (`matchedRulesList.isNotEmpty`). If a customer bought a product that doesn't meet rule quantities (e.g. bought 1 bottle of Tresemme 400ml when the rule requires 2 bottles), the system MUST NEVER award a fallback prize (`prizeNames.first`). The receipt MUST be rejected with a clear report explaining the unfulfilled rule condition.
- Full details documented in [.agents/skills/strict-receipt-ai-verification-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/strict-receipt-ai-verification-standard/SKILL.md).
