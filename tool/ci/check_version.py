#!/usr/bin/env python3
"""Checks the app version the repo's release rule keeps in three places.

The rule (.agents/rules/deployment-and-git-permission-standard.md): every
release bumps patch + buildNumber in lib/core/constants/app_version_config.dart,
pubspec.yaml `version:` and web/version.json (served no-cache; the web app's
update checker compares it with the running build). CI never bumps or commits
the version itself; it only verifies.

  check_version.py                     the three sources agree
  check_version.py --built build/web   ... and the built version.json matches
  check_version.py --newer-than URL    ... and is strictly newer than the live
                                       version.json (production deploys)
Prints `version=X.Y.Z+N` for $GITHUB_OUTPUT.
"""
import json, re, sys, urllib.request

def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)

def parse(s):
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)\+(\d+)", s)
    return tuple(int(x) for x in m.groups()) if m else None

def from_version_json(text, where):
    d = json.loads(text)
    v = f"{d.get('version', '')}+{d.get('build_number', '')}"
    if not parse(v):
        fail(f"{where}: cannot read version/build_number ({v})")
    return v, d

args = sys.argv[1:]
pub = re.search(r"^version:\s*(\S+)", open("pubspec.yaml", encoding="utf-8").read(), re.M)
pub = pub.group(1) if pub else ""
cfg_src = open("lib/core/constants/app_version_config.dart", encoding="utf-8").read()
def const(name):
    m = re.search(rf"static const int {name}\s*=\s*(\d+);", cfg_src)
    return m.group(1) if m else "?"
cfg = f"{const('major')}.{const('minor')}.{const('patch')}+{const('buildNumber')}"
web, web_d = from_version_json(open("web/version.json", encoding="utf-8").read(), "web/version.json")

print(f"pubspec.yaml            {pub}")
print(f"app_version_config.dart {cfg}")
print(f"web/version.json        {web}")
if not (pub == cfg == web) or not parse(pub):
    fail("version mismatch: pubspec.yaml, app_version_config.dart and web/version.json must carry the same X.Y.Z+N. Bump all three in the release PR (see .agents/rules/deployment-and-git-permission-standard.md).")

rel = re.search(r"releaseDate\s*=\s*'([^']*)'", cfg_src)
if rel and web_d.get("build_date") != rel.group(1):
    print(f"::warning::releaseDate ({rel.group(1)}) and web/version.json build_date ({web_d.get('build_date')}) differ")

if "--built" in args:
    d = args[args.index("--built") + 1]
    built, _ = from_version_json(open(f"{d}/version.json", encoding="utf-8").read(), f"{d}/version.json")
    print(f"{d}/version.json  {built}")
    if built != pub:
        fail(f"built version.json is {built}, expected {pub}")

if "--newer-than" in args:
    url = args[args.index("--newer-than") + 1]
    with urllib.request.urlopen(f"{url}?t=ci", timeout=20) as r:
        live, _ = from_version_json(r.read().decode(), url)
    print(f"live {url}  {live}")
    if parse(pub) <= parse(live):
        fail(f"{pub} is not newer than the live {live}. Bump patch + buildNumber in all three files before deploying to production (a rollback uses workflow_dispatch with allow_older_version).")

print(f"version={pub}")
