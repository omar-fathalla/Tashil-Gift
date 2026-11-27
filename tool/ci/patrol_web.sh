#!/usr/bin/env bash
# Gate tool 6 (TAG-82 PR 2): Patrol web tests on the local emulators.
#
#   bash tool/ci/patrol_web.sh                        # every test in patrol_test/
#   bash tool/ci/patrol_web.sh patrol_test/admin_login_test.dart
#   HEADED=1 bash tool/ci/patrol_web.sh ...           # show the browser
#   PATROL_MODE=debug ...                          # default release (dart2js)
#   PATROL_VERBOSE=1 ...                              # Playwright stderr and Flutter logs
#   PATROL_BROWSER_ARGS='["--no-sandbox",...]'       # override the Chromium flags
#
# Safety: the app is built with FIREBASE_EMULATOR=true (project
# demo-tashil-branch, 127.0.0.1 only) and SYNTHETIC_RECEIPT_FIXTURE=true, so
# no request reaches tashil-gift, tashil-gift-dev, Gemini or WhatsApp. The
# emulators run with no Google credentials. The functions emulator skips token
# verification (FIREBASE_DEBUG_MODE) because callables are called by the
# emulator-signed fixture admin; never set that on a deployed function.
# As a second lock, Chrome cannot resolve the Gemini hosts at all (see
# BLOCK_HOSTS); keep that rule when you override PATROL_BROWSER_ARGS.
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
BLOCK_HOSTS='MAP generativelanguage.googleapis.com ~NOTFOUND, MAP firebasevertexai.googleapis.com ~NOTFOUND, MAP aiplatform.googleapis.com ~NOTFOUND'
mkdir -p "$OUT"

unset GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT GCLOUD_PROJECT FIREBASE_TOKEN
[[ "$PROJECT" == demo-* ]] || { echo "patrol_web: project must be demo-*" >&2; exit 1; }

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
  --web-results-dir "$OUT/results" --web-report-dir "$OUT/report" \
  --web-browser-args "${PATROL_BROWSER_ARGS:-[\"--no-sandbox\",\"--disable-dev-shm-usage\",\"--host-resolver-rules=$BLOCK_HOSTS\"]}" \
  --dart-define=FIREBASE_EMULATOR=true \
  --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true \
  "${targets[@]}")

FIREBASE_DEBUG_MODE=true FIREBASE_DEBUG_FEATURES='{"skipTokenVerification":true}' \
  npx -y "firebase-tools@${FIREBASE_TOOLS_VERSION}" emulators:exec \
  --project "$PROJECT" --only auth,firestore,functions \
  "$cmd"
