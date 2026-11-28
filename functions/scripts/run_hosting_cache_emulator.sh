#!/usr/bin/env bash
# Starts the Hosting + Functions + Firestore emulators on a demo project and
# checks sharePreview Cache-Control. Never deploys. Never uses tashil-gift.
set -euo pipefail

PROJECT="${1:-demo-tashil}"
case "$PROJECT" in
  *tashil-gift*)
    echo "Refusing production project: $PROJECT" >&2
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FIXTURE_DIR="$ROOT/build/web"
mkdir -p "$FIXTURE_DIR/assets" "$FIXTURE_DIR/canvaskit" "$FIXTURE_DIR/icons" "$FIXTURE_DIR/fonts"
write_if_missing() {
  local path="$1"
  local body="$2"
  if [[ ! -f "$path" ]]; then
    printf '%s\n' "$body" > "$path"
  fi
}
write_if_missing "$FIXTURE_DIR/index.html" '<!doctype html><title>FIXTURE_SHELL</title>'
write_if_missing "$FIXTURE_DIR/main.dart.js" 'FIXTURE_JS'
write_if_missing "$FIXTURE_DIR/flutter.js" 'FIXTURE_FLUTTER'
write_if_missing "$FIXTURE_DIR/flutter_bootstrap.js" 'FIXTURE_BOOTSTRAP'
write_if_missing "$FIXTURE_DIR/flutter_service_worker.js" 'FIXTURE_SW'
write_if_missing "$FIXTURE_DIR/version.json" '{"fixture":true}'
write_if_missing "$FIXTURE_DIR/manifest.json" '{"name":"fixture"}'
write_if_missing "$FIXTURE_DIR/assets/keep.png" 'FIXTURE_PNG'
write_if_missing "$FIXTURE_DIR/assets/extensionless" 'FIXTURE_ASSET'
write_if_missing "$FIXTURE_DIR/canvaskit/canvaskit.js" 'FIXTURE_CK'
write_if_missing "$FIXTURE_DIR/icons/keep.png" 'FIXTURE_ICON'
write_if_missing "$FIXTURE_DIR/fonts/keep.ttf" 'FIXTURE_FONT'

export CI=1
exec npx -y "firebase-tools@${FIREBASE_TOOLS_VERSION:-15.37.0}" emulators:exec \
  --project "$PROJECT" \
  --only hosting,functions,firestore \
  "node functions/scripts/check_hosting_cache_emulator.js"
