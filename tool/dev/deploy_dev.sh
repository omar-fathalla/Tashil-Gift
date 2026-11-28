#!/usr/bin/env bash
# Deploys to the DEV project tashil-gift-dev ONLY (TAG-12, TAG-23).
#
#   bash tool/dev/deploy_dev.sh rules        # firestore:rules + firestore:indexes + storage
#   bash tool/dev/deploy_dev.sh functions
#   bash tool/dev/deploy_dev.sh hosting      # needs build/web from an APP_ENV=dev build
#   bash tool/dev/deploy_dev.sh all
#
# Used by .github/workflows/dev-deploy.yml. It can also run on a laptop with a
# tashil-gift-dev service account, but never against production: the project
# id is hard-coded, firebase.dev.json is rendered with the dev Storage bucket,
# the credentials file must belong to tashil-gift-dev, and there is no --force.
set -euo pipefail

PROJECT=tashil-gift-dev
FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.37.0}"
what="${1:-}"
case "$what" in
  rules) only="firestore:rules,firestore:indexes,storage" ;;
  functions) only="functions" ;;
  hosting) only="hosting" ;;
  all) only="hosting,functions,firestore:rules,firestore:indexes,storage" ;;
  *) echo "usage: $0 rules|functions|hosting|all" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Repo root: the current directory when it holds firebase.json (CI runs this
# script from a separate checkout of the workflow commit), else this repo.
[ -f firebase.json ] || cd "$SCRIPT_DIR/../.."

# Credentials must be the dev service account (a pasted prod key is refused).
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  sa_project=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('project_id',''))" "$GOOGLE_APPLICATION_CREDENTIALS")
  if [ "$sa_project" != "$PROJECT" ]; then
    echo "::error::The deploy credentials belong to '$sa_project', not $PROJECT. Refusing." >&2
    exit 1
  fi
fi

if [[ ",$only," == *",hosting,"* ]]; then
  [ -f build/web/version.json ] || { echo "::error::build/web is missing (build with --dart-define=APP_ENV=dev first)" >&2; exit 1; }
  env=$(python3 -c "import json; print(json.load(open('build/web/version.json')).get('env','prod'))")
  [ "$env" = "dev" ] || { echo "::error::build/web is an env=$env build; dev Hosting only takes an APP_ENV=dev build" >&2; exit 1; }
fi

python3 "$SCRIPT_DIR/render_firebase_dev_json.py"
if grep -q '"tashil-gift.firebasestorage.app"' firebase.dev.json; then
  echo "::error::firebase.dev.json points at the production bucket" >&2
  exit 1
fi

if [[ ",$only," == *",functions,"* ]] && [ ! -d functions/node_modules ]; then
  (cd functions && npm ci)
fi

echo "Deploying --only $only to $PROJECT"
log="$(mktemp)"
set +e
npx -y "firebase-tools@${FIREBASE_TOOLS_VERSION}" deploy \
  --project "$PROJECT" \
  --config firebase.dev.json \
  --only "$only" \
  --non-interactive \
  --message "dev deploy ${GITHUB_SHA:-local} ${GITHUB_RUN_ID:-}" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
# The functions are live even when only the Artifact Registry cleanup policy
# could not be set (firebase-tools then exits 1 and suggests --force, which we
# never use). That one case is a warning, not a failed deploy.
if [ "$status" -ne 0 ] && grep -q "Functions successfully deployed but could not set up cleanup policy" "$log"; then
  echo "::warning::Functions deployed to $PROJECT; the artifact cleanup policy is not set (one-time: firebase functions:artifacts:setpolicy --project tashil-gift-dev)."
  status=0
fi
rm -f "$log"
exit "$status"
