# 07 — تجهيز بيئة التطوير والتشغيل

## المتطلبات

| الأداة | الإصدار | منين |
|---|---|---|
| Flutter | **3.44.5** (stable) | `.fvmrc` — استخدم [FVM](https://fvm.app): `fvm install && fvm use` |
| Dart SDK | `^3.11.0` | مع Flutter |
| Node.js | **22** | `functions/package.json` (`engines`) |
| Firebase CLI | `firebase-tools` 15.x (الـ CI بيستخدم 15.37.0) | `npx -y firebase-tools@15.37.0` |
| Java | 21+ | للـ Firestore emulator |
| Chrome | أي إصدار حديث | التشغيل على الويب |

## أول مرة

```bash
git clone https://github.com/omar-fathalla/Tashil-Gift.git
cd Tashil-Gift
git checkout dev                 # الشغل كله بيبدأ من dev
fvm flutter pub get              # أو flutter pub get
(cd functions && npm ci)
(cd rules-tests && npm ci)       # لو هتشغّل اختبارات الـ rules
```

## التشغيل

> **تحذير:** التشغيل العادي (`flutter run`) بيتوصّل بمشروع الإنتاج `tashil-gift` مباشرة (Firestore و Functions و Storage حقيقيين). اشتغل على الـ emulators أو على بيئة `tashil-gift-dev` (`--dart-define=APP_ENV=dev`، شوف [DEV_ENVIRONMENT.md](DEV_ENVIRONMENT.md))، وما تعملش حملات تجربة على الإنتاج. خطوات التيست لكل إصدار: [templates/test-steps.md](templates/test-steps.md) (TAG-26).

### على الـ emulators (الأأمن)

```bash
# 1) شغّل الـ emulators بمشروع demo (الإنتاج بيرفض أي project id يبدأ بـ demo-)
npx -y firebase-tools@15.37.0 emulators:start --project demo-tashil-branch --only auth,firestore

# 2) بيانات تجربة (fixture فروع ومخزون)
node tool/seed_branch_identity_emulator.mjs

# 3) التطبيق موجّه للـ emulators
fvm flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357 \
  --dart-define=FIREBASE_EMULATOR=true
```

التفاصيل والحسابات في `tool/BRANCH_IDENTITY_FIXTURE.md`. الـ emulator host ممكن يتغيّر بـ `--dart-define=FIREBASE_EMULATOR_HOST=...`.

### على الإنتاج (قراية/معاينة بس)

```bash
fvm flutter run -d chrome --web-port 8080
```

فيه launch configs جاهزة في `.vscode/launch.json` (Chrome، web-server على 8080، auto device).

### بعد ما بيئة dev تتدمج (فرع `feat/dev-environment`)

الفرع ده بيضيف `APP_ENV` (`lib/core/config/app_env.dart`)، `firebase_options_dev.dart`، `functions/.env.tashil-gift-dev`، alias `dev` في `.firebaserc`، `tool/seed_dev.js` ببيانات وهمية، وفواتير نموذجية في `tool/dev_fixtures/receipts/`. الخطوات الكاملة هتبقى في `docs/DEV_ENVIRONMENT.md`. لما يتدمج، حدّث القسم ده.

## الاختبارات

### البوابة (TAG-82)

`bash tool/ci/run_gate.sh` بيشوف الملفات اللي اتغيرت عن `origin/dev` ويشغّل الأدوات اللي ليها علاقة بيها بس (الجدول في `tool/ci/gate_buckets.py` و `.claude/skills/test/SKILL.md`). `--all` للفول تيست، `--only <tool>` لأداة واحدة، `--dry-run` للخطة. النتيجة في `build/gate/SUMMARY.md`. أداة 4 محتاجة Java 21، وكل الـ emulators على `demo-*` من غير credentials.

| الأمر | بيختبر إيه | الحالة المعروفة |
|---|---|---|
| `fvm flutter analyze` | الـ lints | baseline: 14 info، 1 warning، 0 error (`tool/ci/analyze_baseline.txt`) |
| `bash tool/ci/flutter_test.sh blocking` | 196 ملف اختبار Flutter ماعدا القائمة المعروفة | 1061 نجح |
| `bash tool/ci/flutter_test.sh known` | 7 ملفات فاشلة معروفة (`tool/ci/known_failing_tests.txt`) | 14 فشل، مش بيوقّف الـ CI |
| `fvm flutter test test/<file>_test.dart` | ملف واحد | — |
| `(cd functions && npm test)` | 29 ملف unit للـ functions | 300 نجح، 0 فشل (2026-11-26) |
| `(cd functions && npm run test:emulator)` | functions على الـ emulators | — |
| `(cd rules-tests && npm test)` | firestore.rules و storage.rules | — |
| `python3 tool/ci/check_version.py` | تطابق الإصدار في الـ 3 ملفات | — |
| `python3 tool/ci/static_guards.py` | `--project` في أوامر firebase، اسم prod في السكربتات، الأسرار | 0 finding (الاستثناءات في `tool/ci/guards_allowlist.txt`) |
| `python3 -m unittest discover -s tool/ci -p 'test_*.py'` | اختبارات البوابة نفسها | 21 نجح |

القاعدة: لو اختبار فشل، أعِد تشغيل الملف ده بس لحد ما يتصلّح، مش الـ suite كلها.

## Build

```bash
fvm flutter build web --release      # الناتج في build/web (ده اللي Hosting بينشره)
```

## ممنوعات (من AGENTS.md و Linear)

* ممنوع `git push` أو `firebase deploy` من غير طلب صريح من محمد.
* ممنوع `firebase deploy` من جهاز محلي ومن غير `--force`؛ النشر عن طريق GitHub Actions بس.
* ممنوع نسخ بيانات عملاء حقيقية لأي بيئة تجربة.
* ممنوع الكتابة على Firestore الإنتاج من غير موافقة.

## أسرار وإعدادات

* العميل: `lib/firebase_options.dart` (web config عام، مش سر).
* السيرفر: `GEMINI_API_KEY`, `WAHA_API_KEY`, `WAHA_WEBHOOK_SECRET` في Secret Manager (`firebase functions:secrets:set NAME`).
* `WAHA_BACKEND_URL` (افتراضي `https://waha.sw-point.com`).
* GitHub secret: `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT` (النشر).
