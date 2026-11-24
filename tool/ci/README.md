# CI / deploy (GitHub Actions)

| Trigger | Workflow | What runs | Deploys |
|---|---|---|---|
| PR into `dev` | `dev-preview.yml` | `checks.yml` | Hosting preview channel `pr-<N>` (7 days) |
| push to `dev` (merged PR) | `dev-preview.yml` | `checks.yml` | Hosting preview channel `dev` (7 days) |
| push to `main` | `deploy-production.yml` | `checks.yml` | after the `production` environment approval: `hosting,functions,firestore:rules` |
| manual (rollback) | `deploy-production.yml` (`ref`, `allow_older_version`) | `checks.yml` on that ref | same as above, for that ref |

Preview channels only carry Hosting files. They use the **production**
Firestore, Auth, Storage and Cloud Functions of `tashil-gift`.

`checks.yml`: version check, `flutter analyze` (infos never fail; errors and
warnings above `analyze_baseline.txt` do), Flutter tests (blocking: every
file not in `known_failing_tests.txt`; the listed files run non-blocking),
`functions` `npm ci` + `npm test` on Node 22, `flutter build web --release`,
and the built `version.json` must equal the repo version.

Version: CI never bumps or commits. The release PR must bump `patch` +
`buildNumber` in `lib/core/constants/app_version_config.dart`, `pubspec.yaml`
and `web/version.json` (all three equal). Production refuses a version that is
not newer than the live `https://tashil-gift.web.app/version.json`, except a
manual rollback with `allow_older_version = true`.

Credentials: the `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT` secret is written to
`$RUNNER_TEMP` only for the deploy step and deleted afterwards. Never indexes,
never `--force`.
