#!/usr/bin/env bash
# Gate tool 6 (TAG-82 PR 2): Patrol web tests on the local emulators.
#
#   bash tool/ci/patrol_web.sh                        # every test in patrol_test/
#   bash tool/ci/patrol_web.sh patrol_test/admin_login_test.dart
#   HEADED=1 bash tool/ci/patrol_web.sh ...           # show the browser
#   PATROL_MODE=debug ...                          # default release (dart2js)
#   PATROL_VERBOSE=1 ...
#   PATROL_WEB_LOCALE=ar-EG ...                    # browser locale (default en-US;
#                                                  # the app still opens in Arabic). CI's
#                                                  # LANG=C.UTF-8 is not a valid Intl locale.
#   PATROL_BROWSER_ARGS='["--no-sandbox",...]'       # override the Chromium flags
#
# Safety: the app is built with FIREBASE_EMULATOR=true (project
# demo-tashil-branch, 127.0.0.1 only) and SYNTHETIC_RECEIPT_FIXTURE=true, so
# it reaches neither tashil-gift nor tashil-gift-dev. The emulators run with no
# Google credentials. The functions emulator skips token verification
# (FIREBASE_DEBUG_MODE) because callables are called by the emulator-signed
# fixture admin; never set that on a deployed function.
#
# Gemini and WhatsApp are called only from Cloud Functions, so they are locked
# on the server side, not in the browser:
#   - functions/.env.demo-tashil-branch points WAHA_BACKEND_URL at 127.0.0.1:9.
#   - The script refuses to run if functions/.secret.local exists, because the
#     functions emulator would load real keys from it.
#   - After the run, tool/ci/emulator_log_check.py fails the job if the
#     emulator log shows geminiGenerate, analyzeReceipt, sendWinnerWhatsApp,
#     wahaProxy (or the other WAHA functions) running, or a Gemini/WAHA host.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
export FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.37.0}"
PROJECT=demo-tashil-branch
WEB_PORT="${PATROL_WEB_PORT:-7358}"   # 8080 is the Firestore emulator
# Absolute: Playwright resolves these from its own folder in the pub cache.
OUT="$(cd "$ROOT" && mkdir -p "${GATE_OUT:-build/gate}/patrol" && cd "${GATE_OUT:-build/gate}/patrol" && pwd)"
# Release by default: every test loads the app in a fresh page, and a debug
# (DDC) build is too slow to load more than once.
MODE="${PATROL_MODE:-release}"
mkdir -p "$OUT"
LOG="$OUT/emulators.log"

unset GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT GCLOUD_PROJECT FIREBASE_TOKEN
[[ "$PROJECT" == demo-* ]] || { echo "patrol_web: project must be demo-*" >&2; exit 1; }
if [[ -e functions/.secret.local ]]; then
  echo "patrol_web: functions/.secret.local exists; the functions emulator would load real Gemini/WAHA keys from it." >&2
  echo "patrol_web: move it away for the run (it is never needed for Patrol)." >&2
  exit 1
fi
grep -q '^WAHA_BACKEND_URL=http://127.0.0.1:' "functions/.env.$PROJECT" 2>/dev/null \
  || { echo "patrol_web: functions/.env.$PROJECT must point WAHA_BACKEND_URL at 127.0.0.1" >&2; exit 1; }

targets=()
if [[ $# -gt 0 ]]; then
  for t in "$@"; do targets+=(--target "$t"); done
else
  while IFS= read -r t; do targets+=(--target "$t"); done < <(find patrol_test -maxdepth 1 -name '*_test.dart' | sort)
fi
[[ ${#targets[@]} -gt 0 ]] || { echo "patrol_web: no tests in patrol_test/"; exit 0; }

headless=--web-headless
[[ "${HEADED:-0}" == 1 ]] && headless=--no-web-headless
verbose=()
[[ "${PATROL_VERBOSE:-0}" == 1 ]] && verbose=(--verbose)

if [[ ! -d functions/node_modules ]]; then (cd functions && npm ci --no-audit --no-fund); fi

# Runs inside emulators:exec so the emulators stop with the tests.
cmd=$(printf '%q ' patrol test "${verbose[@]}" "--$MODE" --device chrome "$headless" --web-port "$WEB_PORT" \
  --web-locale "${PATROL_WEB_LOCALE:-en-US}" \
  --web-results-dir "$OUT/results" --web-report-dir "$OUT/report" \
  --web-browser-args "${PATROL_BROWSER_ARGS:-[\"--no-sandbox\",\"--disable-dev-shm-usage\"]}" \
  --dart-define=FIREBASE_EMULATOR=true \
  --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true \
  "${targets[@]}")

# firebase.patrol.json: firebase.json's Storage target names the prod bucket,
# so the emulators get their own config with storage.rules on the app's
# demo bucket.
set +e
FIREBASE_DEBUG_MODE=true FIREBASE_DEBUG_FEATURES='{"skipTokenVerification":true}' \
  npx -y "firebase-tools@${FIREBASE_TOOLS_VERSION}" emulators:exec \
  --config firebase.patrol.json --project "$PROJECT" --only auth,firestore,functions,storage \
  "$cmd" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

python3 tool/ci/emulator_log_check.py "$LOG" || rc=1
exit "$rc"
