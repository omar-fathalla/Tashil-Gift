#!/usr/bin/env python3
"""Writes firebase.dev.json: firebase.json with every production-only value
switched to tashil-gift-dev.

firebase.json pins the Storage rules to the production bucket
(tashil-gift.firebasestorage.app). Deploying `storage` with it would hit
production, so every dev deploy uses `--config firebase.dev.json` instead.
firebase.json itself is never changed (production stays byte-for-byte the same).

  python3 tool/dev/render_firebase_dev_json.py   # -> firebase.dev.json (gitignored)
"""
import json, os, sys

# The repo root: the current directory when it holds firebase.json (CI runs
# the scripts from a separate checkout), else this script's repository.
ROOT = os.getcwd() if os.path.isfile("firebase.json") else \
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROD_BUCKET = "tashil-gift.firebasestorage.app"
DEV_BUCKET = os.environ.get("DEV_STORAGE_BUCKET", "tashil-gift-dev.firebasestorage.app")

src = os.path.join(ROOT, "firebase.json")
dst = os.path.join(ROOT, sys.argv[1] if len(sys.argv) > 1 else "firebase.dev.json")
with open(src, encoding="utf-8") as f:
    cfg = json.load(f)

storage = cfg.get("storage")
if isinstance(storage, dict):
    storage = [storage]
for entry in storage or []:
    if entry.get("bucket") == PROD_BUCKET:
        entry["bucket"] = DEV_BUCKET
cfg["storage"] = storage

text = json.dumps(cfg, indent=2, ensure_ascii=False)
# The CSP allows *.cloudfunctions.net already; list the dev functions origin
# next to the prod one so the dev site may call its own functions directly.
text = text.replace(
    "https://us-central1-tashil-gift.cloudfunctions.net",
    "https://us-central1-tashil-gift.cloudfunctions.net https://us-central1-tashil-gift-dev.cloudfunctions.net",
)
if PROD_BUCKET in text:
    print("::error::firebase.dev.json still references the production bucket")
    sys.exit(1)
with open(dst, "w", encoding="utf-8") as f:
    f.write(text + "\n")
print(f"wrote {os.path.relpath(dst, ROOT)} (storage bucket {DEV_BUCKET})")
