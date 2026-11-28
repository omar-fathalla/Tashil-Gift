#!/usr/bin/env bash
# Gate tool 5 (TAG-82 PR 3): Maestro web, on the Mac only. Never in CI.
#
#   bash tool/ci/maestro_web.sh                # = emulator
#   bash tool/ci/maestro_web.sh emulator       # maestro/emulator/ on the local emulators
#   bash tool/ci/maestro_web.sh dev            # maestro/dev/: small read-only smoke on
#                                              # https://tashil-gift-dev.web.app
#
# This script never installs Maestro. Installing it on the Mac is Mohamed's
# decision; until then the script exits 3 ("not set up here").
#
# emulator (the main one):
#   - Builds the web app with FIREBASE_EMULATOR=true (project
#     demo-tashil-branch, 127.0.0.1 only), SYNTHETIC_RECEIPT_FIXTURE=true and
#     E2E_SEMANTICS=true (Flutter builds the accessibility tree Maestro reads;
#     prod and dev builds never set it).
#   - Same server-side lock as Patrol (tool/ci/e2e_safety.sh): demo-* only, no
#     Google credentials, refuses functions/.secret.local and
#     functions/.env.local, WAHA_BACKEND_URL on 127.0.0.1. After the run,
#     tool/ci/emulator_log_check.py fails it on any Gemini/WAHA call.
#   - Seeds the fixture admin and campaign (maestro/support/seed_emulator.mjs).
#
# dev (by hand only):
#   - Needs MAESTRO_DEV_ADMIN_EMAIL and MAESTRO_DEV_ADMIN_PASSWORD from the
#     Mac's local environment. They are never printed: Maestro reads MAESTRO_*
#     variables itself, and its output is redacted.
#   - Only signs in and opens a campaign. No receipt, no gift, no save.
#   - Maestro's screenshots and logs (they show the login screen) go to a
#     temp folder that is deleted after the run. Nothing is kept or uploaded.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
export FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.37.0}"
MODE="${1:-emulator}"
PROJECT=demo-tashil-branch
WEB_PORT=7360           # must match url: in maestro/emulator/*.yaml
DEV_URL=https://tashil-gift-dev.web.app/

not_set_up() { echo "maestro_web: $*" >&2; exit 3; }

case "$MODE" in
  emulator)
    source tool/ci/e2e_safety.sh
    e2e_safety_check "$PROJECT" maestro_web || exit 1
    ;;
  dev)
    unset GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT GCLOUD_PROJECT FIREBASE_TOKEN
    for f in maestro/dev/*.yaml; do
      grep -qx "url: $DEV_URL" "$f" || { echo "maestro_web: $f must open $DEV_URL only" >&2; exit 1; }
      if grep -qE '^\s*-\s*(takeScreenshot|startRecording)' "$f"; then
        echo "maestro_web: $f must not take screenshots or recordings (login screen)" >&2; exit 1
      fi
    done
    if [[ -z "${MAESTRO_DEV_ADMIN_EMAIL:-}" || -z "${MAESTRO_DEV_ADMIN_PASSWORD:-}" ]]; then
      echo "maestro_web: set MAESTRO_DEV_ADMIN_EMAIL and MAESTRO_DEV_ADMIN_PASSWORD in the Mac's local environment." >&2
      exit 1
    fi
    ;;
  *) echo "usage: $0 [emulator|dev]" >&2; exit 2 ;;
esac

[[ -z "${CI:-}" ]] || not_set_up "Maestro runs on the Mac only, not in CI."
[[ "$(uname -s)" == Darwin ]] || not_set_up "Maestro runs on the Mac only (this is $(uname -s))."
command -v maestro >/dev/null \
  || not_set_up "maestro is not installed. Installing it on the Mac needs Mohamed's approval; this script never installs it."

if [[ "$MODE" == dev ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  # Redact the account in case a Maestro version prints typed text.
  set +e
  maestro test --debug-output "$tmp/debug" --test-output-dir "$tmp/out" maestro/dev 2>&1 \
    | python3 -c '
import os, sys
secrets = [v for v in (os.environ.get("MAESTRO_DEV_ADMIN_EMAIL"), os.environ.get("MAESTRO_DEV_ADMIN_PASSWORD")) if v]
for line in sys.stdin:
    for s in secrets:
        line = line.replace(s, "***")
    sys.stdout.write(line)
    sys.stdout.flush()
'
  rc=${PIPESTATUS[0]}
  exit "$rc"
fi

OUT="$(mkdir -p "${GATE_OUT:-build/gate}/maestro" && cd "${GATE_OUT:-build/gate}/maestro" && pwd)"
LOG="$OUT/emulators.log"

flutter build web --release --output "$OUT/web" \
  --dart-define=FIREBASE_EMULATOR=true \
  --dart-define=SYNTHETIC_RECEIPT_FIXTURE=true \
  --dart-define=E2E_SEMANTICS=true

if [[ ! -d functions/node_modules ]]; then (cd functions && npm ci --no-audit --no-fund); fi

# Runs inside emulators:exec so the emulators stop with the flows.
inner=$(cat <<EOF
set -e
node maestro/support/seed_emulator.mjs
python3 -m http.server $WEB_PORT --bind 127.0.0.1 --directory $(printf '%q' "$OUT/web") >/dev/null 2>&1 &
srv=\$!
trap 'kill \$srv 2>/dev/null || true' EXIT
for _ in \$(seq 1 30); do curl -fsS http://127.0.0.1:$WEB_PORT/ >/dev/null 2>&1 && break; sleep 1; done
maestro test --format junit --output $(printf '%q' "$OUT/report.xml") \
  --debug-output $(printf '%q' "$OUT/debug") --test-output-dir $(printf '%q' "$OUT/out") maestro/emulator
EOF
)

# firebase.patrol.json: firebase.json's Storage target names the prod bucket.
set +e
FIREBASE_DEBUG_MODE=true FIREBASE_DEBUG_FEATURES='{"skipTokenVerification":true}' \
  npx -y "firebase-tools@${FIREBASE_TOOLS_VERSION}" emulators:exec \
  --config firebase.patrol.json --project "$PROJECT" --only auth,firestore,functions,storage \
  "bash -c $(printf '%q' "$inner")" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

python3 tool/ci/emulator_log_check.py "$LOG" || rc=1
exit "$rc"
