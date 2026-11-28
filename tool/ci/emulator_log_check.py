#!/usr/bin/env python3
"""Fails if an emulator log shows a call that leaves the machine (TAG-82 PR 2).

The Patrol tests must never reach Gemini or WhatsApp (WAHA). The app calls
them only through Cloud Functions, so the lock is on the server side: this
script reads the output of `firebase emulators:exec` and fails when

  - a function that talks to Gemini or WAHA started executing, or
  - a Gemini / Vertex AI / WAHA host appears anywhere in the log.

Usage: python3 tool/ci/emulator_log_check.py LOG_FILE
Exit 0 = clean, 1 = forbidden call found, 2 = usage error.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Functions that call Gemini (geminiGenerate, analyzeReceipt) or WAHA.
FORBIDDEN_FUNCTIONS = [
    "geminiGenerate",
    "analyzeReceipt",
    "sendWinnerWhatsApp",
    "wahaProxy",
    "manageWhatsappSenderLink",
    "updateWhatsappWebhookConfig",
]
FORBIDDEN_HOSTS = [
    "waha.sw-point.com",
    "generativelanguage.googleapis.com",
    "firebasevertexai.googleapis.com",
    "aiplatform.googleapis.com",
]

# The functions emulator prints: Beginning execution of "us-central1-geminiGenerate"
EXEC_RE = re.compile(r'Beginning execution of "(?:[a-z0-9-]+-)?(?P<fn>[A-Za-z0-9_]+)"')


def scan(text: str) -> list[str]:
    found = []
    for n, line in enumerate(text.splitlines(), 1):
        m = EXEC_RE.search(line)
        if m and m.group("fn") in FORBIDDEN_FUNCTIONS:
            found.append(f"{n}: function {m.group('fn')} ran: {line.strip()}")
            continue
        for h in FORBIDDEN_HOSTS:
            if h in line:
                found.append(f"{n}: host {h}: {line.strip()}")
                break
    return found


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    path = Path(argv[0])
    if not path.is_file():
        print(f"emulator_log_check: no log at {path}", file=sys.stderr)
        return 2
    found = scan(path.read_text(encoding="utf-8", errors="replace"))
    if found:
        print(f"emulator_log_check: {len(found)} call(s) that must not happen in Patrol:")
        for f in found:
            print("  " + f)
        return 1
    print("emulator_log_check: OK (no Gemini or WAHA call in the emulator log)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
