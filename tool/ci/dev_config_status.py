#!/usr/bin/env python3
"""Prints `configured=true|false` for lib/firebase_options_dev.dart.

false while any value still starts with TODO_ (the tashil-gift-dev web app
config was not filled in yet). Never fails: CI uses the output to skip the
dev deploy instead of going red.
"""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "lib/firebase_options_dev.dart"
try:
    src = open(path, encoding="utf-8").read()
except FileNotFoundError:
    print("configured=false")
    sys.exit(0)
web = re.search(r"FirebaseOptions\s+web\s*=\s*FirebaseOptions\((.*?)\);", src, re.S)
body = web.group(1) if web else ""
values = re.findall(r"\w+:\s*'([^']*)'", body)
ok = bool(values) and all(v and not v.startswith("TODO_") for v in values) \
    and "projectId: 'tashil-gift-dev'" in body
print(f"configured={'true' if ok else 'false'}")
