#!/usr/bin/env python3
"""Stamps the environment into a built web/version.json.

  stamp_env.py build/web dev    -> env "dev",  environment "Development (tashil-gift-dev)"
  stamp_env.py build/web prod   -> env "prod", environment "Production (Firebase)"

Only the built copy is changed (the repo's web/version.json stays env "prod").
Version fields are never touched.
"""
import json, sys

LABELS = {"prod": "Production (Firebase)", "dev": "Development (tashil-gift-dev)"}

if len(sys.argv) != 3 or sys.argv[2] not in LABELS:
    print("usage: stamp_env.py <build/web> <prod|dev>")
    sys.exit(2)
path = f"{sys.argv[1]}/version.json"
env = sys.argv[2]
with open(path, encoding="utf-8") as f:
    d = json.load(f)
d["env"] = env
d["environment"] = LABELS[env]
with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"{path}: env={env}")
