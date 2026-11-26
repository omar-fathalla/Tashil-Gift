# 09 — قواعد الكود والتصميم (ملخّص)

المرجع الكامل `AGENTS.md` (أي تعارض: `AGENTS.md` هو اللي يمشي) وتفاصيل كل قاعدة في `.agents/skills/<name>/SKILL.md`. ده ملخّص سريع.

## العمليات

* ممنوع push أو deploy من غير طلب صريح (`ارفع على جيت هب`، `اعمل deploy`...).
* أي نشر = رفع `patch` و `buildNumber` في الـ 3 ملفات ([08](08-ci-cd-and-release.md)).
* شغّل `flutter analyze` والاختبارات المتأثرة قبل الـ PR.

## منطق الأعمال

| القاعدة | الخلاصة | Skill |
|---|---|---|
| اقتصاديات الوحدة | `price` = صافي السطر ÷ الكمية؛ `originalPrice` = الإجمالي ÷ الكمية؛ الفروع تتجمّع على السلسلة الأم (`normalizeRetailChain`) | `retail-price-intelligence-standard` |
| قواعد العروض | `matchAllWithMultipliers` بيرجّع كميات نهائية؛ ممنوع تتضرب تاني في أي شاشة | `promotional-rules-single-resolution-standard` |
| فروع الحملة | الفلاتر تعرض فروع الحملة بس؛ شيل المحافظة بين القوسين قبل المقارنة؛ الفلترة بالمساواة على `canonical_branch` | `campaign-branch-resolution-standard` |
| صرامة الـ AI | `temperature: 0`، رفض الصور المش واضحة، مفيش هدية بديلة | `strict-receipt-ai-verification-standard` |
| عقل الـ AI | أي heuristic جديد = directive `AIR-XX` جديد | `continuous-ai-directives-standard` |
| التكرار | ID ثابت للفاتورة وفحص على السيرفر | `data-deduplication-and-integrity-standard` |
| الأرقام العربي | توحيد ٠-٩ و ۰-۹ قبل أي parsing | `arabic-numerals-normalization` |
| الفورمز | حفظ بتأكيد من السيرفر، مفيش «نجاح كداب» | `flutter-form-submission-standard` |

## الأداء و Firestore

* التابات lazy (`_loadedTabs` + `Offstage` + `TickerMode`)، مش `IndexedStack` بيحمّل كله.
* الـ streams تتعمل برّه `build()` (`didChangeDependencies` أو `_ensureStreams`).
* الفلترة على السيرفر (`where('companySlug'...)`) قبل الـ stream.
* الحسابات التقيلة memoized بمفتاح cache، والـ snapshot الفاضي ما يمسحش الأرقام.
* أي استعلام مركّب لازم index في `firestore.indexes.json`.
* توحيد العربي (`أ/إ/آ ← ا`, `ة ← ه`, `ى ← ي`) في المطابقة.
* Pagination: `pagination-infinite-scroll-standard`.

## التصميم (Material 3)

* Breakpoints الرسمية الخمسة (`M3WindowSizeClass`): <600، 600–839، 840–1199، 1200–1599، ≥1600.
* الملاحة: drawer/bottom bar على الموبايل، rail 72dp على المتوسط، sidebar 230–275dp على الكبير. الـ sidebar أول child في الـ `Row` (يمين في العربي، شمال في الإنجليزي والهندي).
* `EdgeInsetsDirectional` و `BorderDirectional` دايمًا.
* المسافات مضاعفات 8dp (`M3Spacing`)، والمحتوى جوه `M3ContentBoundary` (max 1360dp).
* القوايم: `M3ListTile` بارتفاعات 56/72/88، فواصل `M3InsetDivider` 72dp، أهداف لمس 48dp.
* القوايم المنسدلة: `M3ActionMenu` (مبني على `MenuAnchor`)؛ `PopupMenuButton` ممنوع. الأفعال الخطرة `isDestructive: true`.
* Progress و tooltips و motion: `material-design-3-progress-indicators`, `material-design-3-tooltips-affordance`, `material-motion`.
* الخط Cairo (google_fonts).

## اللغات

* كل نص في `core/localization/app_strings.dart` (`AppStrings.of(ref)`، `isAr`)، بالعربي والإنجليزي والهندي.
* كلام الواجهة عربي بسيط (C-06). أسماء الهدايا المخزّنة ما بتتغيّرش (السيرفر بيطابق على كلمة «فواتشر»)، والعرض بس بيتحوّل لـ «كارت مشتريات» عن طريق `CampaignWording.giftLabel`. باقي الشاشات في TAG-34.

## Commits و PRs

* الفرع والـ commit فيهم رقم التيكت: `TAG-67: ...`.
* PR على `dev`، وصف فيه المشكلة والحل والاختبارات.
