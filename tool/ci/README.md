# CI / deploy (GitHub Actions)

| Trigger | Workflow | What runs | Deploys |
|---|---|---|---|
| PR into `dev` | `dev-preview.yml` | `checks.yml` (APP_ENV=dev once tashil-gift-dev is ready) | `pr-<N>` channel on **tashil-gift-dev** (7 days) + PR comment; until dev is ready: legacy `pr-<N>` channel on tashil-gift |
| push to `dev` (merged PR) | `dev-preview.yml` | same | live **https://tashil-gift-dev.web.app** (+ functions/rules if `DEV_AUTO_DEPLOY_BACKEND=true`); until dev is ready: legacy `dev` channel on tashil-gift |
| manual | `dev-deploy.yml` (`ref`, `what`) | `checks.yml` APP_ENV=dev | tashil-gift-dev only: hosting, functions, Firestore rules + indexes, Storage rules |
| PR into / push to `dev` | `gate.yml` | `run_gate.sh --ci`: static guards, rules + functions emulator suites, picked by `gate_buckets.py` from the changed files | nothing |
| push to `main` | `deploy-production.yml` | `checks.yml` | after the `production` environment approval: `hosting,functions,firestore:rules` |
| manual (rollback) | `deploy-production.yml` (`ref`, `allow_older_version`) | `checks.yml` on that ref | same as above, for that ref |

Dev environment: see `docs/DEV_ENVIRONMENT.md`. The dev path runs only when
the `FIREBASE_SERVICE_ACCOUNT_TASHIL_GIFT_DEV` secret exists and
`lib/firebase_options_dev.dart` is filled in (`tool/ci/dev_config_status.py`);
otherwise it is skipped (CI stays green). Legacy preview channels on
`tashil-gift` carry Hosting files only and use the **production** Firestore,
Auth, Storage and Cloud Functions; `DISABLE_PROD_PREVIEW_FALLBACK=true` turns
them off. `version.json` carries `env` (`prod`/`dev`); production refuses a
non-prod build (`check_version.py --env prod`).

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

Test gate (TAG-82): `run_gate.sh` runs only the tools a change needs
(`gate_buckets.py`), `--all` runs every tool. `static_guards.py` is read-only;
intended findings live in `guards_allowlist.txt` with a reason. `gate.yml` is
separate from `checks.yml` on purpose: `checks.yml` also gates production
deploys and rollbacks.
