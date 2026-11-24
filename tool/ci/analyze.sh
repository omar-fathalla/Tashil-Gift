#!/usr/bin/env bash
# flutter analyze that fails on any error, or on more warnings than the baseline.
# Info-level findings never fail the job.
set -uo pipefail
baseline_file="${1:-$(dirname "$0")/analyze_baseline.txt}"
max_warnings=$(sed -n 's/^warnings=\([0-9]*\).*/\1/p' "$baseline_file")
out=$(flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1); code=$?
echo "$out"
errors=$(grep -cE '^[[:space:]]*error [•-]' <<<"$out" || true)
warnings=$(grep -cE '^[[:space:]]*warning [•-]' <<<"$out" || true)
echo "analyze: errors=$errors warnings=$warnings (baseline warnings=$max_warnings)"
if [[ $code -ne 0 || $errors -gt 0 ]]; then echo "::error::flutter analyze reported errors"; exit 1; fi
if [[ $warnings -gt $max_warnings ]]; then echo "::error::new analyzer warnings ($warnings > $max_warnings)"; exit 1; fi
