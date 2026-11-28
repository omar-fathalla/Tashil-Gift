# AGENTS.md — Tashil Gift Workspace Guidelines

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
- **Strict Canonical Scoping**: Dropdown filters, reporting tables, and branch pickers across all screens (`InvoicesLogScreen`, `CampaignReportsScreen`, `CompanyPrizesStockReportScreen`) MUST strictly display ONLY the canonical branches configured in the campaign (`event.branchNames`). Raw OCR variations, store codes, or noise strings must NEVER leak into available branch lists.
- **Geographic Parenthetical Striping & Anti-Collision**: Always strip parenthetical governorates (`(القاهرة)`, `(الإسكندرية)`, `(الغربية)`) prior to token comparisons. Different branches in the same city (e.g. `التجمع` vs `عمارات العبور`) must NEVER collide or group together based on city names.
- **Strict Filter Equality**: Once invoices are enriched with `canonical_branch` at load time, UI branch filtering MUST strictly use exact equality (`inv['canonical_branch'] == selectedBranch`) to prevent false-positive leakage.
- **Dynamic KPI Isolation**: Selecting any branch must dynamically recalculate all metric KPI cards (`totalInvoicesCount`, `totalPromoSales`, `totalExtractedItems`, `avgAiSpeed`) strictly for that specific branch.
- **Zero Rogue Branches & 100% Invoice Distribution**: Total invoices (e.g. 578 receipts) must distribute cleanly across the exact campaign branches (e.g. 12 branches) with accurate counts per branch and zero duplicates.
- Full details documented in [.agents/skills/campaign-branch-resolution-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/campaign-branch-resolution-standard/SKILL.md).

