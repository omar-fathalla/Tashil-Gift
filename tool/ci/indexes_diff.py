#!/usr/bin/env python3
"""TAG-76: compare live Firestore indexes with firestore.indexes.json.

usage: indexes_diff.py LIVE_JSON FILE_JSON
LIVE_JSON is the output of `firebase firestore:indexes --project <id>`.
Prints Markdown; exit code is always 0 (information only).
"""
import json
import sys


def key(ix):
    fields = tuple(
        (f.get("fieldPath"), f.get("order") or f.get("arrayConfig") or f.get("vectorConfig") and "vector")
        for f in ix.get("fields", [])
        if f.get("fieldPath") != "__name__"
    )
    return (ix.get("collectionGroup"), ix.get("queryScope", "COLLECTION"), fields)


def label(k):
    coll, scope, fields = k
    return f"`{coll}` ({scope}): " + ", ".join(f"{p} {o}" for p, o in fields)


def load(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    start = text.find("{")  # firebase-tools may print a banner first
    return json.loads(text[start:]).get("indexes", [])


def main(live_path, file_path):
    live = {key(i) for i in load(live_path)}
    want = {key(i) for i in load(file_path)}
    missing = sorted(want - live, key=str)
    extra = sorted(live - want, key=str)
    print("### Firestore indexes: tashil-gift vs firestore.indexes.json")
    print(f"- In the file: {len(want)}; live: {len(live)}")
    print(f"- In the file but NOT live (a deploy adds them): {len(missing)}")
    for k in missing:
        print(f"  - {label(k)}")
    print(f"- Live but not in the file (kept; deploy never deletes): {len(extra)}")
    for k in extra:
        print(f"  - {label(k)}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
