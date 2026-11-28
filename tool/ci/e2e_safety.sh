#!/usr/bin/env bash
# Shared checks for the e2e runners on the emulators (TAG-82): sourced by
# tool/ci/patrol_web.sh and tool/ci/maestro_web.sh. Run from the repo root.
#
#   e2e_safety_check <demo-project> <runner-name>
#
# Fails (returns 1) when the run could reach Gemini, WhatsApp (WAHA) or a real
# Firebase project:
#   - the project is not demo-*;
#   - functions/.secret.local exists (the functions emulator would load real
#     Gemini/WAHA keys from it);
#   - functions/.env.local exists (the functions emulator reads it on top of
#     functions/.env.<project>, so a real WAHA_BACKEND_URL there would win);
#   - functions/.env.<project> does not point WAHA_BACKEND_URL at 127.0.0.1.
# It also drops any Google credentials from the environment.

e2e_safety_check() {
  local project="$1" who="${2:-e2e}"
  unset GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT GCLOUD_PROJECT FIREBASE_TOKEN
  if [[ "$project" != demo-* ]]; then
    echo "$who: project must be demo-*, got '$project'" >&2; return 1
  fi
  local f
  for f in functions/.secret.local functions/.env.local; do
    if [[ -e "$f" ]]; then
      echo "$who: $f exists; the functions emulator would load real Gemini/WAHA settings from it." >&2
      echo "$who: move it away for the run (it is never needed for the e2e tests)." >&2
      return 1
    fi
  done
  if ! grep -q '^WAHA_BACKEND_URL=http://127.0.0.1:' "functions/.env.$project" 2>/dev/null; then
    echo "$who: functions/.env.$project must point WAHA_BACKEND_URL at 127.0.0.1" >&2; return 1
  fi
}