### 9. Ultra-Fast Performance, Lazy Loading & Firestore Indexing Rule (معيار الأداء والسرعة الفائقة والتحميل الكسول وفهرسة الاستعلامات)
- **On-Demand Lazy Loading**: Tab navigation and multi-view screens (`CompanyManagerPortalScreen`, etc.) MUST strictly use lazy on-demand instantiation (`_loadedTabs`) combined with `Offstage` + `TickerMode(enabled: isCurrentTab)`. NEVER use eager `IndexedStack` that mounts all heavy child views and triggers concurrent Firestore streams on initial load.
- **RepaintBoundary Animation Isolation**: Always wrap collapsible navigation sidebars, drawers, and heavy data viewports in independent `RepaintBoundary` widgets to guarantee 60 FPS transitions without triggering full-screen repaints during width/height animations.
- **Server-Side Scoped Firestore Queries**: Real-time streams and database reads MUST strictly apply server-side filtering (`.where('companySlug', isEqualTo: slug)`, `.where('campaignId', isEqualTo: eventId)`) before streaming data to the client. Never stream entire database collections to the client for client-side filtering.
- **O(1) Memoized Computation Caching & Zero-Wipe Invariant**: Heavy data aggregation loops, product ranking sorting, and branch normalization regexes MUST NEVER run synchronously inside raw `build()` methods. All heavy metrics MUST be memoized with lightweight cache keys (`_cachedMetrics` + `_lastMetricsCacheKey`) to ensure rebuilds on scroll, hover, or resize return in 0.001ms. Incoming empty or transient snapshots MUST NEVER wipe or zero-out existing valid cached metrics.
- **Stale-While-Revalidate Persistent In-Memory Caching (0ms Instant Render)**: Dashboards and comparison screens MUST maintain static/persistent memory caches (`_persistentMetricsCache`, `_persistentEventsCache`) keyed by tenant/company. When navigating between tabs or toggling metrics, the UI MUST render existing data in 0ms immediately without showing full-screen spinners or flashing 0 values, while syncing updates silently in the background.
- **Stream Memoization Outside `build()`**: NEVER create Firestore `.snapshots()` directly inside `build()`. Streams MUST be memoized outside `build()` (`_ensureStreams` or `didChangeDependencies`) so that local `setState()` calls (such as toggling dimension chips or mode selectors) do not trigger stream cancellation, re-subscription cycles, or transient empty states.
- **Session-Preserved User Selections**: Comparative campaign selections, active dimensions, and filters MUST be retained across tab switches in static memory maps keyed by `companySlug`.
- **Phonetic & Multi-Variant Arabic Normalization**: Campaign transactions MUST be indexed and matched against both direct Firestore IDs and normalized Arabic titles (unifying `أ/إ/آ` -> `ا`, `ة` -> `ه`, `ى` -> `ي`, removing diacritics, and unifying hyphens, en-dashes, and spaces) to prevent dropped receipts or zero-value anomalies.
- **Declared Cloud Firestore Composite Indexes**: All compound queries combining equality filters with sorting/inequality MUST be declared in [firestore.indexes.json](file:///Users/fathalla/Development/Tashil%20Gift/firestore.indexes.json) and linked in [firebase.json](file:///Users/fathalla/Development/Tashil%20Gift/firebase.json) for single-digit millisecond query responses.
- Full details documented in [.agents/skills/ultra-fast-performance-and-indexing-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/ultra-fast-performance-and-indexing-standard/SKILL.md).
### 10. Strict Receipt AI Verification & Zero-Hallucination Governance Rule (معيار الصرامة الفائقة ومنع التخمين وحوكمة عدم استحقاق الهدايا)
- **Zero Hallucination & Deterministic AI**: All Gemini 3.7 Flash extraction calls MUST strictly operate at `temperature: 0.0`. Never guess or hallucinate product identities, brands, or quantities.
- **Blurry & Illegible Image Rejection**: If a receipt is blurry, cropped, folded, or product names/quantities are illegible, the AI MUST strictly reject the receipt with `isValid = false` and `unfulfilledConditions: ['صورة الفاتورة غير واضحة أو اسم المنتج غير مقروء بدقة، برجاء إعادة تصوير الفاتورة بوضوح وإظهار سطر المنتج والكمية']`.
- **Zero Fallback Prize Invariant**: When a campaign has promotional rules (`event.promotionalRules.isNotEmpty`), gifts/vouchers can ONLY be awarded if a promotional rule is matched (`matchedRulesList.isNotEmpty`). If a customer bought a product that doesn't meet rule quantities (e.g. bought 1 bottle of Tresemme 400ml when the rule requires 2 bottles), the system MUST NEVER award a fallback prize (`prizeNames.first`). The receipt MUST be rejected with a clear report explaining the unfulfilled rule condition.
- Full details documented in [.agents/skills/strict-receipt-ai-verification-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/strict-receipt-ai-verification-standard/SKILL.md).

### 11. Continuous AI Brain Directives & Heuristics Registration Rule (معيار التوثيق المستمر لمهارات وقواعد عقل الذكاء الاصطناعي)
- **Mandatory Directives Registration**: Whenever any new retail heuristic, receipt parsing rule, POS quirk handler, twin-bundle resolver, unit economics formula, or AI prompt enhancement is added to the system:
  1. The agent MUST register a corresponding formal directive in [ai_directives_seed_data.dart](file:///Users/fathalla/Development/Tashil%20Gift/lib/features/admin/domain/ai_directives_seed_data.dart) with a sequential ID (`AIR-XX`), clear Arabic/English descriptions, logic steps, and before/after example inputs and outputs.
  2. The directive MUST be synced to Firestore (`ai_brain_directives`) so it immediately renders in the AI Brain Rules screen (`AiBrainRulesScreen`).
  3. The catalog in the AI Brain screen must remain a live, growing knowledge base of everything taught to the AI across all campaigns and POS systems.
- Full details documented in [.agents/skills/continuous-ai-directives-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/continuous-ai-directives-standard/SKILL.md).

### 12. Material Design 3 Layout & Adaptive Design System Rule (معيار التخطيط والتصميم التكيفي الرسمي لماتيريال 3)
- **5 Official Window Size Classes**: Layout responsiveness MUST strictly adhere to the five official M3 breakpoints (`M3WindowSizeClass`): `Compact (<600dp)`, `Medium (600–839dp)`, `Expanded (840–1199dp)`, `Large (1200–1599dp)`, and `Extra Large (≥1600dp)`. Breakpoints must never use arbitrary thresholds.
- **Three-Tier Adaptive Navigation Transformation**: Navigation MUST automatically transform based on available width:
  - *Compact (<600dp)*: Body content fills 100% width; navigation transforms into a Modal Navigation Drawer or Bottom Navigation Bar.
  - *Medium (600–839dp)*: Navigation transforms into a Slim Navigation Rail (`width: 72dp–76dp`) with centered icons (at 38dp) and contextual hover tooltips, preserving 88%+ of screen width for data.
  - *Expanded & Large (≥840dp)*: Full Navigation Sidebar / Persistent Drawer (`width: 230dp–275dp`) with smooth animated expand/collapse transitions (`200ms`, `ClipRect` + `OverflowBox`).
- **Natural Start Navigation Placement (RTL vs LTR)**: The navigation sidebar/rail MUST strictly be placed at the natural start: situated on the **RIGHT** side in Arabic (`ar` / RTL) and on the **LEFT** side in English (`en` / LTR) and Hindi (`hi` / LTR).
- **Max-Width Containment & Visual Breathing**: Heavy viewports, reports, analytical screens, and forms MUST be wrapped in `M3ContentBoundary` with `maxWidth: 1360dp` (or `1440dp` max for high-density tables) centered horizontally (`Alignment.topCenter`), preventing unreadable stretching on ultra-wide / 4K displays while maintaining symmetric visual breathing margins.
- **8dp Baseline Spacing Grid**: All margins, paddings, and layout gaps MUST be exact multiples of 8dp (`M3Spacing`: `xxs: 4`, `xs: 8`, `sm: 16`, `md: 24`, `lg: 32`, `xl: 40`, `xxl: 48`, `xxxl: 64`). Random unaligned pixel values are strictly forbidden. Dashboard KPI cards MUST reflow dynamically (1 column on Compact, 2 columns on Medium, 4 columns on Desktop/Expanded).
- Full details documented in [.agents/skills/material-design-3-layout-and-adaptive-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/material-design-3-layout-and-adaptive-standard/SKILL.md).

### 13. Material Design 3 Lists, ListTiles & Inset Dividers Rule (معيار قوائم وعناصر وفواصل ماتيريال 3 القياسية)
- **Standard Height Constraints**: All list items throughout the app MUST strictly adhere to standard M3 heights: `56dp` for 1 line (desktop compact: `44-48dp`), `72dp` for 2 lines (desktop compact: `60dp`), and `88dp` for 3 lines (desktop compact: `76dp`).
- **72dp Directional Inset Dividers (`M3InsetDivider`)**: Inner dividers between list items MUST start with a 72dp indent (`indent: 72, endIndent: 0`), perfectly aligning with the headline text after the 16dp margin + 40dp avatar + 16dp spacing, mirroring naturally from the right in Arabic (RTL) and from the left in English/Hindi (LTR).
- **Minimum 48x48dp Touch Targets (`M3TouchTargetBoundary`)**: All trailing interactive action buttons, icons, or tap targets MUST guarantee a minimum touch area of `48x48dp` for full accessibility compliance (WCAG 2.1 AA / TalkBack / VoiceOver).
- **0ms Instant Selection Feedback**: Tapping or selecting an item MUST immediately trigger visual feedback with `colorScheme.secondaryContainer` and `12dp` rounded borders in 0ms without layout jumping.
- **Structured 48dp Subheaders (`M3Subheader`)**: Categorized lists, branch groups, and report sections MUST use standardized 48dp subheaders with clear Cairo typography and optional trailing actions.
- Full details documented in [.agents/skills/material-design-3-lists-and-tiles-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/material-design-3-lists-and-tiles-standard/SKILL.md).

### 14. Material Design 3 Action Menus & Cascading Submenus Rule (معيار قوائم الإجراءات والقوائم الفرعية المتتالية لماتيريال 3)
- **MenuAnchor Architecture & Legacy Deprecation**: The legacy `PopupMenuButton` is strictly deprecated across the entire codebase. All action menus, overflow controls, and dropdown options MUST use `M3ActionMenu` built upon Flutter's official `MenuAnchor`, `MenuItemButton`, and `SubmenuButton`.
- **M3 Container Elevation & Styling**: Menu surfaces MUST strictly use `colorScheme.surfaceContainer` with an **8dp** corner radius (`BorderRadius.circular(8.0)`), Level 2 elevation (`2.0dp`), 1dp `colorScheme.outlineVariant.withValues(alpha: 0.5)` border, and 4dp vertical padding. Raw white or grey surfaces are strictly forbidden.
- **Responsive Density & Touch Boundaries**: Menu items MUST adapt by window size: `48dp` item height on mobile touch devices, and `40dp` compact height on desktop displays. Anchor buttons MUST guarantee a minimum touch area of `48x48dp` (`M3SpacingTokens.minTouchTarget`).
- **Bidirectional Cascading Submenus & Automatic RTL Mirroring**: Submenu navigation chevrons MUST mirror automatically based on ambient layout direction: pointing **LEFT** in Arabic (`ar` / RTL) and pointing **RIGHT** in English (`en` / LTR) and Hindi (`hi` / LTR).
- **Semantic Hierarchy & Destructive Isolation**: Functional groups MUST be separated with headers (`M3ActionMenu.header`) and 1dp dividers (`M3ActionMenu.divider`). Irreversible or dangerous operations (Delete, Cancel, Reject) MUST set `isDestructive: true`, visually highlighting the action in **`colorScheme.error`**.
- **Full Keyboard Accessibility (a11y)**: All menus MUST support `ArrowUp`/`ArrowDown` navigation with wrap-around looping, instant activation via `Enter`/`Space`, clean dismissal via `Escape`, and fast character typeahead.
- Full details documented in [.agents/skills/material-design-3-action-menus-standard/SKILL.md](file:///Users/fathalla/Development/Tashil%20Gift/.agents/skills/material-design-3-action-menus-standard/SKILL.md).
