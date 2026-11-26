---
name: test
description: Test a change in Tashil Gift the agreed way (TAG-82). Picks only the gate tools the changed files need (analyze, flutter test, static guards, rules/functions on the emulator, Patrol web, Maestro) and ends with an Arabic report. Use when the user types /test or says "اعمل الاختبارات", "اختبر", "اعمل تست", "جرّب التعديل", "الفول تيست", or asks whether a branch or PR is ready.
---

# /test — بوابة الاختبار في Tashil Gift

كلّم محمد بالعربي المصري في كل رسالة. المصطلحات وأسماء الملفات والأوامر بالإنجليزي.

## القواعد

- مفيش تستات على الإنتاج `tashil-gift` خالص. الـ emulators بمشروع `demo-*` هي الأساس، و `tashil-gift-dev` لـ smoke صغير بس.
- أي أمر `firebase` لازم معاه `--project tashil-gift-dev` أو `--project demo-*`. الـ default في `.firebaserc` هو prod.
- مفيش push أو merge أو deploy أو كومنت على PR من غير موافقة محمد في الشات.
- ماتطبعش ولا تقرا أسرار: الـ service accounts، حسابات الـ seed (`dev-seed-credentials`)، `functions/.env*` غير الـ dev العام.
- ماتعدّلش `checks.yml` ولا `deploy-production.yml` ولا `tool/ci/guards_allowlist.txt` إلا لو محمد طلب.

## 0. إيه اللي هيتشغّل

البوابة بتختبر **commit**. لو فيه تعديلات مش متعملها commit، قول كده واسأل قبل ما تعمل commit.

```bash
git fetch origin dev
python3 tool/ci/gate_buckets.py --base origin/dev      # الـ buckets والأدوات
```

قول لمحمد في سطرين: الـ buckets، والأدوات اللي هتشتغل، والوقت التقريبي.
مش كل تعديل بيشغّل الـ6. الجدول في `tool/ci/gate_buckets.py`:

| Bucket | المسارات | الأدوات |
| --- | --- | --- |
| docs | `docs/**`، `*.md` | ولا حاجة |
| dart | `lib/**`، `test/**` | 1، 2 |
| ui | presentation، `lib/core/{widgets,theme,localization,services}/**`، `lib/main.dart`، `web/**`، `assets/**`، `firebase.json` | 1، 2، 6 (و 5 على الماك) |
| rules | `firestore.rules`، `storage.rules`، `firestore.indexes.json`، `rules-tests/**` | 4 rules، 6 |
| functions | `functions/**` | 4 functions |
| toolchain | `pubspec.*`، `.fvmrc`، `analysis_options.yaml`، `known_failing_tests.txt`، `analyze_baseline.txt` | 1، 2 |
| e2e | `maestro/**`، `patrol_test/**`، `integration_test/**` | 6 (و 5) |
| scripts | `tool/**`، `.github/**`، `firebase*.json`، `*.sh` | 3 |
| مش متصنّف | أي حاجة تانية | 1 لـ 4 |

الـ6 كلهم مرة واحدة بس لما محمد يطلب «الفول تيست» صراحة، أو قبل release من `dev` لـ `main`.

## 1. التشغيل

```bash
bash tool/ci/run_gate.sh                 # الأدوات اللي التعديل محتاجها
bash tool/ci/run_gate.sh --all           # الفول تيست
bash tool/ci/run_gate.sh --only rules    # أداة واحدة (لإعادة اللي فشل بس)
bash tool/ci/run_gate.sh --dry-run       # الخطة من غير تشغيل
```

النتيجة في `build/gate/SUMMARY.md` واللوجات جنبها. لو أداة فشلت، أعِد تشغيلها هي بس بـ `--only` لحد ما تتصلّح.

- **1 analyze**: `tool/ci/analyze.sh` مع الـ baseline. الـ infos مش بتوقّف، والـ errors والـ warnings الزيادة بتوقّف.
- **2 flutter test**: `tool/ci/flutter_test.sh blocking` ثم `known`. الملفات اللي في `known_failing_tests.txt` (TAG-73) مش بتوقّف. ماتنادي `flutter test` على الكل مباشرة.
- **3 static guards**: `tool/ci/static_guards.py` + الـ self-tests. قراية بس. لو لقى حاجة مقصودة، اسأل محمد قبل ما تضيفها للـ allowlist.
- **4 rules / functions**: `rules-tests` و `functions` (`npm test` و `npm run test:emulator`) على `demo-*` من غير credentials. محتاج Java 21. إصدار firebase-tools من `FIREBASE_TOOLS_VERSION` (الافتراضي 15.37.0).
  - لو الـ rules اتغيرت: شغّل نفس الاختبار على `git show origin/dev:firestore.rules` وعلى الجديد، وقارن. اللي التطبيق بيعمله لازم يفضل مسموح، والثغرة لازم تتقفل.
- **6 Patrol web** و **5 Maestro**: لسه متجهزوش (TAG-82 PR 2 و PR 3). البوابة بتقول «not set up yet». قول ده في التقرير وماتعتبروش نجاح.

في الـ CI: `.github/workflows/gate.yml` بيشغّل نفس السكربت بـ `--ci` على كل PR وكل push لـ `dev`. analyze و flutter test و functions unit بيشتغلوا في `checks.yml` أصلًا، فالـ gate بيعدّيهم.

## 2. التقرير (بالعربي)

جدول قصير: الأداة، النتيجة، الوقت، مكان اللوج. وبعده:
- اللي ماتغطاش، وإزاي اتأكدت منه بطريقة تانية؛
- الفشل المعروف اللي مش من التعديل ده (مثلًا ملفات TAG-73)؛
- الخطوة الجاية كسؤال (push؟ draft PR؟ ready؟).
