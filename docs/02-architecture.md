# 02 — المعمارية وهيكل الكود

## الصورة الكبيرة

```
Flutter Web (lib/)  ──►  Firebase Auth (anonymous / email / custom token)
        │           ──►  Cloud Firestore (قراية مباشرة محكومة بـ firestore.rules)
        │           ──►  Cloud Storage (صور الفواتير واللوجوهات والهدايا)
        │           ──►  Cloud Functions callables (functions/, Node 22, us-central1)
        │                    ├─ geminiGenerate  ──► Gemini API (المفتاح في Secret Manager)
        │                    ├─ decrementCampaignPrize (صرف الهدية والتحقق من الأهلية)
        │                    └─ ... (شوف 05-cloud-functions.md)
        └── Firebase Hosting (build/web) + rewrites لـ sharePreview و wahaProxy
```

* كل الـ callables عليها `enforceAppCheck: true` (reCAPTCHA على الويب، `app_check_bootstrap.dart`).
* الـ Gemini API key مش موجود في العميل؛ كل الطلبات بتعدي على `geminiGenerate`.

## هيكل `lib/`

```
lib/
├── main.dart                 # تهيئة Firebase + App Check + جلسة anonymous + الـ routing كله
├── firebase_options.dart     # إعدادات Firebase (prod)
├── core/
│   ├── config/               # AiConfig (اختيار الموديل وقت التشغيل)
│   ├── constants/            # ai_models, app_version_config (الإصدار), country_currency_config
│   ├── services/             # منطق الأعمال: AI، الهدايا، الفروع، السلاسل، Firebase
│   ├── utils/                # حل الفروع، التواريخ، الأرقام العربي، الـ slugs، رفع الصور
│   ├── widgets/              # مكونات M3 مشتركة (scaffold، menus، list tiles...)
│   ├── theme/                # AppTheme + M3 tokens
│   ├── localization/         # app_strings.dart (~4000 سطر، ar/en/hi) + locale_provider
│   ├── animations/           # m3_motion
│   └── update/               # فحص وجود إصدار جديد وإعادة تحميل الصفحة
└── features/
    ├── admin/                # لوحة الأدمن، إنشاء/تعديل الحملات، الكتالوج، السلاسل، عقل الـ AI
    │   ├── data/             # campaign_content_repository (events/{id}/content)
    │   ├── domain/           # الموديلات (EventModel...) ومنطق الحفظ والمراجعة
    │   └── presentation/
    ├── auth/                 # دخول الأدمن ودخول بوابة الشركاء
    ├── client_portal/        # شاشة المندوب لرفع الفواتير
    ├── company_portal/       # بوابة البراند/العمليات + WhatsApp + التسويق
    │   └── domain/           # خدمات WhatsApp والمشرفين والمبيعات اليومية
    ├── games/                # العجلة، الكشط، الصندوق، اختيار الهدية، الهدية المباشرة
    └── validation/           # سجل الفواتير (invoices_log) وشاشة التحقق اليدوي
```

النمط تقريبًا feature-first مع `domain/` و `presentation/`، لكن معظم منطق الأعمال في `core/services/` مش جوه الـ features.

## أكبر الملفات (مهم تعرفها قبل التعديل)

| الملف | السطور |
|---|---|
| `features/admin/presentation/create_event_screen.dart` | ~10,200 |
| `features/validation/presentation/invoices_log_screen.dart` | ~8,500 |
| `core/services/ai_receipt_service.dart` | ~6,000 |
| `company_portal/presentation/company_prizes_stock_report_screen.dart` | ~5,800 |
| `company_portal/presentation/campaigns_comparison_analytics_screen.dart` | ~5,200 |
| `company_portal/presentation/company_customers_marketing_screen.dart` | ~5,000 |
| `client_portal/presentation/client_receipt_upload_screen.dart` | ~4,300 |
| `admin/presentation/company_catalog_screen.dart` | ~4,100 |

## الـ State و الـ DI

* **Riverpod** (`flutter_riverpod` 2.x): `ProviderScope` في `main.dart`. أهم الـ providers في `core/services/firebase_service.dart`:
  `firebaseAuthProvider`, `authStateStreamProvider`, `authClaimsProvider`, `isAdminProvider`, `isSuperAdminProvider`, `firestoreProvider`, `firebaseFunctionsProvider`, `firebaseStorageProvider`, `firebaseServiceProvider`.
* `get_it` موجود في `pubspec.yaml` لكن مش مستخدم في أي ملف تحت `lib/` (مرشّح للشيل).
* كتير من الشاشات `StatefulWidget` كبيرة بتعمل streams لـ Firestore بنفسها (القاعدة: الـ streams تتعمل برّه `build()`).

## Firebase scope (فصل جلسة البوابة عن جلسة المندوب)

`core/services/firebase_scope.dart`: روابط البوابات (`portal`, `p`, `company`, `ops`, `agency`, `operations`) بتشتغل على Firebase app منفصل اسمه `partner-portal`، عشان دخول/خروج البوابة ما يمسحش جلسة المندوب الـ anonymous في تاب تاني. الأدمن اللي داخل بالفعل بيفضل على الـ app الافتراضي. استخدم `scopedFunctions()` والـ providers بدل `FirebaseFirestore.instance` مباشرة في أي كود يتنادى من البوابة.

## Routing

`MyApp._buildRouteForUri` في `main.dart` بيحوّل أي URI (path نظيف أو `#` قديم) لشاشة واحدة (`onGenerateInitialRoutes` بيرجّع route واحد بس عشان الـ deep links ما تتفكّكش). الجدول الكامل في [01-overview.md](01-overview.md).

## التهيئة في `main.dart`

1. `Firebase.initializeApp` بـ timeout ومحاولة تانية (عشان الـ splash ما يعلّقش).
2. لو `--dart-define=FIREBASE_EMULATOR=true` بيتوصّل بالـ emulators.
3. `activateFirebaseAppCheck()`.
4. جلسة anonymous بس على الروابط العامة (`routeNeedsAnonymousSession`).
5. `FirebaseScope.init` للبوابات.

## Cloud Functions

مجلد `functions/` (CommonJS، Node 22، `firebase-functions` v7 gen2). كل الدوال في `index.js` أو بتتصدّر منه. الأسرار: `GEMINI_API_KEY`, `WAHA_API_KEY`, `WAHA_WEBHOOK_SECRET`. التفاصيل في [05-cloud-functions.md](05-cloud-functions.md).
