# CLAUDE.md — دليل الـ agent لمنظومة Tashil Gift (تسهيل جفت)

الملف ده أول حاجة أي session (Claude أو غيره) تقراها قبل ما تلمس الكود. فيه منطق المنظومة كلها، وخريطة كل صفحة: بتعمل إيه، مين يفتحها، بتقرا وتكتب فين، وإيه اللي لازم تاخد بالك منه.

* اتكتب بعد مراجعة كاملة للكود على فرع `dev` يوم **2026-11-26** عند الإصدار **2.0.192+252**.
* التفاصيل الأعمق في `docs/` (فهرسها `docs/README.md`). الملف ده هو الخريطة، و`docs/` هي المراجع.
* القواعد الإلزامية الكاملة في `AGENTS.md` (و`GEMINI.md` بقى مجرد إشارة ليه، TAG-75). لو فيه تعارض، `AGENTS.md` والطلب الصريح من محمد هما المرجع.

---

## 0. قبل ما تبدأ أي شغل (إلزامي)

1. **ممنوع `git push` أو `firebase deploy`** من غير طلب صريح من محمد في نفس المحادثة (AGENTS.md #1). النشر بيحصل من GitHub Actions بس، ومن غير `--force`.
2. **ابدأ من `dev`**: `git checkout dev` ثم فرع جديد (`fix/tag-NN-...` أو `feat/tag-NN-...`). الـ commit يبدأ برقم تيكت Linear: `TAG-67: ...`.
3. **الـ PR يروح على `dev`** مش `main`. `main` = إنتاج، وأي push عليه بينشر.
4. **ما تكتبش على Firestore الإنتاج** (`tashil-gift`) ولا تنسخ بيانات عملاء حقيقية لأي بيئة. للتجربة استخدم `tashil-gift-dev` أو الـ emulators.
5. لو هترفع إصدار (بعد طلب صريح): `patch + 1` و`buildNumber + 1` في 3 أماكن متطابقة: `lib/core/constants/app_version_config.dart`, `pubspec.yaml`, `web/version.json` (`python3 tool/ci/check_version.py` بيتأكد).
6. أي heuristic جديد للـ AI (قراية فواتير، POS quirk، معادلة سعر) لازم يتسجّل directive جديد `AIR-NN` في `lib/features/admin/domain/ai_directives_seed_data.dart` (آخر رقم حاليًا `AIR-89`).
7. أي PR بيغيّر سلوك موصوف هنا أو في `docs/` يحدّث الملف ده في نفس الـ PR.
8. المستخدم (محمد) بيكتب عامية مصرية. رد عليه بالعربي.

> **مفتاح Gemini (AGENTS.md #5، اتصحّحت في TAG-75):** مفيش أي مفتاح في العميل، وكل طلبات Gemini بتعدي على الـ callable `geminiGenerate` والمفتاح في Secret Manager. ما ترجعش مفتاح للعميل أبدًا.

---

## 1. المنظومة في سطور

منصة عروض ترويجية للشركات (Unilever، Knorr، Cadbury، Edita، Almarai، Clorox...) جوه فروع سلاسل السوبرماركت (فتح الله، جملة ماركت، بيت الجملة، كارفور، خير زمان، سبينس...).

```
العميل يشتري منتجات الشركة ← المندوب في الفرع يصوّر الفاتورة
  ← Gemini يقرا الفاتورة (رقم، تاريخ، فرع، سطور بسعر الوحدة)
  ← قواعد العرض (promotional rules) تحدد يستحق إيه
  ← لعبة (عجلة / كشط / اختار هديتك / هدية مباشرة)
  ← السيرفر يعيد التحقق ويخصم من رصيد الفرع (decrementCampaignPrize)
  ← (اختياري) WhatsApp للفائز
  ← البراند وشركة الدعاية يتابعوا التقارير والمخزون من بواباتهم
```

| | |
|---|---|
| المنصة | Flutter **Web** (فيه `android/` و`ios/` لكن مش بيتبنوا في الـ CI) |
| اسم الـ package | `al_mraay` (اسم قديم، كل الـ imports `package:al_mraay/...`) |
| اللغات | عربي RTL (الافتراضي)، إنجليزي، هندي. النصوص في `lib/core/localization/app_strings.dart` |
| الـ backend | Firebase: Auth، Firestore، Storage، Functions (Node 22, gen2, `us-central1`)، Hosting، App Check (reCAPTCHA) |
| الإنتاج | مشروع `tashil-gift` ← https://tashil-gift.web.app (و`gift.sw-point.com`) |
| التطوير | مشروع `tashil-gift-dev` ← https://tashil-gift-dev.web.app |
| State | Riverpod 2.x (`ProviderScope` في `main.dart`)، والـ providers الأساسية في `lib/core/services/firebase_service.dart` |

---

## 2. الأدوار والدخول

| الدور | الرابط | طريقة الدخول | الصلاحية |
|---|---|---|---|
| `super_admin` | `/` أو `/admin` | إيميل وباسورد، claim `role` | كل حاجة + الأدمنز (`admins`) وبيانات دخول البوابات (`portal_credentials`) + `setUserRole` |
| `admin` | `/` أو `/admin` | إيميل وباسورد | إدارة الشركات، الحملات، الهدايا، السلاسل، الفروع، الـ AI، كل الفواتير |
| مدير البراند (`brand_manager`) | `/portal/<slug>` (`/p`, `/brand`, `/company`) | يوزر/باسورد البوابة ← `partnerPortalLogin` ← custom token بـ `role=partner`, `partnerAccess=read` | قراية تقارير شركته بس، المخزون read-only |
| شركة الدعاية (`agency_ops`) | `/ops/<slug>` (`/agency`, `/operations`) أو `/ep/<eventId>` (`/event-portal`) | نفس الفكرة بـ `partnerAccess=ops`. `/ep/` ممكن يبقى ليه يوزر خاص بالحملة (`lockedEventId` في الـ claims) | الفواتير والأرصدة والفواتشر والمبيعات لشركته، وتعديل الأرصدة والفواتير |
| المندوب / العميل | `/c/<slug>` (`/client`, `/promoter`, `/submit`) أو `/e/<eventId>` (`/event`) | جلسة Anonymous تلقائية | رفع فواتير لحملات نشطة للشركة دي، ورؤية فواتيره هو |

* الـ claims بتتحط بـ `setUserRole` (super_admin بس) لحسابات الإيميل، وبـ `partnerPortalLogin` لحسابات البوابة (uid شكله `portal_<hash>`، وفيه `credVersion`؛ تغيير الباسورد بيزوّد الـ version فيطرد الجلسات القديمة).
* البوابات بتشتغل على Firebase app منفصل اسمه `partner-portal` (`lib/core/services/firebase_scope.dart`)، عشان دخول البوابة في تاب ما يمسحش جلسة المندوب الـ anonymous في تاب تاني. في أي كود بيتنادى من البوابة استخدم `scopedFirestore()` / `scopedFunctions()` / الـ providers، مش `FirebaseFirestore.instance`.
* الجلسة الـ anonymous بتتعمل بس على الروابط العامة (`routeNeedsAnonymousSession`)، مش في زيارات الأدمن.
* الأدمن اللي داخل بالفعل بيعدي من `PortalAuthGuard` من غير يوزر البوابة.

---

## 3. خريطة الكود

```
lib/
├── main.dart                     # تهيئة Firebase + App Check + anonymous + كل الـ routing (_buildRouteForUri)
├── firebase_options*.dart        # prod و dev (يتحدد بـ --dart-define=APP_ENV=dev)
├── core/
│   ├── config/                   # app_env (prod/dev)، ai_config، firebase_env_options
│   ├── constants/                # ai_models، app_version_config (الإصدار)، country_currency_config
│   ├── services/                 # منطق الأعمال الحقيقي (AI، الهدايا، السلاسل، البوابات...)
│   ├── utils/                    # حل الفروع، نافذة التاريخ، أرقام عربي، slugs، ضغط الصور
│   ├── widgets/                  # مكونات M3 مشتركة + CampaignSuspendedScreen + EnvBadge
│   ├── localization/ theme/ animations/ update/(فحص إصدار جديد وإعادة تحميل)
└── features/
    ├── admin/        (data/ domain/ presentation/)   لوحة الأدمن وكل شاشات الإعداد
    ├── auth/                                         دخول الأدمن ودخول البوابات
    ├── client_portal/                                شاشة المندوب ودايالوجاتها
    ├── company_portal/ (domain/ presentation/)       بوابة البراند/العمليات + WhatsApp + التسويق
    ├── games/                                        الألعاب وصرف الهدايا
    └── validation/                                   سجل الفواتير
functions/            # Cloud Functions (CommonJS). index.js + security_functions.js
rules-tests/          # اختبارات firestore.rules و storage.rules (Jest على الـ emulator)
test/                 # ~199 ملف اختبار Flutter
tool/                 # ci/، seed_dev.js، fixtures، benchmark
docs/                 # التوثيق المرجعي (عربي)
.agents/skills/       # تفاصيل كل معيار من AGENTS.md
```

**تنبيه حجم:** الشاشات ضخمة جدًا. اقرا الجزء اللي محتاجه بـ grep/offset، ما تقراش الملف كله:
`create_event_screen.dart` ~10.2k سطر، `invoices_log_screen.dart` ~8.5k، `ai_receipt_service.dart` ~6.3k، `company_prizes_stock_report_screen.dart` ~5.8k، `campaigns_comparison_analytics_screen.dart` ~5.2k، `company_customers_marketing_screen.dart` ~5k، `client_receipt_upload_screen.dart` ~4.3k، `company_catalog_screen.dart` ~4.1k.

---

## 4. الـ Routing (`lib/main.dart`)

`MyApp._buildRouteForUri` بيحوّل أي URI (نظيف أو `#` قديم) لشاشة واحدة (`onGenerateInitialRoutes` بيرجّع route واحد عشان الـ deep link ما يتفكّكش).

| الرابط | الشاشة |
|---|---|
| `/`, `/admin`, أي حاجة مش معروفة | `AdminAuthGuard` ← `AdminDashboardScreen` لو أدمن، وإلا `AuthScreen` |
| `/login`, `/auth` | `AuthScreen` |
| `/c/<slug>`, `/client/<slug>`, `/promoter/<slug>`, `/submit` | `ClientReceiptUploadScreen(companySlug)` |
| `/e/<eventId>`, `/event/<eventId>` | `ClientReceiptUploadScreen(initialEventId)` |
| `/portal/<slug>`, `/p/`, `/brand/`, `/company/` | `CompanyManagerPortalScreen` (وضع البراند) داخل `PortalAuthGuard` |
| `/ops/<slug>`, `/agency/`, `/operations/` | `CompanyManagerPortalScreen(isAgencyOpsMode: true)` |
| `/ep/<eventId>`, `/event-portal/` | بوابة عمليات مقفولة على حملة واحدة |
| مسار فاضي بعد البادئة | `CampaignSuspendedScreen` |
| `EmulatorFixtureGiftClaimScreen.route`, `EmulatorMissingLedgerProbeScreen.route` | شاشات اختبار للـ emulator بس |

Hosting rewrites (`firebase.json`): `/waha/**` ← `wahaProxy`، روابط المشاركة والبوابات ← `sharePreview` (OpenGraph)، والباقي ← `index.html`.

---

## 5. نموذج البيانات المختصر

التفاصيل الكاملة والصلاحيات في `docs/03-data-model.md`. أهم المجموعات:

| المجموعة | المحتوى | ملاحظات |
|---|---|---|
| `companies/{slug}` | الشركة: الاسم، اللوجو، يوزرات البوابات (`brandManagerUsername/Password`, `agencyOpsUsername/Password`, `brand/agencyCredentialVersion`)، `whatsappGatewayConfig` | الباسوردات نص صريح (TAG-70). أدمن بس |
| `company_products` | كتالوج الشركة: اسم، باركود، براند، مجموعة، حجم، `chainAliases` (اسم الصنف في كاشير كل سلسلة) | منع تكرار الاسم/الباركود للشركة |
| `company_gifts/{giftId}` | مخزون الهدايا والفواتشر (`CompanyGiftModel`): منتج مادي أو فاوتشر بقيمة فئة، دفعات توريد | `syncCompanyGiftsAvailableQuantities` بعد حفظ الحملة |
| `gift_stock_movements` | سجل حركات المخزون | |
| `retail_chains` / `branches` | السلاسل والفروع (`BranchModel`: كود المتجر، POS، رقم ضريبي، سجل تجاري، خط ساخن، عنوان، «توقيع» الفاتورة) | تحديد الفرع من الفاتورة بيعتمد عليها |
| `events/{eventId}` | الحملة (`EventModel`، `features/admin/domain/event_model.dart`) | شوف تحت |
| `events/{id}/content/{products,products_N,prompt}` | منتجات وبرومبت الحملة لما يكبروا (TAG-62) | `CampaignContentRepository` (عميل) و`campaign_content.js` (سيرفر) |
| `event_drafts` | مسودات الحملات (C-05) | محدش بيقراها غير شاشة الإنشاء |
| `receipts_transactions/{id}` | كل فاتورة اترفعت (مقبولة أو مرفوضة) | ID ثابت `rcpt_{campaignId}_{receiptNo}` لمنع التكرار |
| `daily_campaign_branch_sales` | تجميعة مبيعات يومية لكل فرع | `DailySalesAggregationService` |
| `campaign_stock_settlements` | تسويات «نهاية الأسبوع» للأرصدة | من شاشة أرصدة الفروع |
| `chain_products_catalog` | أسعار المنتجات في السلاسل (من الفواتير) | ذكاء الأسعار |
| `discovered_products_inbox` | منتجات جديدة لقاها الـ AI في الفواتير ومستنية اعتماد | |
| `ai_brain_directives` | قواعد عقل الـ AI `AIR-NN` | seed من `ai_directives_seed_data.dart` |
| `system_settings` | الموديل النشط وإعدادات عامة | `AiModelConfigService` |
| `marketing_contacts`, `company_supervisors` | جمهور WhatsApp التسويقي ومشرفين الشركة | |
| `whatsapp_*` | inbound، status، outbox، sender_links، webhook_config، webhook_campaigns | السيرفر بيكتب |
| `admins`, `portal_credentials`, `portal_access_logs` | إدارة الدخول | super_admin |
| `rateLimits`, `loginThrottle` | حماية | السيرفر بس |

### الحملة `EventModel` (أهم الحقول)

* هوية: `eventName`, `targetCompany`, `companySlug`, `companyLogoUrl`.
* حالة: `isActive` (الحملة كلها)، و`isPromoterActive` / `isAgencyActive` / `isManagerActive` (كل بوابة لوحدها)، `startDate`/`endDate`. `autoCloseExpiredCampaigns` بيقفلها بعد يوم النهاية بتوقيت القاهرة.
* شروط: `minimumSpend`, `requiredProducts`, `customPrompt`, `promotionalIdea`.
* `promotionalRules: List<PromotionalRuleItem>`: `conditionType` (`by_quantity` | `by_spend` | `combo_spend`)، `minQuantity`/`minSpend`/`maxSpend`، `matchMode` (`OR`/`AND`)، `requiredBrands`، `selectedProductIds/Barcodes/Names`، `rewardType` (`voucher` | `free_product` | `game_spin`)، `allowMultipliers`، `linkedGifts` (كميات نهائية)، `gameType` خاص بالقاعدة، `rewardOptions` (العميل يختار واحدة).
* لعبة الحملة: `gameType` = `wheel` | `scratch` | `directGift` | `chooseGift` (القاعدة ممكن تغيّرها).
* هدايا: `allocatedPrizes` (لكل فرع×هدية: `allocatedQuantity`, `remainingQuantity`, `branchId`, `giftType`, `unitValue`).
* فروع: `retailChainId`, `branchIds`, `branchNames`, `isAllBranches`.
* فرص: `allowMultipleChances`, `multiplierBasis`, `maxChancesPerReceipt`, `spendLadderMode` (`exclusive` افتراضي | `consuming`).
* إعدادات: `voucherSerialMode` (`required`|`optional`|`hidden`)، `allowComplementaryReceipts`، `enableWhatsAppWinnerNotification`، `customAgencyUsername/Password/CredentialVersion`، `contentInfo` (المنتجات/البرومبت جوه المستند ولا في `content/`).

### مستند الفاتورة (`receipts_transactions`)

`receipt_number`, `receipt_date`, `status` (`accepted` | `rejected`)، `is_valid`, `rejection_reason`, `unfulfilled_conditions`, `total_value`, `target_company_total` (إجمالي منتجات الحملة بس)، `extracted_products` (سعر **الوحدة**)، `store_chain_detected`, `is_branch_matched`, `canonical_branch` (بيتحسب وقت التحميل)، علامات الغش (`is_handwritten`, `is_thermal_pos_receipt`, `is_tampered`, `is_screen_capture`, `fraud_risk_score`, `fraud_reasons`)، الصور (`image_url(s)`, `storage_path(s)`, `parts_count`)، العميل (`customerName`, `customerPhone`)، الربط (`campaignId`, `companySlug`, `targetCompany`, `submittedByUid`)، الـ AI (`analysis_duration_ms`, `ai_kpi_rating`, `aiMessage`, `matched_rule_id`)، الفرص (`chances_earned`, `remaining_chances`)، والصرف (`game_played`, `prize_won`, `claimed_gifts` — **السيرفر هو اللي بيكتبها**)، و`near_miss`, `price_check`, `branch_load` للتشخيص.

---

## 6. الـ flows الأساسية

### 6.1 دورة حياة الحملة

1. الأدمن يسجّل الشركة ومنتجاتها (الكتالوج) وهداياها (كتالوج الهدايا) والسلسلة وفروعها.
2. «إنشاء حملة» (`CreateEventScreen`): البيانات، الفترة، اللعبة، السلسلة والفروع، توزيع الهدايا على الفروع، قواعد العرض والبرومبت، واجهة العميل. ممكن يحفظ مسودة أو «جرّب على فاتورة» (`dryRunCampaignEligibility`، من غير كتابة).
3. الحفظ: ملخص مراجعة (`CampaignActivationSummaryDialog`) ← رفع اللوجو ← حفظ `events/{id}` + `content/` ← **تأكيد من السيرفر** (N-01: «تحقق» بيقرا من السيرفر مش الكاش) ← حفظ يوزر الوكالة الخاص ← مسح المسودة ← مزامنة أرصدة الهدايا ← دايالوج الروابط والـ QR.
4. التشغيل: الروابط الثلاثة (المندوب `/c/<slug>`، العمليات `/ops/<slug>`، البراند `/portal/<slug>`) من كارت الحملة في اللوحة.
5. الإيقاف: يدوي (`isActive` أو بوابة معيّنة)، أو تلقائي بعد يوم النهاية.

### 6.2 الفاتورة: من التصوير للصرف

التفاصيل خطوة بخطوة في `docs/04-receipt-and-claim-flow.md`. الملخص:

`ClientReceiptUploadScreen._submitAndValidateReceiptImpl` ← (session) استعادة جلسة المندوب ونافذة التاريخ ← تجهيز الصور (معايرة الحراري + تصغير، ممكن أكتر من جزء) ← (lookup) كتالوج الباركود وتوقيعات الفروع ومحتوى الحملة ← (ai) `AiReceiptService.analyzeReceiptImage` ← `GeminiCloudModel` ← `geminiGenerate` ← `PromotionalRuleMatcher.matchAllWithMultipliers` ← (dupCheck) `checkReceiptDuplicate` ← (storage) رفع الصورة ← (save) حفظ المستند ← تحديد الفرع ← اللعبة ← `decrementCampaignPrize` (السيرفر يعيد الأهلية ويخصم في transaction).

**أسباب الرفض** (بتظهر للمندوب في `ReceiptIssueDialog` بصياغة مفهومة مش نص تقني): صورة مش واضحة، خط يد، تلاعب، سكرين شوت، مش فاتورة POS حرارية، فرع أو سلسلة مش في الحملة، تاريخ برّه الفترة، قواعد العرض ما اتحققتش، مكررة، أو مصروفة قبل كده.
**Near miss (2.0.171):** لو السبب الوحيد هو الإنفاق والفرق أقل من 10% من أقرب حد، بيطلب إعادة تصوير بدل الرفض النهائي (ولسه بيتسجّل rejected مع `near_miss`).

**اختيار اللعبة:** `directGift` ← `DirectGiftClaimScreen`؛ `chooseGift` أو حملة `consuming` ← `ChooseGiftScreen`؛ `scratch` (أو إجمالي ≥ 500 لو مفيش نوع) ← `ScratchCardScreen`؛ غير كده ← `SpinTheWheelScreen`. لو الفاتورة تنفع لأكتر من حملة للشركة ← `UnifiedMultiCampaignClaimScreen`.

### 6.3 تحديد الفرع

`SmartBranchMatcherService` + `canonical_branch_resolver` + `store_code_branch_resolver` (كود الفرع من رقم الفاتورة) + `BranchSignatureAiService`. ممنوع تخمين «أول فرع». في الفلاتر والتقارير: فروع الحملة المعتمدة بس (`event.branchNames`)، ومقارنة بالمساواة على `canonical_branch` (AGENTS.md #8).

### 6.4 WhatsApp (WAHA)

* الإعدادات لكل شركة في `companies/{slug}.whatsappGatewayConfig`. العميل بيكلّم `<origin>/waha/**` ← `wahaProxy` (ID token + App Check + origin allowlist). مفتاح WAHA عمره ما بيوصل للعميل.
* إشعار الفائز: `sendWinnerWhatsApp` لو `enableWhatsAppWinnerNotification`.
* الوارد: `wahaWebhook` (HMAC بـ `WAHA_WEBHOOK_SECRET`) بيستقبل صورة فاتورة ويحللها بنفس `verifyReceiptImage` ويصرف. ربط الأرقام بالحملات في `whatsapp_sender_links` (`manageWhatsappSenderLink`).
* في dev: `WAHA_API_KEY` لازم يفضل dummy، وما تستخدمش جلسة WhatsApp الإنتاج أبدًا (هتبعت لعملاء حقيقيين).

---

## 7. مراجعة صفحة صفحة

الصيغة: **الملف** — مين يفتحها — بتعمل إيه — بتقرا/تكتب — ملاحظات.

### 7.1 الدخول

* **`AuthScreen`** (`features/auth/presentation/auth_screen.dart`) — `/login` أو `/` لغير الأدمن. دخول الأدمن بإيميل وباسورد، مع «تذكرني». الصلاحية من الـ claim `role`؛ لو مسجّل ومفيش claim أدمن بيفضل على الشاشة دي.
* **`PortalAuthGuard` + `PartnerPortalLoginScreen`** (`partner_portal_login_screen.dart`) — بيلف بوابات البراند والعمليات. بيعدّي الأدمن مباشرة. بيتحقق من الجلسة المحفوظة مقابل `credentialVersion` الحالي (`partnerPortalInfo`)، ويفصل الأدوار (`brand_manager` ≠ `agency_ops`)، ويعدّي `lockedEventId` لبوابة الحملة الواحدة. الدخول عن طريق `partnerPortalLogin` (فيه throttle بعد محاولات كتير: HTTP 429 و`Retry-After`). المنطق في `core/services/partner_portal_auth_service.dart`.

### 7.2 بوابة المندوب (عامة، Anonymous)

* **`ClientReceiptUploadScreen`** (`client_portal/presentation/client_receipt_upload_screen.dart`) — `/c/<slug>` أو `/e/<eventId>`.
  * بتجيب حملات الشركة اللي `isActive && isPromoterActive` (stream حي على `events`). لو أكتر من حملة فيه اختيار «كل الحملات» (`__AUTO_ALL__`) والفاتورة تتقيّم على الكل (`MultiCampaignReceiptEvaluator`).
  * المندوب يصوّر (كاميرا/معرض، أكتر من جزء)، يدخل اسم ورقم العميل، ويبعت. الـ flow في 6.2.
  * لو الحملة موقوفة بتعرض شاشة الإيقاف. **تنبيه:** أي خطأ في تحميل الحملة (مثلًا Anonymous auth مقفول) بيظهر برضه «الحملة موقوفة»، وده مضلل وقت التشخيص.
  * بتسجّل الفواتير المرفوضة للمراجعة (`_recordRejectedReceipt`)، وفشل الحفظ (`logReceiptSaveFailure`).
  * حصاد المنتجات/الأسعار/الفروع الجديدة في الخلفية بيشتغل **للـ staff بس** (المندوب الـ anonymous ممنوع يكتب في المجموعات دي، 2.0.155).
  * الأزرار العلوية بتفتح الدايالوجات اللي تحت.
* **`CampaignBriefDialog`** — فكرة الحملة وقواعد العرض بصياغة مفهومة والفروع المشاركة متجمعة حسب السلسلة (بالـ ID أولًا، والاسم fallback للحملات القديمة).
* **`CampaignGiftBalanceDialog`** — هدايا الحملة، سجل الصرف اليومي بتنقّل بالتاريخ، ورصيد الفرع. المندوب يقدر «يثبّت» فرعه (محفوظ محليًا).
* **`PromoterInvoicesDialog`** — سجل فواتير المندوب: فواتيره هو (`submittedByUid`)، وتاريخ الفرع كله عن طريق `listBranchReceipts` (المندوب الـ anonymous مش بيقدر يقرا فواتير غيره مباشرة). بحث وفلترة بالفرع والتاريخ. إعادة الفحص (قواعد سريعة أو AI كامل) **للأدمن بس**.
* **`ReceiptIssueDialog`** — مكان واحد لكل أسباب الرفض والأخطاء التقنية، بعنوان وتلميح «تعمل إيه» بالعربي والإنجليزي، وكود الخطأ صغير للدعم.
* **`UnifiedMultiCampaignClaimScreen`** — لما فاتورة واحدة تستحق من أكتر من حملة لنفس الشركة: خانات أرقام الفواتشر لكل حملة وصرف الكل.

### 7.3 الألعاب وصرف الهدايا (`features/games/presentation/`)

كل الألعاب ليها وضع `isDemo` (من غير خصم ولا WhatsApp) بيستخدمه «أنواع الألعاب» في لوحة الأدمن، وبيظهر فوقها `GameDemoBanner`.

* **`DirectGiftClaimScreen`** — هدية فورية من غير لعب. الصرف **تلقائي** أول ما الفوز يظهر (2.0.163)، وزرار المندوب بس بيأكد التسليم الفعلي (أو يعيد محاولة صرف فشلت). بيحترم سقف القطع للفاتورة (2.0.164، الأعلى قيمة أولًا). بيدعم `rewardOptions` (العميل يختار) وأرقام كروت الفواتشر حسب `voucherSerialMode`، وتنبيه رصيد قليل للمندوب.
* **`ChooseGiftScreen`** — شبكة هدايا يختار منها العميل (ومع `consuming` جولة لكل شريحة). بيقرا الـ ledger من السيرفر بس (مش الكاش) عشان الاستكمال بعد انقطاع (`claim_ledger_resume`).
* **`ScratchCardScreen`** — كارت كشط، والخصم بعد الكشف.
* **`SpinTheWheelScreen`** — عجلة. بيجيب رصيد الفرع الحي قبل كل لفة عشان صنف خلص ما يظهرش، وبيقفل اللعب لما الفرص تخلص.
* **`MysteryBoxScreen`** — صناديق مفاجآت. **بيتفتح من الديمو بس**؛ مش من ضمن قيم `gameType` ومش بيتوصل من مسار الفاتورة.
* **`WinnerCelebrationDialog`** — احتفال الفوز (confetti) ومتابعة إرسال WhatsApp.
* **`GameTypesScreen`** — تبويب في لوحة الأدمن: شرح كل لعبة وديمو حي وسيناريوهات (عرض مفرد، مضاعفة 2×، سلة مجمعة) وتجربة الأصوات.
* **`EmulatorFixtureGiftClaimScreen`, `EmulatorMissingLedgerProbeScreen`** — للاختبارات على الـ emulator بس.

الصرف في كل الألعاب: `CompanyGiftsService.decrementCampaignPrize` ← callable `decrementCampaignPrize` مع retry وfallback (`claim_retry.dart`, `claim_callable_fallback.dart`). السيرفر بيرفض صرف تاني لنفس الفاتورة.

### 7.4 لوحة الأدمن (`AdminDashboardScreen`)

قائمة جانبية (موبايل: 4 أزرار + «المزيد»). التبويبات بالترتيب (`_buildMainViewForIndex`):

| # | التبويب | الشاشة |
|---|---|---|
| 0 | إدارة الحملات | كروت الحملات (مدمج في اللوحة) |
| 1 | التحليلات | `CampaignReportsScreen` |
| 2 | دليل الشركات | `CompanyCatalogScreen` |
| 3 | السلاسل والفروع | `RetailChainsScreen` |
| 4 | ذكاء المنتجات | `ChainProductsIntelligenceScreen` |
| 5 | تدقيق الفواتير | `InvoicesLogScreen` |
| 6 | هدايا الشركات | `CompanyGiftsScreen` |
| 7 | أنواع الألعاب | `GameTypesScreen` |
| 8 | سرعة الـ AI | `AiSpeedBenchmarkScreen` |
| 9 | عقل الـ AI | `AiBrainRulesScreen` |
| 10 | اكتشاف المنتجات | `AiProductDiscoveryScreen` (عليه عداد المنتظر) |
| 11 | تسويق WhatsApp | `CompanyCustomersMarketingScreen(isEmbedded: true)` |

* **تبويب الحملات (0)** — كروت كل الحملات (فلترة بالحالة وعدّادات)، إنشاء حملة، المسودات (`CampaignDraftsSheet`). كل كارت: الفروع، الـ slug، الحد الأدنى، الفترة، عدد الأصناف، نسخ البرومبت، نسخ الروابط الثلاثة، معاينة حية لكل بوابة، `PortalCredentialsDialog` (يوزرات البوابات + كارت WhatsApp جاهز للإرسال)، تعديل (`CreateEventScreen(eventToEdit)`)، `VoucherSerialsManagementDialog` (سجل أرقام كروت الفواتشر وإعادة تعيينها)، وحذف الحملة (وبعدها مسح `content/` best effort).

* **`CreateEventScreen`** (إنشاء/تعديل حملة، ~10k سطر). الأقسام بالترتيب:
  1. البيانات الأساسية: الاسم، الشركة (من `companies`)، الـ slug، الحد الأدنى، اختيار المنتجات من الكتالوج (بحث وفلترة براند، مع aliases عربي زي Axe/Lux)، الفرص المتعددة، وضع أرقام الفواتشر، الفواتير التكميلية، إشعار WhatsApp، يوزر الوكالة الخاص بالحملة.
  2. فترة السريان.
  3. نوع اللعبة (مع إعدادات `chooseGift` و`directGift`).
  4. السلسلة والفروع: اختيار سلسلة أو أكتر، إضافة سريعة لسلسلة/فرع، و`SmartBranchBatchImporterDialog` (استيراد فروع من Excel أو صورة فاتورة بالـ AI وتسجيل الجديد).
  5. توزيع الهدايا على الفروع (يدوي أو بالتساوي).
  6. استوديو الـ AI والقواعد: قواعد العرض (إضافة/تعديل، presets، كشف تعارض `RuleConflictIssue`)، «هيكلة الحملة بالـ AI» من وصف حر (`CampaignAiAssistantService`، بيقسّم الفاوتشر لفئات المخزون)، والبرومبت بيتولّد من القواعد (البرومبت المكتوب يدوي ما بيتلمسش).
  7. واجهة العميل: النصوص والشروط واللوجو.
  * أزرار: حفظ مسودة (`event_drafts`)، «جرّب على فاتورة» (`CampaignTryReceiptDialog` ← `dryRunCampaignEligibility`)، حفظ (الخطوات في 6.1).
  * **TAG-62:** في التعديل، الحفظ مقفول لحد ما منتجات/برومبت الحملة يتحملوا من `content/`، وإلا هيتمسحوا.
  * لو الحفظ ما اتأكدش من السيرفر بيظهر `CampaignSavePendingBanner` وزرار «تحقق».

* **`CampaignReportsScreen`** (التحليلات) — تقارير حملة: KPIs، الأصناف الأكثر مبيعًا (أصناف الشركة بس أو الكل)، توزيع الفروع والسلاسل (رسوم `branch_chain_analytics_charts.dart`)، جدول الفواتير بالصفحات، فلترة بالتاريخ واليوم، تصدير Excel/CSV. بتقرا `events` و`receipts_transactions` و`branches`. نفس الشاشة هي تبويب «التحليلات» في بوابة البراند.

* **`CompanyCatalogScreen`** (دليل الشركات) — تسجيل الشركات بكود (slug) فريد وتعديلها وحذفها، وكتالوج منتجات كل شركة: إدخال يدوي، استيراد Excel/CSV بأي ترتيب أعمدة (Gemini بيكتشف الأعمدة، `AiProductCatalogService`)، قائمة معاينة قبل الحفظ، منع تكرار الاسم/الباركود، تدقيق وإزالة المكرر، مسح كل منتجات شركة، «aliases» الكاشير لكل سلسلة، مراجعة المنتجات المكتشفة من الفواتير (`AiDiscoveredProductsDialog`)، والدخول على يوزرات البوابات. بتكتب `companies` و`company_products`.

* **`RetailChainsScreen`** (السلاسل والفروع) — CRUD للسلاسل والفروع، بحث، seed للسلاسل المعروفة، تنظيف التكرار، و«مسح فاتورة بالـ AI» لاستخراج بصمة الفرع (Store ID، POS، رقم ضريبي، سجل تجاري، خط ساخن، عنوان) ومقارنة الفرق قبل التحديث (`_showBranchUpdateDiffDialog`)، ودمج بيانات الفروع المرصودة من الفواتير. بتكتب `retail_chains` و`branches` عن طريق `RetailChainsService`.

* **`ChainProductsIntelligenceScreen`** (ذكاء المنتجات والأسعار) — مقارنة أسعار نفس المنتج بين السلاسل (رادار شامل، مقارنة سلسلتين، الأرخص/الأغلى، كسر الأسعار، عروض المنافسين، «فرص توريد» لمنتجات مش موجودة عند فتح الله)، مصفوفة `ChainProductsMatrixTable`، تاريخ السعر (`ProductPriceHistoryDialog`)، «تدقيق جديد» (healing: إعادة فحص الفواتير بالـ AI)، تصدير. البيانات في `chain_products_catalog` (`ChainProductsIntelligenceService`). المقارنة دايمًا بين السلاسل الأم (`normalizeRetailChain`)، وسعر الوحدة مش إجمالي السطر (AGENTS.md #4).

* **`InvoicesLogScreen`** (تدقيق الفواتير، ~8.5k سطر) — نفس الشاشة للأدمن والبوابات (`isEmbedded`، `lockedCompanySlug`، `lockedEventId`). فلترة بالحالة (`accepted` الافتراضي / `rejected` / `all`)، الحملة، الفرع (المعتمد بس)، التاريخ، والبحث؛ KPIs بتتحسب للفرع المختار؛ صفحات (`_loadMore`)؛ تصدير CSV؛ بحث برقم الفاتورة. **للأدمن بس (مش embedded):** حذف فاتورة، إعادة فحص (قواعد سريعة أو AI كامل) وكتابة النتيجة على المستند، وفتح Copilot عقل الـ AI على الفاتورة. شركة العمليات تقدر تعدّل فواتير شركتها حسب `partnerReceiptUpdate` في الـ rules.

* **`CompanyGiftsScreen`** (هدايا الشركات) — كتالوج الهدايا لكل شركة: منتج مادي أو فاوتشر نقدي بقيمة الكارت الواحد (فئات سريعة)، صورة اختيارية (`company_gifts/` في Storage)، تعديل وحذف. بتكتب `company_gifts`. توزيع الكميات على الفروع بيحصل في الحملة مش هنا.

* **`AiSpeedBenchmarkScreen`** — قياس سرعة قراية فاتورة (fast tier أو deep audit) على صورة مرفوعة أو فاتورة مولّدة، وعرض JSON الخام وتقييم KPI، وتصدير السجل CSV.

* **`AiBrainRulesScreen`** (عقل الـ AI) — كتالوج الـ directives (`AIR-NN`) ببحث وتصنيف وتفاصيل (المنطق، الكود، مثال قبل/بعد)، إضافة/تعديل، مزامنة سحابية (`AiDirectivesService` ← `ai_brain_directives`)، تبديل الموديل (`AiModelSwitcherDialog` ← `system_settings`)، و`AiBrainCoPilotStudioWidget` (شات نصي/صوتي/صور مع الـ AI: نشر directive جديد، محاكاة dry-run، تحليل اتجاهات الرفض من `receipts_transactions`).

* **`AiProductDiscoveryScreen`** — صندوق المنتجات المكتشفة (`discovered_products_inbox`): اعتماد فردي أو جماعي للكتالوج، تعديل قبل الاعتماد، فحص الفواتير التاريخية، وتنظيف الصندوق بمعايير AIR-72 (باركود أقل من 8 أرقام، سطور خدمية زي أكياس/توصيل، براند مش تبع الشركة، ظهور مرة واحدة).

* **`CompanyCustomersMarketingScreen`** (تسويق WhatsApp، في لوحة الأدمن بس) — بيجمّع العملاء من الفواتير + `marketing_contacts` المستوردة + `company_supervisors` في ملفات موحدة؛ شرائح وبحث (debounce 600ms)؛ محرر رسالة بـ tags وقوالب ووسائط (`whatsapp_campaign_media/`)؛ إرسال متتابع بفواصل ضد السبام (`WhatsappCampaignDispatcherDialog`، auto أو يدوي)؛ فحص الأرقام النشطة؛ رسالة تجربة؛ إعدادات البوابة (`WhatsAppGatewaySettingsDialog`: اختبار الاتصال، QR pairing، restart، logout، محاكي الرد الآلي، تجربة رسالة فائز)؛ `WhatsAppLiveOutboxView` و`WhatsAppWebhookInboxView` (الوارد وربط الأرقام، للـ staff بس)؛ تصدير Excel وVCF.

### 7.5 بوابة الشركة (`CompanyManagerPortalScreen`)

لوحة M3 مقفولة على شركة واحدة (و`lockedEventId` لو `/ep/`). التبويبات بتتبني lazy (`_loadedTabs` + `Offstage` + `TickerMode`) عشان ما تفتحش كل الـ streams مرة واحدة (AGENTS.md #9). فيها إعدادات (اللغة، العملة، الثيم، روابط المشاركة) وتسجيل خروج من جلسة البوابة. لو كل حملات الشركة موقوفة للبوابة دي (`isManagerActive` للبراند، `isActive && isAgencyActive` للعمليات) بتظهر `CampaignSuspendedScreen`.

**وضع البراند (`/portal/`)**: 0 التحليلات (`CampaignReportsScreen`) · 1 مقارنة الحملات (`CampaignsComparisonAnalyticsScreen`) · 2 الفواتير (`InvoicesLogScreen`) · 3 المبيعات اليومية (`DailyBranchSalesScreen`) · 4 أرصدة الفروع (`BranchStockBalancesScreen`، read-only) · 5 الفواتشر (`CompanyVouchersReportScreen`) · 6 محاكاة المندوب (نسخة حية من شاشة الرفع) · 7 مخزون الهدايا (`CompanyPrizesStockReportScreen`، read-only، TAG-79).

**وضع العمليات (`/ops/`, `/ep/`)**: 0 الفواتير · 1 أرصدة الفروع (قابلة للتعديل) · 2 الفواتشر · 3 المبيعات اليومية · 4 مخزون الهدايا (read-only، TAG-79؛ في `/ep/` مقفول على الحملة ومن غير سجل الحركات).

* **`BranchStockBalancesScreen`** — مصفوفة فرع × هدية بالمتبقي (`remainingQuantity`، ده اللي الصرف بيتحقق منه). العمليات تقدر تزوّد/تقلّل وتوزّع بالجملة وتحفظ (`updateBranchAllocations` على السيرفر)، و«تسوية نهاية الأسبوع» (تأرشف الموجة، المتبقي يتحسب مرتجع، ورصيد جديد) في `campaign_stock_settlements`. تصدير Excel. read-only للبراند.
* **`CampaignsComparisonAnalyticsScreen`** — مقارنة حملتين وجهًا لوجه (A ضد B بشارة القائد) وترتيب كل حملات الشركة، واكتشاف «موجات» نهاية الأسبوع جوه الحملة، وفترات مخصصة، وتصدير CSV. بيطابق الفواتير بالـ ID وبالاسم العربي المطبّع (أ/إ/آ، ة/ه، ى/ي).
* **`DailyBranchSalesScreen`** — مبيعات كل فرع لكل يوم وهدايا/فواتشر اتصرفت (مصفوفة + إجماليات + لوحة KPIs ومتصدرين)، اختيار التاريخ، تصدير Excel. بتطابق الهدية المصروفة مع الهدية الأم بالـ ID ثم الاسم المطبّع.
* **`CompanyVouchersReportScreen`** — الفواتشر حسب الفئة (25، 50، ...): المخصص والمصروف والمتبقي والقيمة، لكل حملة/فرع، ومصفوفة فرع × فئة، وتصدير Excel.

### 7.6 شاشات موجودة ومش متوصلة بالواجهة

`ValidationScreen` القديمة اتشالت (TAG-80)، و`CompanyPrizesStockReportScreen` بقت تبويب «مخزون الهدايا» في بوابة الشركة (TAG-79، شوف 7.5).

* **`MysteryBoxScreen`** — ديمو بس (شوف 7.3).

قبل ما تعدّل في أي واحدة من دول، اسأل الأول هل المطلوب نوصّلها ولا نشيلها.

---

## 8. Cloud Functions (`functions/`)

19 دالة منشورة. التفاصيل في `docs/05-cloud-functions.md`. كل الـ callables عليها `enforceAppCheck: true`، `us-central1`، 256MiB.

| الدالة | النوع | الدور |
|---|---|---|
| `geminiGenerate` | callable | بوابة Gemini الوحيدة (cache + rate limit 20/دقيقة و200/يوم لكل عميل + fallback موديلات) |
| `analyzeReceipt` | callable | تحليل فاتورة على السيرفر (WhatsApp/قديم) |
| `checkReceiptDuplicate` | callable | فحص التكرار عبر كل المستخدمين |
| `replaceReceipt` | callable | إعادة رفع فاتورة موجودة (المعتمدة مقفولة لغير الـ staff) |
| `logReceiptSaveFailure` | callable | تسجيل فشل الحفظ |
| `listBranchReceipts` | callable | فواتير الفرع للمندوب الـ anonymous |
| `decrementCampaignPrize` | callable | الصرف: أهلية (`campaign_eligibility.js`) + شرائح (`exclusive_/consuming_spend_ladder.js`) + خصم في transaction + ledger |
| `dryRunCampaignEligibility` | callable | «جرّب على فاتورة» من غير كتابة |
| `updateBranchAllocations` | callable | حفظ أرصدة الفروع والتسوية |
| `setUserRole` | callable | claims الأدوار (super_admin بس) |
| `partnerPortalInfo` / `partnerPortalLogin` | callable | بيانات البوابة العامة / الدخول وإصدار custom token |
| `sendWinnerWhatsApp` | callable | رسالة الفائز |
| `updateWhatsappWebhookConfig` / `manageWhatsappSenderLink` | callable | إعدادات الـ webhook وربط الأرقام |
| `sharePreview` | HTTP | صفحات OpenGraph |
| `wahaProxy` | HTTP | proxy لـ WAHA |
| `wahaWebhook` | HTTP عام (HMAC) | رسائل WhatsApp الواردة |
| `autoCloseExpiredCampaigns` | schedule `10 0 * * *` Africa/Cairo | قفل الحملات المنتهية |

* `security_functions.js` بيتدمج في `index.js` بـ `Object.assign` (وفيه كمان export عادي `applyCampaignPrizeClaim` للاختبارات، مش trigger).
* `env_config.js`: بيفرّق prod/dev من project id أو `TASHIL_ENV`. `functions/.env.tashil-gift-dev` فيه قيم dev غير السرية (`TASHIL_ENV`, `PUBLIC_SITE_ORIGIN`). الإنتاج مالوش ملف env عمدًا.

---

## 9. قواعد الأعمال اللي لازم تفضل صح (invariants)

1. **السيرفر هو المرجع** في الأهلية والمخزون. حسابات العميل للعرض بس. منطق الأهلية متكرر في `PromotionalRuleMatcher` (Dart) و`campaign_eligibility.js` (Node)؛ أي تغيير لازم يتعمل في الاتنين، وإلا العميل يشوف «كسبت» والسيرفر يرفض (TAG-67، TAG-69). الاتنين بيتختبروا على نفس الحالات في `test/fixtures/eligibility_parity.json` (TAG-72)؛ أي حالة جديدة تتضاف هناك.
2. **لا هدية بديلة:** لو الحملة ليها قواعد ومفيش قاعدة اتحققت، الفاتورة بتترفض بسبب واضح (AGENTS.md #10).
3. **`linkedGifts` نهائية:** ممنوع تتضرب تاني في عدد الفرص (AGENTS.md #6).
4. **سعر الوحدة** = صافي السطر ÷ الكمية، و`originalPrice` = الإجمالي ÷ الكمية (AGENTS.md #4).
5. **الحد الأدنى للإنفاق** بيتحسب على منتجات الحملة بس، مش إجمالي الفاتورة ولا براندات تانية لنفس الشركة (TAG-67).
6. **الـ AI** بـ `temperature: 0`، وفاتورة مش واضحة ← `isValid=false` بدل التخمين.
7. **الفروع:** فروع الحملة المعتمدة بس، مساواة على `canonical_branch`، شيل المحافظة بين القوسين قبل المقارنة، وممنوع فرعين في نفس المدينة يتجمّعوا (AGENTS.md #8).
8. **صرف واحد لكل فاتورة** (claim ledger على السيرفر). الـ ID الثابت `rcpt_{campaignId}_{receiptNo}` بيمنع التكرار.
9. **التواريخ** أيام كاملة بتوقيت القاهرة (`receipt_date_window.dart`).
10. **الأداء:** streams برّه `build()`، فلترة على السيرفر (`where('companySlug', ...)`)، كاش للمقاييس، وأي query مركّب ليه index في `firestore.indexes.json` (AGENTS.md #9).
11. **التصميم:** M3، اتجاه RTL/LTR طبيعي (القائمة يمين في العربي)، spacing مضاعفات 8، `M3ActionMenu` بدل `PopupMenuButton` (AGENTS.md #7، #12–#14).
12. **حجم مستند الحملة:** المنتجات والبرومبت الكبار في `events/{id}/content/` (حد 1MB للمستند). الـ rules بتاعة الفاتورة الـ anonymous صغيرة عمدًا عشان حد الـ 1000 expression.

---

## 10. التشغيل والاختبار والنشر

```bash
git checkout dev
fvm flutter pub get                   # Flutter 3.44.5 من .fvmrc
(cd functions && npm ci)              # Node 22

# تشغيل على dev (الأأمن مع بيانات وهمية)
fvm flutter run -d chrome --dart-define=APP_ENV=dev

# أو على الـ emulators
npx -y firebase-tools@15.37.0 emulators:start --project demo-tashil-branch --only auth,firestore
node tool/seed_branch_identity_emulator.mjs
fvm flutter run -d web-server --web-port 7357 --dart-define=FIREBASE_EMULATOR=true

# الاختبارات
fvm flutter analyze                               # baseline في tool/ci/analyze_baseline.txt
bash tool/ci/flutter_test.sh blocking             # كل الاختبارات ماعدا المعروف فشلها
bash tool/ci/flutter_test.sh known                # tool/ci/known_failing_tests.txt (مش بيوقّف الـ CI)
(cd functions && npm test)                        # unit tests للـ functions
(cd functions && npm run test:emulator)
(cd rules-tests && npm test)
python3 tool/ci/check_version.py
```

**تحذير:** `flutter run` من غير `APP_ENV=dev` بيشتغل على **الإنتاج** (`tashil-gift`).

**الفروع والنشر:**

```
feature branch ──PR──► dev ──(version PR)──► release PR ──► main ──► deploy-production (موافقة environment)
```

| Workflow | الحدث | النتيجة |
|---|---|---|
| `checks.yml` | بيتنادى من الباقي | فحص الإصدار، analyze، اختبارات Flutter وfunctions، build web |
| `dev-preview.yml` | PR أو push على `dev` | معاينة Hosting (`pr-N`، أو الموقع على `tashil-gift-dev`) |
| `dev-deploy.yml` | يدوي | نشر ref معيّن على `tashil-gift-dev` |
| `deploy-dev-backend.yml` | يدوي | functions وrules وindexes على dev |
| `deploy-production.yml` | push على `main` أو يدوي (rollback بـ `ref` و`allow_older_version`) | hosting + functions + firestore:rules على `tashil-gift` |

* الـ indexes ما بتتنشرش أوتوماتيك على الإنتاج (TAG-76).
* بيانات dev الوهمية: `tool/seed_dev.js` (أو push على `dev` فيه `[seed]` في رسالة الـ commit). التفاصيل في `docs/DEV_ENVIRONMENT.md`.
* بعد أي نشر مصرّح بيه اذكر: الإصدار (`v2.0.X (Build #N)`)، و https://console.firebase.google.com/project/tashil-gift/overview ، و https://tashil-gift.web.app (AGENTS.md #3).

---

## 11. الأسرار والإعدادات (أسماء بس، ما تكتبش قيم أبدًا)

| الاسم | فين | لإيه |
|---|---|---|
| `GEMINI_API_KEY` | Secret Manager (لكل مشروع) | Gemini |
| `WAHA_API_KEY` | Secret Manager | WAHA (dummy في dev) |
| `WAHA_WEBHOOK_SECRET` | Secret Manager | HMAC للـ webhook |
| `WAHA_BACKEND_URL` | env (افتراضي `https://waha.sw-point.com`) | عنوان WAHA |
| `TASHIL_ENV`, `PUBLIC_SITE_ORIGIN` | `functions/.env.tashil-gift-dev` | قيم dev غير سرية |
| `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT` | GitHub secret | نشر الإنتاج |
| `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT_DEV` | GitHub secret | نشر dev |
| `DEV_AUTO_DEPLOY_BACKEND`, `DISABLE_PROD_PREVIEW_FALLBACK` | GitHub variables | سلوك dev |
| `--dart-define=APP_ENV=dev` | build flag | يبني على `tashil-gift-dev` (أي قيمة غلط بترمي error) |
| `--dart-define=FIREBASE_EMULATOR=true` (+ `FIREBASE_EMULATOR_HOST`) | build flag | الـ emulators |

`lib/firebase_options*.dart` فيها web config عام (مش سر).

---

## 12. ملاحظات من المراجعة (2026-11-26)

الحاجات دي اتلاحظت أثناء المراجعة؛ اللي ليه تيكت مذكور رقمه. القائمة الكاملة في `docs/10-tech-debt-and-gaps.md`.

* **شاشات يتيمة:** `MysteryBoxScreen` ديمو بس (7.6). محتاج قرار: نوصّل ولا نشيل. (`ValidationScreen` اتشالت في TAG-80، و`CompanyPrizesStockReportScreen` اتوصلت في TAG-79.)
* ~~**رسالة «الحملة موقوفة» مضللة**~~: اتصلحت في TAG-81 (`CampaignLoadState`)؛ شاشة الإيقاف بتظهر بس للحملة الموقوفة فعلًا.
* **منطق الأهلية متكرر** في Dart وNode؛ عليه اختبار تطابق مشترك (TAG-72).
* **باسوردات البوابات نص صريح** في `companies` و`events` (TAG-70).
* **قراية anonymous واسعة** لـ `company_products` و`branches` و`retail_chains` (TAG-71).
* **ملفات ضخمة** صعب تتراجع (TAG-36 لصفحة الحملة).
* **`docs/07` و`docs/08`** لسه بيقولوا إن بيئة dev «لسه ما اتدمجتش»؛ هي اتدمجت وشغالة (Hosting + 19 function + rules + seed). الأوامر في القسم 10 هنا هي الحالية.
* فيه index لمجموعة `validation_transactions` مش مستخدمة في الكود (يتشال بعد التأكد إن المجموعة فاضية على الإنتاج). `get_it` اتشال (TAG-75).

---

## 13. فين تلاقي إيه بسرعة

| عايز تعدّل | ابدأ من |
|---|---|
| قراية الفاتورة / البرومبت | `lib/core/services/ai_receipt_service.dart` (+ directive جديد) |
| قواعد العرض والفرص (عميل) | `PromotionalRuleMatcher` في نفس الملف |
| الأهلية والصرف (سيرفر) | `functions/campaign_eligibility.js`, `functions/security_functions.js`, `*_spend_ladder.js` |
| مسار رفع الفاتورة | `client_receipt_upload_screen.dart` (`_submitAndValidateReceiptImpl`) |
| تحديد الفرع | `core/services/smart_branch_matcher_service.dart`, `core/utils/*branch*_resolver.dart` |
| موديل الحملة | `features/admin/domain/event_model.dart` |
| حفظ الحملة | `create_event_screen.dart` (`_saveEvent`), `features/admin/domain/campaign_edit_save.dart` |
| المخزون والصرف (عميل) | `core/services/company_gifts_service.dart` |
| دخول البوابات | `core/services/partner_portal_auth_service.dart`, `functions/partner_portal.js` |
| WhatsApp | `features/company_portal/domain/whatsapp_*`, `functions/waha_webhook.js`, `functions/winner_whatsapp.js` |
| الصلاحيات | `firestore.rules`, `storage.rules` (+ `rules-tests/`) |
| الـ routing | `lib/main.dart` (`_buildRouteForUri`) |
| النصوص | `lib/core/localization/app_strings.dart` |
| الموديلات | `lib/core/constants/ai_models.dart`, `functions/ai_models.js` |
