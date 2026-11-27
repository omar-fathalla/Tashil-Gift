# 08 — الفروع، الـ CI/CD، والإصدارات

## الفروع

```
feature / fix branch  ──PR──►  dev  ──release PR──►  main  ──►  نشر الإنتاج
                         │              │
                 معاينة pr-<N>     معاينة قناة dev
```

* كل شغل جديد يبدأ من `dev` في فرع باسم واضح (`fix/tag-67-...`, `feat/tag18-...`) ورقم تيكت Linear في الاسم والـ commit.
* PR على `dev` ← بعد الدمج، PR «version X.Y.Z+N» يرفع الإصدار على `dev` ← PR «Release X.Y.Z+N (TAG-..)» من `dev` لـ `main`.
* الـ commits بتبدأ برقم التيكت: `TAG-67: stop other company products counting toward brand-scoped spend rules`.

## GitHub Actions (`.github/workflows/`)

| الحدث | الـ workflow | بيعمل إيه | بينشر |
|---|---|---|---|
| PR على `dev` | `dev-preview.yml` | `checks.yml` | Hosting preview `pr-<N>` (7 أيام) |
| push على `dev` | `dev-preview.yml` | `checks.yml` | Hosting preview قناة `dev` |
| PR أو push على `dev` | `gate.yml` (TAG-82) | `tool/ci/run_gate.sh --ci`: الـ static guards و rules/functions على الـ emulator، و Patrol web (job `patrol`) لو الـ UI أو الـ rules أو `patrol_test/` اتغيروا، حسب الملفات اللي اتغيرت | ولا حاجة |
| push على `main` | `deploy-production.yml` | `checks.yml` ثم موافقة environment `production` | `hosting,functions,firestore:rules` على `tashil-gift` |
| يدوي (rollback) | `deploy-production.yml` بـ `ref` و`allow_older_version` | `checks.yml` على الـ ref | نفس اللي فوق |

`checks.yml`: فحص الإصدار، `flutter analyze` (أخطاء أو warnings زيادة عن الـ baseline بتوقّف)، اختبارات Flutter (blocking + known-failing non-blocking)، `npm ci && npm test` للـ functions، `flutter build web --release`، ورفع الـ build كـ artifact عشان النشر يشيل نفس اللي اتختبر.

**مهم:** المعاينات (`pr-N` و `dev`) بتستخدم Firestore و Auth و Storage و Functions بتوع **الإنتاج**. مش بتنشر functions ولا rules. الـ indexes مش بتتنشر أوتوماتيك أبدًا، ومفيش `--force`.

## رفع الإصدار

الإصدار لازم يبقى متطابق في 3 أماكن (و`tool/ci/check_version.py` بيتأكد):

1. `lib/core/constants/app_version_config.dart`: `patch`, `buildNumber`, `releaseDate`.
2. `pubspec.yaml`: `version: 2.0.<patch>+<build>`.
3. `web/version.json`: `version`, `build_number`, `build_date`.

مع كل نشر: `patch + 1` و `buildNumber + 1`. الإنتاج بيرفض إصدار مش أحدث من `https://tashil-gift.web.app/version.json` إلا في الـ rollback. الـ CI عمره ما بيرفع الإصدار بنفسه.

الحالي: **2.0.191+251** (2026-11-26).

## Rollback

GitHub → Actions → `deploy-production` → Run workflow → `ref` = SHA أو tag قديم، و`allow_older_version = true`. أو من Firebase console → Hosting → Release history (ده بيرجّع الـ hosting بس).

## بعد أي نشر

اذكر في الرد:

* الإصدار: مثلًا `v2.0.191 (Build #251)`
* Firebase console: https://console.firebase.google.com/project/tashil-gift/overview
* التطبيق: https://tashil-gift.web.app

## Linear

* الحالات المستخدمة: Backlog → Todo → In Progress → In Review (PR) → Done (on prod) / Canceled.
* تيكتات الإصدار بعنوان `2.0.xxx — ...` وبتتقفل «Done (on prod)» بعد النشر.
* labels: `area:campaigns`, `area:claims`, `area:rules`, `area:functions`, `area:admin`, `area:ci`, `area:hosting`, `area:dev-env`، و`risk:low/medium/high`، والنوع `Bug`/`Feature`/`Improvement`/`Tech debt`/`Security`/`Infra/CI`/`Wording`.

## الخطة الجاية (مشروع Dev Environment `P-TAG-16`)

* المعاينات وقناة `dev` تتحوّل لمشروع `tashil-gift-dev` (TAG-23، TAG-27).
* required reviewer على environment `production` (TAG-20) و branch protection على `main` (TAG-21).
