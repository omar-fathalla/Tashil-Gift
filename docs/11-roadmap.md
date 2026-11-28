# 11 — خطة التطوير (مربوطة بـ Linear)

الحالة من Linear يوم 2026-11-26 (فريق `TAG`). رتّبت الشغل لـ 4 مسارات بالأولوية.

## 1. شغال دلوقتي (خلّصه الأول)

| التيكت | الموضوع | الحالة |
|---|---|---|
| TAG-69 | حملة يونيليفر بترفض الرول اون اللي باركوده مش في كتالوج القاعدة | In Progress |
| TAG-43 | حفظ تعديل حملة «Hair back to school» (والفرعيات TAG-47، TAG-48، TAG-49) | In Progress |
| TAG-45 | شيل تحذيرات رصيد الهدايا من إنشاء/تعديل الحملة | In Progress |
| TAG-18 | التفعيل التلقائي للحملة يوم البداية (فرع `feat/tag18-auto-activate`) | In Review |
| TAG-68 | رسالة خطأ الدخول بتظهر «Error» بس | Todo |

## 2. أمان (Urgent / High)

| التيكت | الموضوع |
|---|---|
| TAG-33 | إلغاء مفاتيح الدخول لصور الفواتير المكشوفة في `tool/run_12_receipts_benchmark.py` (السكربت اتشال في TAG-83، والمفاتيح لسه في تاريخ git: [النسخة القديمة](https://github.com/omar-fathalla/Tashil-Gift/blob/2a018e3f191b30e2297198f4ed3ca1d282e923b9/tool/run_12_receipts_benchmark.py)) |
| TAG-20 | Required reviewer على environment `production` |
| TAG-21 | Branch protection على `main` و `dev` |
| TAG-10 | شيل المفاتيح المكتوبة في خدمات الـ AI (In Review) |
| TAG-70 | تشفير (hash) باسوردات البوابات |
| TAG-71 | مراجعة صلاحيات القراية للجلسات الـ anonymous |

## 3. بيئة التطوير (مشروع `P-TAG-16`)

M1 Firebase dev project ← M2 فصل الإعدادات ← M3 البيانات والـ rules ← M4 CI/CD ← M5 الاختبار والتحويل.

الحالة يوم 2026-11-26 (من الكود ومن تشغيلات GitHub Actions على PR #44):

| | الحالة |
|---|---|
| مشروع `tashil-gift-dev` و web app و config في الكود (TAG-3) | جاهز |
| Service account و GitHub secret للـ dev (TAG-16، TAG-19) | جاهزين فعليًا (معاينة `pr-44` اتنشرت على dev)، لكن التيكتات لسه Backlog |
| فصل الإعدادات في الكود (`APP_ENV`، functions env، seed، workflows) | جاهز على `feat/dev-environment` (PR #44)، ومش متدمج |
| Firestore/Storage rules و indexes على dev (TAG-12) | فشل: `403 The caller does not have permission` على Firebase Rules API. الـ service account ناقصه دور **Firebase Rules Admin** (أو الـ API مش متفعّل) |
| Cloud Functions على dev | ما اتنشرتش؛ محتاجة الـ secrets الأول (TAG-4). من غيرها قراية الفاتورة وصرف الهدية ما يشتغلوش على dev |
| App Check على dev | مش متأكد إن `DEV_APP_CHECK_RECAPTCHA_SITE_KEY` متحط؛ من غيره كل الـ callables بترفض |
| البيانات الوهمية (TAG-15) | محتاجة الـ rules والـ functions الأول |
| PR #44 | فيه تعارض بسيط في `web/version.json` مع `dev` بعد 2.0.191 |

بعد كده: TAG-24 (smoke tests)، TAG-26، TAG-27 (قرار التحويل)، TAG-22، TAG-5، TAG-6.

## 4. ديون تقنية ومنتج

| التيكت | الموضوع |
|---|---|
| TAG-63 → TAG-64 | نقل محتوى الحملات الموجودة لـ `content/` ثم إيقاف الحقول القديمة |
| TAG-65، TAG-66 | حد الحجم في المسودات و«جرّب على فاتورة» |
| TAG-35 | «نجاح كداب» في شاشات الشركات والسلاسل والمنتجات |
| TAG-36 | تقسيم صفحة إنشاء الحملة لخطوات |
| TAG-37 (38–42) | مؤجلات حفظ الحملة C-02 |
| TAG-34 | تعديل الكلام في لوحة الأدمن وكتالوج الهدايا |
| TAG-72 | اختبار تطابق الأهلية بين Dart و Cloud Functions |
| TAG-73 | إصلاح الـ 7 ملفات اختبار الفاشلة |
| TAG-74 | مراقبة وتنبيهات لفشل حفظ الفواتير وصرف الهدايا |
| TAG-75 | تنظيف الريبو وتصحيح AGENTS.md |
| TAG-76 | نشر Firestore indexes بخطوة محكومة |

## تنظيف Linear (اتعمل 2026-11-26)

* فرعيات TAG-51 و TAG-56 الملغيين (TAG-52..55، TAG-58..60) اتقفلت Duplicate لـ TAG-62/63/64.
