# 10 — النواقص والمخاطر المعروفة

اتجمعت من قراية الكود يوم 2026-11-26 ومقارنتها بتيكتات Linear. اللي ليه تيكت مكتوب رقمه؛ والخطة في [11-roadmap.md](11-roadmap.md).

## أمان

| البند | التفاصيل | Linear |
|---|---|---|
| بيئة التطوير لسه مش شغالة كاملة | المشروع `tashil-gift-dev` موجود، لكن الـ rules والـ functions ما اتنشروش عليه، والمعاينات على `dev` لسه على backend الإنتاج لحد ما PR #44 يتدمج (التفاصيل في 11-roadmap.md) | مشروع `P-TAG-16` |
| النشر على الإنتاج من غير موافقة إجبارية | أي push على `main` بينشر | TAG-20، TAG-21 |
| روابط فواتير مكشوفة في سكربت benchmark | السكربت اتشال في TAG-83، لكن الروابط ومفاتيحها لسه في تاريخ git ([النسخة القديمة](https://github.com/omar-fathalla/Tashil-Gift/blob/2a018e3f191b30e2297198f4ed3ca1d282e923b9/tool/run_12_receipts_benchmark.py)) ولازم الـ tokens تتلغي في Storage | TAG-33 (Urgent) |
| مفاتيح مكتوبة في كود خدمات الـ AI | — | TAG-10 |
| بيانات مشرفين حقيقية في الريبو | `tool/seeds/company-supervisors.xlsx` و `test/company_supervisor_import_test.dart` فيهم أسماء وأرقام موبايل شكلها حقيقية، والريبو public. المطلوب: التست يبني workbook وهمي في الذاكرة، والملف يتشال، ومحمد يقرر هنعمل إيه في تاريخ git | follow-up (Security) |
| باسوردات البوابات نص صريح | `companies/*` و `events/*` (`customAgencyPassword`) فيها باسوردات البوابات من غير hash. الـ rules بتقصرها على الأدمن والـ callable ما بيرجّعهاش، لكن أي تسريب لصلاحية أدمن أو backup بيكشفها | TAG-70 |
| قراية anonymous واسعة | أي جلسة anonymous (أي حد فتح رابط حملة) تقدر تقرا `company_products` لكل الشركات، و`branches` و`retail_chains` كلها | TAG-71 |
| CSP فيها `unsafe-eval` و `unsafe-inline` | غالبًا لازمين لـ Flutter web، محتاج تأكيد | — |

## جودة الكود

| البند | التفاصيل | Linear |
|---|---|---|
| ملفات ضخمة | `create_event_screen.dart` ~10 آلاف سطر، `invoices_log_screen.dart` ~8.5 ألف، `ai_receipt_service.dart` ~6 آلاف. صعب تتراجع وتتختبر | TAG-36 (تقسيم صفحة الحملة)، الباقي لسه |
| منطق الأهلية متكرر في مكانين | `PromotionalRuleMatcher` (Dart، للعرض) و `campaign_eligibility.js` (السيرفر، المرجع). أي اختلاف بينهم = العميل يشوف «كسبت» والسيرفر يرفض (زي TAG-67 و TAG-69) | TAG-72 |
| 7 ملفات اختبار فاشلة (14 اختبار) | `tool/ci/known_failing_tests.txt`، مش بتوقّف الـ CI | TAG-73 |
| نقل المحتوى لـ `content/` لسه ناقص | مراحل 2 و 3، والمسودات و«جرّب على فاتورة» بيعدّوا حد الحجم | TAG-63، TAG-64، TAG-65، TAG-66 |
| «نجاح كداب» بعد مهلة الحفظ في شاشات تانية | الشركات والسلاسل والمنتجات | TAG-35 |
| مؤجلات C-02 | حفظ الحملة من السيرفر مع `stockRev`، legacy tally، تنظيف `linkedGifts`، نقل الفرع | TAG-37 → TAG-38..42 |
| تيكتات مكررة في Linear | TAG-51 و TAG-56 (اتلغوا) وفيه تيكتات تحتهم لسه Todo/In Progress (TAG-52..55، TAG-58..60) | اتقفلت Duplicate (2026-11-26) |

## نظافة الريبو (TAG-75)

* `README.md` لسه قالب Flutter الافتراضي، و`pubspec.yaml` اسمه `al_mraay` ووصفه «A new Flutter project.» (تغيير الاسم بيغيّر كل الـ imports، فالأسهل نسيبه ونوثّقه).
* ~~`get_it` في الـ dependencies ومش مستخدم~~: اتشال (TAG-75).
* ~~ملفات خطط في الجذر~~: اتنقلت لـ `docs/plans/` و`docs/backups/` (TAG-75).
* `AGENTS.md` و `GEMINI.md` نسختين متطابقتين يدوي (أي تعديل لازم يتعمل في الاتنين)، وفيهم مسارات محلية `file:///Users/fathalla/...`.
* `AGENTS.md` القاعدة 5 بتقول المفتاح في `AiConfig.geminiApiKey`، بينما الكود الحالي بيمنع أي مفتاح في العميل وبيعدّي كله على `geminiGenerate`. القاعدة محتاجة تتصحّح.
* `firestore.indexes.json` فيه index لمجموعة `validation_transactions` مش مستخدمة.
* `.claude/skills` و `.agents/skills` فيهم skills Firebase عامة متكررة.

## تشغيل ومراقبة

* مفيش مراقبة أخطاء للويب (Crashlytics مش بيدعم Flutter web). فيه بس `logReceiptSaveFailure` و `recordClaimFailure` في Firestore. مفيش تنبيه لو نسبة فشل الصرف زادت (TAG-74).
* الـ Firestore indexes بتتنشر يدوي (الـ CI مش بينشرها عمدًا). محتاج خطوة محكومة (TAG-76).
* مجلدات `android/` و `ios/` موجودة ومش بتتبني في الـ CI. محتاج قرار: نسيبهم ولا نشيلهم.
