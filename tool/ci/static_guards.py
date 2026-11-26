#!/usr/bin/env python3
"""Static guards (gate tool 3, TAG-82). Read-only: never edits a file.

Checks the tracked files of the repo (or a test fixture directory) for:

  firebase-project  every Firebase CLI call in scripts and workflows names a
                    project with --project/-P, and that project is
                    tashil-gift-dev, a demo-* emulator project, or a variable
                    the same file sets only to those.
  prod-project      the production project id `tashil-gift` (not
                    `tashil-gift-dev`) in a script, workflow or test tool.
  secret            private keys, service account JSON, GitHub/OpenAI tokens,
                    and Google API keys outside the public Firebase web config.

A finding that is intended (the production deploy workflow, the legacy
preview channel, the seed script's refusal list...) is listed in
tool/ci/guards_allowlist.txt with a reason. Changing that list, or
.github/workflows/deploy-production.yml, is Mohamed's decision.

Usage: python3 tool/ci/static_guards.py [--root DIR] [--allowlist FILE] [--files F...]
Exit 0 = clean, 1 = findings, 2 = usage error.
"""
from __future__ import annotations

import argparse
import fnmatch
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# Files the firebase-project and prod-project checks read: code that runs
# commands or talks to a backend outside the Flutter app itself.
SCRIPT_GLOBS = [
    ".github/workflows/*.yml",
    ".github/workflows/*.yaml",
    "tool/**",
    "functions/scripts/**",
    "functions/package.json",
    "rules-tests/**",
    "package.json",
    "*.sh",
    "firebase*.json",
]
SCRIPT_EXTS = {".yml", ".yaml", ".sh", ".bash", ".js", ".mjs", ".cjs", ".ts", ".py", ".json", ".dart", ""}
SKIP_GLOBS = ["**/node_modules/**", "**/package-lock.json", "**/*.md", "backups/**", "build/**"]

PROD_RE = re.compile(r"(?<![\w.])(?<!demo-)tashil-gift(?![-\w])")
ALLOWED_PROJECT_RE = re.compile(r"^(tashil-gift-dev|demo-[a-z0-9-]+)$")

# A Firebase CLI call: `firebase <cmd>` or `npx [-y] "firebase-tools@x" <cmd>`.
FIREBASE_CALL_RE = re.compile(
    r"""(?:^|[\s;&|(`"'])(?:npx\s+(?:-y\s+)?["']?firebase-tools(?:@[^\s"']*)?["']?|firebase)\s+"""
    r"""(?P<cmd>deploy|emulators:\S+|functions:\S+|firestore:\S+|hosting:\S+|database:\S+|auth:\S+|"""
    r"""storage:\S+|apps:\S+|remoteconfig:\S+|ext:\S+|use|target:\S+|projects:\S+)"""
)
PROJECT_ARG_RE = re.compile(r"""(?:--project|-P)(?:\s+|=)["']?(?P<val>[^\s"'\\]+)""")
# Commands that never touch a project.
PROJECTLESS_CMDS = {"projects:list"}

SECRET_PATTERNS = [
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("service account JSON", re.compile(r"\"type\"\s*:\s*\"service_account\"")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("OpenAI-style key", re.compile(r"\bsk-[A-Za-z0-9]{32,}\b")),
    ("Google API key", re.compile(r"AIza[0-9A-Za-z_\-]{35}")),
]
# The public Firebase web config is meant to ship in the app.
GOOGLE_KEY_OK = {"lib/firebase_options.dart", "lib/firebase_options_dev.dart"}


@dataclass
class Finding:
    check: str
    path: str
    line: int
    text: str
    why: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: [{self.check}] {self.why}\n    {self.text.strip()[:200]}"


@dataclass
class AllowRule:
    check: str
    path_glob: str
    needle: str  # substring of the line; "*" = any line of the file
    reason: str
    used: bool = False

    def matches(self, f: Finding) -> bool:
        if f.check != self.check or not fnmatch.fnmatch(f.path, self.path_glob):
            return False
        return self.needle == "*" or self.needle in f.text


def load_allowlist(path: Path) -> list[AllowRule]:
    """One rule per line: check | path glob | line substring or * | reason
    (fields are separated by a | with spaces around it)."""
    rules = []
    if not path.exists():
        return rules
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in re.split(r"\s+\|\s+", line, maxsplit=3)]
        if len(parts) != 4 or not all(parts):
            raise SystemExit(f"{path}:{n}: need 'check | path | needle | reason', got: {raw}")
        rules.append(AllowRule(*parts))
    return rules


def tracked_files(root: Path) -> list[str]:
    try:
        out = subprocess.run(["git", "ls-files"], cwd=root, check=True, capture_output=True, text=True).stdout
        files = out.splitlines()
    except (subprocess.CalledProcessError, FileNotFoundError):
        files = [str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()]
    return sorted(f for f in files if not any(fnmatch.fnmatch(f, g) for g in SKIP_GLOBS))


