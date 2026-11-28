#!/usr/bin/env bash
# Test gate (TAG-82): runs only the tools a change needs, picked by
# tool/ci/gate_buckets.py from `git diff --name-only <base>...HEAD`.
#
#   bash tool/ci/run_gate.sh                 # change vs origin/dev
#   bash tool/ci/run_gate.sh --base main     # change vs another ref
#   bash tool/ci/run_gate.sh --all           # the full test: every tool
#   bash tool/ci/run_gate.sh --only rules,guards
#   bash tool/ci/run_gate.sh --dry-run       # print the plan, run nothing
#   bash tool/ci/run_gate.sh --ci            # in gate.yml: skip what checks.yml already runs
#
# Tools 1-4 run here. Tool 6 (Patrol web) and 5 (Maestro, Mac only) are
# listed when needed and arrive with TAG-82 PR 2 and PR 3.
#
# Safety: emulator tools only ever use demo-* projects and run with no
# Google credentials. Nothing here deploys or writes to tashil-gift-dev or
# tashil-gift. Results: $GATE_OUT/SUMMARY.md (default build/gate/).
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
export FIREBASE_TOOLS_VERSION="${FIREBASE_TOOLS_VERSION:-15.37.0}"

base="origin/dev"; all=0; only=""; dry=0; ci=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --all) all=1; shift ;;
    --only) only="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --ci) ci=1; shift ;;
    -h|--help) sed -n 2,18p "$0"; exit 0 ;;
    *) echo "run_gate: unknown option $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$only" ]]; then
  TOOLS="${only//,/ }"; BUCKETS="(--only)"
elif [[ $all -eq 1 ]]; then
  eval "$(python3 tool/ci/gate_buckets.py --all --format shell)"
else
  git rev-parse --verify -q "$base" >/dev/null || { echo "run_gate: base '$base' not found (git fetch origin dev?)" >&2; exit 2; }
  python3 tool/ci/gate_buckets.py --base "$base" --format text
  eval "$(python3 tool/ci/gate_buckets.py --base "$base" --format shell)"
fi

# In CI, checks.yml (called by dev-preview.yml on every PR into dev) already
# runs analyze, flutter test and the functions unit tests.
skip_ci=" analyze flutter_test "
OUT="${GATE_OUT:-build/gate}"
mkdir -p "$OUT"
summary="$OUT/SUMMARY.md"
sha=$(git rev-parse --short HEAD)
{
  echo "# Gate $sha ($(date -u +%Y-%m-%dT%H:%MZ))"
  echo
  echo "Buckets: ${BUCKETS:-none}"
  echo
  echo "| Tool | Result | Time | Log |"
  echo "| --- | --- | --- | --- |"
} > "$summary"

if [[ -z "${TOOLS// /}" ]]; then
  echo "run_gate: nothing to run for this change (docs only or no changes)."
  echo "Nothing to run." >> "$summary"
  exit 0
fi
echo "run_gate: tools: $TOOLS"
[[ $dry -eq 1 ]] && { echo "(dry run, nothing executed)"; exit 0; }

# --- emulator safety: demo-* only, no credentials ---
emulator_safety() {
  unset GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT GCLOUD_PROJECT FIREBASE_TOKEN
  local bad
  bad=$(grep -hoE -- '--project[ =]+[^ "\\]+' rules-tests/package.json functions/package.json | awk '{print $2}' | grep -vE '^demo-' || true)
  if [[ -n "$bad" ]]; then echo "::error::emulator scripts name a non-demo project: $bad"; return 1; fi
}

t_analyze()      { flutter pub get >/dev/null && bash tool/ci/analyze.sh tool/ci/analyze_baseline.txt; }
t_flutter_test() {
  flutter pub get >/dev/null || return 1
  bash tool/ci/flutter_test.sh blocking tool/ci/known_failing_tests.txt; local rc=$?
  bash tool/ci/flutter_test.sh known tool/ci/known_failing_tests.txt || true
  return $rc
}
t_guards() {
  python3 tool/ci/static_guards.py || return 1
  python3 -m unittest discover -s tool/ci -p 'test_*.py' -q
}
t_rules() {
  emulator_safety || return 1
  (cd rules-tests && npm ci --no-audit --no-fund && npm test)
}
t_functions() {
  emulator_safety || return 1
  (cd functions && npm ci --no-audit --no-fund) || return 1
  if [[ $ci -eq 0 ]]; then (cd functions && npm test) || return 1; fi
  (cd functions && npm run test:emulator)
}
t_patrol()  { echo "Patrol web is not set up yet (TAG-82 PR 2)."; return 3; }
t_maestro() { echo "Maestro runs on the Mac only and is not set up yet (TAG-82 PR 3)."; return 3; }

failed=0
for t in $TOOLS; do
  if [[ $ci -eq 1 && "$skip_ci" == *" $t "* ]]; then
    echo "| $t | skipped (checks.yml runs it) | - | - |" >> "$summary"; continue
  fi
  if ! declare -F "t_$t" >/dev/null; then echo "run_gate: unknown tool $t" >&2; exit 2; fi
  log="$OUT/$t.log"
  echo "::group::$t"
  start=$(date +%s)
  "t_$t" > >(tee "$log") 2>&1; rc=$?
  wait
  secs=$(( $(date +%s) - start ))
  echo "::endgroup::"
  case $rc in
    0) res="PASS" ;;
    3) res="not set up yet" ;;
    *) res="FAIL ($rc)"; failed=1 ;;
  esac
  echo "$t: $res (${secs}s)"
  echo "| $t | $res | ${secs}s | $log |" >> "$summary"
done

echo; cat "$summary"
[[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$summary" >> "$GITHUB_STEP_SUMMARY"
exit $failed
