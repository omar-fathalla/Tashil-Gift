# بيئة التطوير (DEV) — `tashil-gift-dev`

الملف ده بيشرح بيئة التطوير المنفصلة عن الإنتاج: إزاي متقسّمة، والخطوات اللي لازم تتعمل من الـ console مرة واحدة، وإزاي نملا البيانات الوهمية ونجرّب.

> القاعدة الثابتة: **الإنتاج `tashil-gift` ما يتلمسش من بيئة التطوير.** مفيش `firebase deploy` من جهاز لأي مشروع، مفيش `--force`، مفيش indexes على الإنتاج، ومفيش بيانات عملاء حقيقية في dev.

مشروع Linear: **Tashil Gift — Dev Environment** (فريق `TAG`).

---

## 1. الشكل العام

| | الإنتاج (prod) | التطوير (dev) |
|---|---|---|
| Firebase project | `tashil-gift` | `tashil-gift-dev` |
| الموقع | https://tashil-gift.web.app | https://tashil-gift-dev.web.app |
| المعاينات | — | `https://tashil-gift-dev--pr-<N>-xxxx.web.app` |
| البناء | `flutter build web --release` (زي ما هو) | `flutter build web --release --dart-define=APP_ENV=dev` |
| `version.json` → `env` | `prod` | `dev` |
| علامة في الواجهة | مفيش | شريط **DEV** في الركن |
| GitHub secret للنشر | `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT` | `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT_DEV` |
| Workflow | `deploy-production.yml` (push على `main`) | `dev-preview.yml` (PR و push على `dev`) و `dev-deploy.yml` (يدوي) |
| البيانات | حقيقية | وهمية من `tool/seed_dev.js` |
| Firestore | `me-central1` | `eur3` (اتعمل كده ومش هيتغير. الفرق بيأثر على السرعة بس، مش على الـ rules أو الكود) |
| Functions | `us-central1` | `us-central1` |

### الملفات المهمة

| الملف | دوره |
|---|---|
| `.firebaserc` | aliases: `default` و `prod` = `tashil-gift`، و `dev` = `tashil-gift-dev`. الـ default فضل prod، والـ CI دايمًا بيكتب `--project` صريح. |
| `lib/core/config/app_env.dart` | قراءة `APP_ENV` (الافتراضي prod). أي قيمة غلط زي `dve` بتوقف التطبيق بدل ما يشتغل على الإنتاج. |
| `lib/firebase_options_dev.dart` | إعدادات Firebase بتاعة dev. فيها الـ config الحقيقي بتاع الـ web app `tashil-gift-dev-web` (خطوة 5). لو أي قيمة رجعت `TODO_`، نسخة dev بتقف وما بتكلمش الإنتاج. |
| `lib/core/config/firebase_env_options.dart` | بيختار الإعدادات حسب البيئة. نسخة dev من غير إعدادات بتعرض رسالة وما بتكلمش الإنتاج أبدًا. |
| `lib/core/widgets/env_badge.dart` | شريط DEV. |
| `functions/env_config.js` | القيم اللي بتختلف بين البيئتين في Functions (رابط الموقع، الـ origins المسموحة للـ WAHA proxy). الإنتاج بيستخدم نفس القيم القديمة بالظبط. |
| `functions/.env.tashil-gift-dev` | قيم dev (مش secrets). بيتقري تلقائي مع `--project tashil-gift-dev`. |
| `tool/dev/render_firebase_dev_json.py` | بيعمل `firebase.dev.json` (gitignored) من `firebase.json` بـ Storage bucket بتاع dev، لأن `firebase.json` مثبّت على bucket الإنتاج. |
| `tool/dev/deploy_dev.sh` | النشر على dev بس (rules و indexes و storage و functions و hosting). بيرفض أي credentials مش بتاعة `tashil-gift-dev`. |
| `tool/seed_dev.js` و `tool/seed_dev_lib.js` | البيانات الوهمية. بيرفض يشتغل على أي مشروع غير `tashil-gift-dev` أو emulator `demo-*`. |
| `tool/dev_fixtures/receipts/` | 6 صور فواتير مصنوعة (`generate_receipts.py`). |
| `.github/workflows/dev-preview.yml` | معاينات الـ PR وموقع dev. |
| `.github/workflows/dev-deploy.yml` | نشر يدوي كامل على dev. |