def is_script(path: str) -> bool:
    if not any(fnmatch.fnmatch(path, g) for g in SCRIPT_GLOBS):
        return False
    return Path(path).suffix in SCRIPT_EXTS


def is_comment(line: str) -> bool:
    s = line.lstrip()
    return s.startswith(("#", "//", "/*", "* ", "*/")) or s == "*"


def is_label(line: str) -> bool:
    """A workflow step or job title line (`- name: ...`), not a command."""
    return re.match(r"^\s*-?\s*name:", line) is not None


def logical_lines(text: str):
    """Yields (first_line_no, joined_text), joining shell `\\` continuations."""
    buf, start = [], 0
    for n, line in enumerate(text.splitlines(), 1):
        if not buf:
            start = n
        if line.rstrip().endswith("\\"):
            buf.append(line.rstrip()[:-1])
            continue
        buf.append(line)
        yield start, " ".join(buf)
        buf = []
    if buf:
        yield start, " ".join(buf)


def var_values(text: str, name: str) -> list[str]:
    """Values a file gives NAME: `NAME=v`, `NAME: v`, `NAME="${1:-v}"`."""
    vals = []
    for m in re.finditer(rf"""(?m)^\s*(?:export\s+)?{re.escape(name)}\s*[:=]\s*["']?(?P<v>[^\s"'#]+)""", text):
        v = m.group("v")
        d = re.match(r"\$\{\w+:-([^}]+)\}", v)
        vals.append(d.group(1) if d else v)
    return vals


def check_project_value(val: str, text: str) -> str | None:
    """None if the --project value is safe, else the reason."""
    if val.startswith("${{"):
        return "project from a GitHub expression; name tashil-gift-dev or demo-* in the file instead"
    var = re.fullmatch(r"\$\{?(\w+)\}?", val)
    if var:
        vals = var_values(text, var.group(1))
        if not vals:
            return f"${var.group(1)} is not set in this file to tashil-gift-dev or demo-*"
        bad = [v for v in vals if not ALLOWED_PROJECT_RE.match(v)]
        return f"${var.group(1)} can be {', '.join(bad)}" if bad else None
    return None if ALLOWED_PROJECT_RE.match(val) else f"--project {val} is not tashil-gift-dev or demo-*"


def scan_file(path: str, text: str) -> list[Finding]:
    out: list[Finding] = []
    script = is_script(path)
    lines = text.splitlines()

    if script:
        for n, line in enumerate(lines, 1):
            if not is_comment(line) and PROD_RE.search(line):
                out.append(Finding("prod-project", path, n, line, "production project id tashil-gift"))
        for n, joined in logical_lines(text):
            if is_comment(joined) or is_label(joined):
                continue
            for m in FIREBASE_CALL_RE.finditer(joined):
                if m.group("cmd") in PROJECTLESS_CMDS:
                    continue
                proj = PROJECT_ARG_RE.search(joined, m.end())
                if not proj:
                    out.append(Finding("firebase-project", path, n, joined, f"firebase {m.group('cmd')} without --project"))
                    continue
                why = check_project_value(proj.group("val"), text)
                if why:
                    out.append(Finding("firebase-project", path, n, joined, why))

    for n, line in enumerate(lines, 1):
        for label, rx in SECRET_PATTERNS:
            if rx.search(line):
                if label == "Google API key" and path in GOOGLE_KEY_OK:
                    continue
                out.append(Finding("secret", path, n, line, label))
    return out


def run(root: Path, allowlist: Path, files: list[str] | None) -> int:
    rules = load_allowlist(allowlist)
    findings: list[Finding] = []
    for rel in files if files is not None else tracked_files(root):
        p = root / rel
        if not p.is_file():
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        findings += scan_file(rel, text)

    left = []
    for f in findings:
        rule = next((r for r in rules if r.matches(f)), None)
        if rule:
            rule.used = True
        else:
            left.append(f)

    for r in rules:
        if not r.used and files is None:
            print(f"note: allowlist rule matches nothing any more, remove it: {r.check} | {r.path_glob} | {r.needle}")
    if left:
        print(f"static guards: {len(left)} finding(s)\n")
        for f in left:
            print(f, "\n")
        print("Fix the line, or, if it is intended, add a rule with the reason to tool/ci/guards_allowlist.txt.")
        return 1
    print(f"static guards: OK ({len(findings)} allowlisted)")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    here = Path(__file__).resolve().parent
    ap.add_argument("--root", type=Path, default=Path.cwd())
    ap.add_argument("--allowlist", type=Path, default=here / "guards_allowlist.txt")
    ap.add_argument("--files", nargs="*", help="only these paths (relative to --root)")
    a = ap.parse_args(argv)
    return run(a.root.resolve(), a.allowlist, a.files)


if __name__ == "__main__":
    sys.exit(main())
