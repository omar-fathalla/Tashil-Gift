#!/usr/bin/env python3
"""Which gate tools a change needs (TAG-82, same idea as Stage 0 of the
Tashil-Employee pr-gate). Each changed file lands in one or more buckets,
and each bucket turns on only the tools that matter for it.

Tools:
  analyze      1  flutter analyze (tool/ci/analyze.sh + baseline)
  flutter_test 2  flutter test (tool/ci/flutter_test.sh blocking + known)
  guards       3  static guards + the gate's own self-tests
  rules        4  firestore/storage rules on the emulator (rules-tests)
  functions    4  functions unit tests + functions on the emulator
  patrol       6  Patrol web on the emulators (TAG-82 PR 2)
  maestro      5  Maestro web, on the Mac only (TAG-82 PR 3)

A docs-only change needs nothing. A file that matches no bucket needs
tools 1 to 4, so nothing slips through unclassified.

Usage:
  python3 tool/ci/gate_buckets.py [--base origin/dev] [--head HEAD]   # from git
  python3 tool/ci/gate_buckets.py --files a b c                         # explicit
  --format text|shell|json   (shell: TOOLS="..." BUCKETS="..." lines for bash)
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys

TOOL_ORDER = ["analyze", "flutter_test", "guards", "rules", "functions", "patrol", "maestro"]
TOOL_LABEL = {
    "analyze": "1 analyze",
    "flutter_test": "2 flutter test",
    "guards": "3 static guards",
    "rules": "4 rules (emulator)",
    "functions": "4 functions (unit + emulator)",
    "patrol": "6 Patrol web",
    "maestro": "5 Maestro (Mac)",
}
FAST_TOOLS = {"analyze", "flutter_test", "guards", "rules", "functions"}
ALL_FAST = ["analyze", "flutter_test", "guards", "rules", "functions"]

# (bucket, globs, tools). A file can match several buckets.
BUCKETS: list[tuple[str, list[str], list[str]]] = [
    ("docs", ["docs/**", "*.md", "**/*.md", "*.txt", "*.png", "LICENSE"], []),
    ("ui", [
        "lib/features/*/presentation/**", "lib/core/widgets/**", "lib/core/theme/**",
        "lib/core/localization/**", "lib/core/services/**", "lib/main.dart",
        "web/**", "assets/**", "firebase.json",
    ], ["analyze", "flutter_test", "patrol", "maestro"]),
    ("dart", ["lib/**", "test/**"], ["analyze", "flutter_test"]),
    ("rules", ["firestore.rules", "storage.rules", "firestore.indexes.json", "rules-tests/**"], ["rules", "patrol"]),
    ("functions", ["functions/**"], ["functions"]),
    ("toolchain", [
        "pubspec.yaml", "pubspec.lock", ".fvmrc", "analysis_options.yaml", "devtools_options.yaml",
        "tool/ci/known_failing_tests.txt", "tool/ci/analyze_baseline.txt",
    ], ["analyze", "flutter_test"]),
    ("e2e", ["maestro/**", "patrol_test/**", "integration_test/**", "firebase.patrol.json",
             "functions/.env.demo-tashil-branch", "tool/ci/patrol_web.sh", "tool/ci/emulator_log_check.py"], ["analyze", "patrol", "maestro"]),
    ("scripts", [
        "tool/**", ".github/**", "firebase*.json", ".firebaserc", "*.sh", "functions/scripts/**",
        ".claude/**", "skills-lock.json",
    ], ["guards"]),
]


def _match(path: str, glob: str) -> bool:
    # fnmatch's * already crosses "/", so "lib/**" matches every file under lib/.
    return fnmatch.fnmatch(path, glob)


def classify(paths: list[str]) -> tuple[dict[str, list[str]], list[str]]:
    """Returns ({bucket: [files]}, ordered tools)."""
    buckets: dict[str, list[str]] = {}
    tools: set[str] = set()
    for p in sorted(set(x.strip() for x in paths if x.strip())):
        hit = [(name, t) for name, globs, t in BUCKETS if any(_match(p, g) for g in globs)]
        if any(name == "docs" for name, _ in hit) and len(hit) == 1:
            buckets.setdefault("docs", []).append(p)
            continue
        hit = [(n, t) for n, t in hit if n != "docs"]
        if not hit:
            buckets.setdefault("unclassified", []).append(p)
            tools.update(ALL_FAST)
            continue
        for name, t in hit:
            buckets.setdefault(name, []).append(p)
            tools.update(t)
    return buckets, [t for t in TOOL_ORDER if t in tools]


def changed_files(base: str, head: str) -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...{head}"], check=True, capture_output=True, text=True
    ).stdout
    return out.splitlines()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", default="origin/dev")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--files", nargs="*")
    ap.add_argument("--all", action="store_true", help="the full test: every tool")
    ap.add_argument("--format", choices=["text", "shell", "json"], default="text")
    a = ap.parse_args(argv)

    if a.all:
        buckets, tools = {"full-test": ["(all)"]}, list(TOOL_ORDER)
    else:
        files = a.files if a.files is not None else changed_files(a.base, a.head)
        buckets, tools = classify(files)

    if a.format == "json":
        print(json.dumps({"buckets": buckets, "tools": tools}, ensure_ascii=False, indent=2))
    elif a.format == "shell":
        print(f'TOOLS="{" ".join(tools)}"')
        print(f'BUCKETS="{" ".join(sorted(buckets))}"')
    else:
        if not buckets:
            print("no changed files")
        for b in sorted(buckets):
            print(f"{b}: {len(buckets[b])} file(s)")
        print("tools: " + (", ".join(TOOL_LABEL[t] for t in tools) if tools else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