### المفتاح المكشوف في ملفات الـ AI (TAG-10)

الـ 4 ملفات `ai_receipt_service.dart` و `campaign_ai_assistant_service.dart` و `branch_signature_ai_service.dart` و `ai_product_catalog_service.dart` (في `lib/core/services/`) كان فيهم مفتاح Google مكتوب ثابت من الإصدار 2.0.5، واتشال في 2.0.6. دلوقتي كل نداءات Gemini بتعدّي على Cloud Function `geminiGenerate`، وهي بتقرا `GEMINI_API_KEY` من Secret Manager بتاع كل مشروع، يعني dev و prod كل واحد بمفتاحه.

المفتاح اللي كان مكتوب هو نفسه **Browser API key بتاع Firebase في الإنتاج** (الموجود في `lib/firebase_options.dart`)، ولسه موجود في تاريخ الريبو. الاختبار `test/no_hardcoded_api_keys_test.dart` بيمنع أي مفتاح يرجع. المطلوب منك في خطوة 10 تحت.

---

## 2. اللي لازم تعمله من الـ console (مرة واحدة)

الخطوات دي محتاجة حسابك وخطة الدفع، وأنا ما بعملهاش.

### خطوة 1 — إنشاء المشروع (TAG-1)
1. افتح https://console.firebase.google.com/ ← **Add project** ← الاسم `tashil-gift-dev`. خلي الـ Project ID بالظبط `tashil-gift-dev`.
2. فعّل خطة **Blaze**، لأنها مطلوبة لـ Cloud Functions و Secret Manager: https://console.firebase.google.com/project/tashil-gift-dev/usage/details
3. اعمل Budget alert صغير (مثلًا 5$): https://console.cloud.google.com/billing/budgets

### خطوة 2 — تشغيل الخدمات (TAG-2)
1. **Authentication** ← Sign-in method ← فعّل **Email/Password** و **Anonymous**، لأن المناديب بيدخلوا Anonymous:
   https://console.firebase.google.com/project/tashil-gift-dev/authentication/providers
2. **Firestore** ← Create database ← Native mode ← المنطقة **`me-central1`**، نفس الإنتاج، ومش هتتغير بعد كده:
   https://console.firebase.google.com/project/tashil-gift-dev/firestore
3. **Storage** ← Get started، وخليه في نفس منطقة الإنتاج. الـ bucket المتوقع هو `tashil-gift-dev.firebasestorage.app`، ولو اسمه طلع مختلف قولي:
   https://console.firebase.google.com/project/tashil-gift-dev/storage
4. **Functions**: هتشتغل مع أول نشر. لو طلب تفعيل APIs، فعّل Cloud Build و Artifact Registry و Cloud Run و Cloud Scheduler و Secret Manager و Eventarc:
   https://console.cloud.google.com/apis/library?project=tashil-gift-dev

### خطوة 3 — App Check (للـ callables)
الـ Functions بتطلب App Check (`enforceAppCheck: true`)، ومفتاح reCAPTCHA بتاع الإنتاج مش هيشتغل على dev.
1. اعمل مفتاح reCAPTCHA Enterprise للدومين `tashil-gift-dev.web.app`: https://console.cloud.google.com/security/recaptcha?project=tashil-gift-dev
2. سجّله في App Check للـ web app: https://console.firebase.google.com/project/tashil-gift-dev/appcheck
3. حط الـ site key (مش secret) كـ GitHub **variable** اسمه `DEV_APP_CHECK_RECAPTCHA_SITE_KEY`:
   https://github.com/omar-fathalla/Tashil-Gift/settings/variables/actions

