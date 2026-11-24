#!/usr/bin/env bash
# Runs the Flutter tests in two steps:
#   blocking  : every test/**/*_test.dart file NOT listed in known_failing_tests.txt
#   known     : the listed files (never fails the job; results are printed)
# Usage: tool/ci/flutter_test.sh blocking|known [list-file]
set -euo pipefail
mode="${1:?usage: flutter_test.sh blocking|known [list-file]}"
list="${2:-$(dirname "$0")/known_failing_tests.txt}"

mapfile -t known < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^[[:space:]]*$' || true)
is_known() { local f; for f in "${known[@]}"; do [[ "$1" == "$f" ]] && return 0; done; return 1; }

mapfile -t all < <(find test -name '*_test.dart' -type f | sort)
run=()
for f in "${all[@]}"; do
  if [[ "$mode" == blocking ]]; then is_known "$f" || run+=("$f"); else is_known "$f" && run+=("$f"); fi
done

echo "mode=$mode files=${#run[@]} (of ${#all[@]}; known-failing list has ${#known[@]})"
if [[ ${#run[@]} -eq 0 ]]; then echo "nothing to run"; exit 0; fi

if [[ "$mode" == blocking ]]; then
  flutter test "${run[@]}"
else
  for f in "${run[@]}"; do
    [[ -f "$f" ]] || { echo "::warning::$f is in the known-failing list but does not exist"; continue; }
    if flutter test "$f"; then
      echo "::notice::$f now passes. Remove it from tool/ci/known_failing_tests.txt so it becomes blocking."
    else
      echo "::warning::$f still fails (known, not blocking)."
    fi
  done
fi