### خطوة 4 — Secrets في Secret Manager (TAG-4)
Functions بتعرّف 3 secrets، والنشر بيفشل لو أي واحد مش موجود. استخدم **مفاتيح منفصلة للتطوير**، مش مفاتيح الإنتاج:

| Secret | القيمة في dev |
|---|---|
| `GEMINI_API_KEY` | مفتاح Gemini جديد للتطوير بحد استخدام قليل (https://aistudio.google.com/apikey) |
| `WAHA_API_KEY` | قيمة وهمية زي `dev-disabled`، عشان الواتساب يقفل في dev. **ممنوع** نستخدم جلسة واتساب الإنتاج، لأنها هتبعت رسايل لعملاء حقيقيين. |
| `WAHA_WEBHOOK_SECRET` | أي قيمة عشوائية |

https://console.cloud.google.com/security/secret-manager?project=tashil-gift-dev

### خطوة 5 — تسجيل Web app وإرسال الـ config (TAG-3)
1. Project settings ← Your apps ← **Add app** ← Web، وسمّيه `Tashil Gift DEV`:
   https://console.firebase.google.com/project/tashil-gift-dev/settings/general
2. انسخ `firebaseConfig` (apiKey و appId و messagingSenderId) وابعتهولي. الـ web config مش secret، وأنا هحطه في `lib/firebase_options_dev.dart` مكان الـ `TODO_` في PR صغير.

> ✅ اتعملت يوم 2026-11-25: الـ web app اسمه `tashil-gift-dev-web` (appId `1:871169518648:web:0ef2437d5b7183e299cacd`)، والقيم متحطوطة في `lib/firebase_options_dev.dart`.

### خطوة 6 — Authorized domains و Browser key (TAG-5 و TAG-6)
1. Authentication ← Settings ← Authorized domains: لازم يكون فيها `tashil-gift-dev.web.app` و `tashil-gift-dev.firebaseapp.com` و `localhost`:
   https://console.firebase.google.com/project/tashil-gift-dev/authentication/settings
2. قيّد الـ Browser key بتاع dev: https://console.cloud.google.com/apis/credentials?project=tashil-gift-dev
   * **Website restrictions**: `https://tashil-gift-dev.web.app/*` و `https://tashil-gift-dev.firebaseapp.com/*` و `http://localhost/*`، ورابط كل معاينة `https://tashil-gift-dev--pr-<N>-xxxx.web.app/*` زي ما كنا بنعمل في الإنتاج.
   * **API restrictions**: Identity Toolkit و Token Service و Cloud Firestore و Firebase Storage و Firebase Installations و Firebase App Check و Cloud Functions، ومن غير Generative Language API.

### خطوة 7 — Service account للنشر (TAG-16)
1. IAM ← Service accounts ← Create، والاسم `github-deployer-dev`:
   https://console.cloud.google.com/iam-admin/serviceaccounts?project=tashil-gift-dev
2. اديله **نفس أدوار** `github-deployer` في الإنتاج. تقدر تشوفها هنا: https://console.cloud.google.com/iam-admin/iam?project=tashil-gift
   ولو محتاج قائمة، دي الأدوار المعتادة للنشر:
   Firebase Hosting Admin، Cloud Functions Admin، Service Account User، Firebase Rules Admin، Cloud Datastore Index Admin، Secret Manager Viewer، Cloud Scheduler Admin، Artifact Registry Administrator، Cloud Build Editor، Service Usage Consumer، Firebase Extensions Viewer.
3. Keys ← Add key ← JSON. **ما تبعتش الملف في الشات.**

### خطوة 8 — GitHub secret (TAG-19)
https://github.com/omar-fathalla/Tashil-Gift/settings/secrets/actions ← **New repository secret**
* الاسم: `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT_DEV`
* القيمة: محتوى ملف JSON بتاع `github-deployer-dev`، وبعدها امسح الملف من جهازك.

الـ CI بيرفض المفتاح لو `project_id` فيه مش `tashil-gift-dev`.

### خطوة 9 (اختياري) — متغيرات GitHub
https://github.com/omar-fathalla/Tashil-Gift/settings/variables/actions
* `DEV_AUTO_DEPLOY_BACKEND=true`: كل push على `dev` ينشر functions و rules و indexes على dev كمان، مش Hosting بس.
* `DISABLE_PROD_PREVIEW_FALLBACK=true`: يقفل المعاينات القديمة اللي على الإنتاج (قرار TAG-27).

### خطوة 10 — المفتاح القديم (TAG-10)
المفتاح اللي كان مكتوب في ملفات الـ AI لسه في تاريخ الريبو، وهو Browser key بتاع الإنتاج:
1. افتح https://console.cloud.google.com/apis/credentials?project=tashil-gift ← Browser key.
2. تحت API restrictions، اتأكد إن **Generative Language API مش موجودة** في القائمة. كده المفتاح المكشوف ما ينفعش يستخدم Gemini على حسابك.
3. لو حابب تعمل rotate كامل، ده محتاج PR يغيّر `lib/firebase_options.dart` ونشر على الإنتاج بموافقتك، فبنعمله في تيكت لوحده.

---

## 3. بعد الخطوات دي: النشر الأول على dev

1. أنا هحط الـ web config (خطوة 5) في PR صغير على `dev`.
2. **Actions ← dev-deploy ← Run workflow**، وخلي `ref = dev` و `what = all`:
   https://github.com/omar-fathalla/Tashil-Gift/actions/workflows/dev-deploy.yml
   ده بينشر الموقع و Functions و Firestore rules و indexes و Storage rules على `tashil-gift-dev` بس (TAG-12). الـ indexes على dev آمنة، وبتبيّن الفرق عن الإنتاج.
3. من ساعتها:
   * كل PR على `dev` بياخد معاينة `pr-<N>` على `tashil-gift-dev`، وتعليق فيه الرابط في الـ PR.
   * كل push على `dev` بيحدّث https://tashil-gift-dev.web.app.

**لحد ما الـ secret والـ config يبقوا جاهزين**، `dev-preview.yml` بيتخطى نشر dev (ملاحظة في الـ summary، من غير ما يفشل)، والمعاينات بتفضل زي النهارده على مشروع الإنتاج، Hosting بس.

---

## 4. البيانات الوهمية (TAG-13 و TAG-14 و TAG-15)

`tool/seed_dev.js` بيعمل:
* **شركتين**: `devco-choco` و `devco-clean`، ومعاهم حسابات بوابة الشركة: Brand `/portal/<slug>` و Agency `/ops/<slug>`.
* **سلسلتين و3 فروع**: `dev-chain-a_101` و `dev-chain-a_102` و `dev-chain-b_201`، والأخير مش في الحملة.
* **4 منتجات** بباركود يبدأ بـ `999`، و**3 هدايا** فيها «كارت مشتريات 100 جنيه (تجربة)».
* **4 حملات**: شغالة، موقوفة، تبدأ بكرة، وخلصت. وكمان مسودة في `event_drafts`.
* **أدمن تجربة**: `dev-admin@example.com` بدور `super_admin`.
* **المندوب**: بيدخل Anonymous من رابط الحملة، والسكربت بيطبع الروابط.
* **6 صور فواتير** بتترفع على `gs://tashil-gift-dev.firebasestorage.app/dev_fixtures/receipts/`.

### الحماية
السكربت **بيرفض** يشتغل في الحالات دي:
* من غير `--project`، أو لو المشروع `tashil-gift` أو أي مشروع غير `tashil-gift-dev` أو `demo-*`.
* لو `GCLOUD_PROJECT` أو ملف الـ credentials بيشاوروا على مشروع تاني.
* على `tashil-gift-dev` من غير `--confirm tashil-gift-dev`.
* على `demo-*` من غير emulators على localhost.

### التشغيل
```bash
cd functions && npm ci && cd ..
# 1) شوف الخطة من غير كتابة
node tool/seed_dev.js --project tashil-gift-dev --dry-run
# 2) على dev (مفتاح service account بتاع tashil-gift-dev بس، بدور Firebase Admin)
GOOGLE_APPLICATION_CREDENTIALS=~/keys/tashil-gift-dev-seeder.json \
  node tool/seed_dev.js --project tashil-gift-dev --confirm tashil-gift-dev
# 3) أو على الـ emulators المحلية
npx -y firebase-tools@15.37.0 emulators:exec --project demo-tashil-dev --only firestore,auth,storage \
  "node tool/seed_dev.js --project demo-tashil-dev"
```
* السكربت بيطبع كلمات السر الجديدة **مرة واحدة بس**. احفظها في مدير كلمات السر، مش في الريبو ولا في التيكت.
* تقدر تشغله أكتر من مرة، لأن الـ ids ثابتة والكتابة merge، وكلمات السر الموجودة ما بتتغيرش.
* بعد أول دخول للأدمن، اعمل sign out وادخل تاني عشان الـ claim يتفعّل.

### صور الفواتير والمتوقع منها
| الملف | السيناريو | المتوقع |
|---|---|---|
| `01_valid_chain_a_branch_101.png` | فاتورة سليمة من فرع 101، ومشتريات الشركة 249.50 | مقبولة وتاخد هدية، والمخزون يقل 1 |
| `02_duplicate_of_01.png` | نفس الفاتورة متصوّرة تاني | مرفوضة لأنها مكررة |
| `03_other_branch_chain_b_201.png` | فرع مش في الحملة | مرفوضة (الفرع) |
| `04_below_min_spend.png` | أقل من 150 | مرفوضة (الحد الأدنى) |
| `05_blurry_unreadable.png` | مش واضحة | رسالة واضحة إن الصورة مش مقروءة |
| `06_not_a_receipt.png` | مش فاتورة | رسالة «مش فاتورة» من غير أكواد |

---

## 5. مسار الإصدار والحالات في Linear

PR على `dev` ← معاينة على dev ← دمج في `dev` ← تجربة على https://tashil-gift-dev.web.app ← موافقة محمد ← PR من `dev` لـ `main` ← `deploy-production.yml` ينشر على الإنتاج.

| الحالة | معناها |
|---|---|
| In Progress | الشغل بدأ |
| In Review (PR) | الـ PR مفتوح ومعاه معاينة |
| On Dev | اتدمج في `dev` واتنشر على dev |
| Testing | محمد بيجرّب على dev |
| Ready for Prod | اتوافق عليه وجاهز للإنتاج |
| Done (on prod) | اتنشر على الإنتاج |

الـ rollback في الإنتاج: Actions ← deploy-production ← Run workflow، ونكتب `ref` = الـ SHA القديم، و `allow_older_version = true`.

---

## 6. ملحوظات
* `deploy-production.yml` بيبني prod بس، وبيرفض build الـ `env` بتاعه مش `prod`، وبيرفض لو الـ secret بتاع الإنتاج فيه مفتاح `tashil-gift-dev`. وما يعرفش أي secret بتاع dev.
* النسخة dev على الويب بس حاليًا. Android و iOS بيفضلوا على الإنتاج.
* `functions/scripts/bootstrap-super-admin.js` و `shared_pool_report.js` سكربتات محلية قديمة بتشاور على الإنتاج افتراضيًا. ما تشغلهمش إلا بـ `GCLOUD_PROJECT=tashil-gift-dev`.
