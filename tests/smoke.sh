#!/bin/sh
# Smoke test for the manifest and installer area. Parses the manifest and
# runs every script in dry-run mode. Extended by each area, never split.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

# 1. Every script parses.
for f in install.sh tests/smoke.sh bin/*; do
  [ -f "$f" ] || continue
  case "$(head -n 1 "$f")" in
    *bash*) bash -n "$f" || fail "syntax $f" ;;
    *) sh -n "$f" || fail "syntax $f" ;;
  esac
done
ok "syntax"

# 2. The manifest has the shape the loader expects.
python3 - <<'PY' || fail "manifest shape"
import sys, tomllib, pathlib

def load(p):
    with open(p, "rb") as f:
        return tomllib.load(f)

root = load("mise.toml")
glob = load("config/mise/config.toml")
work = load("config/mise/config.work.toml")
errs = []

if "dotfiles" in glob or "bootstrap" in glob:
    errs.append("global file carries dotfiles or bootstrap; those belong in mise.toml")
if "tools" in glob and next(iter(glob["tools"])) != "node":
    errs.append("node must be the first tool so npm: tools run on it")
if "tools" in root:
    errs.append("repo-root file carries tools; they are only on PATH inside the clone")
if set(work) - {"tools", "bootstrap"}:
    errs.append(f"overlay carries unexpected tables: {sorted(set(work) - {'tools', 'bootstrap'})}")

for target, src in root.get("dotfiles", {}).items():
    source = src if isinstance(src, str) else src.get("source", "")
    if any(c in target + source for c in "*?["):
        errs.append(f"wildcard in dotfiles entry {target}")
    if not pathlib.Path(source).exists():
        errs.append(f"dotfiles source missing: {source} (each area adds its own lines)")

for domain, keys in root["bootstrap"]["macos"].get("defaults", {}).items():
    for key, value in keys.items():
        if not isinstance(value, (bool, int, float, str)):
            errs.append(f"defaults {domain}.{key} is a {type(value).__name__}; mise skips arrays and dicts")

hooks = set(root["bootstrap"].get("hooks", {}))
if hooks != {"pre-packages", "post-defaults", "final"}:
    errs.append(f"hooks are {sorted(hooks)}")

age = glob.get("settings", {}).get("minimum_release_age")
if not isinstance(age, str):
    errs.append(f"minimum_release_age must be a duration string, got {age!r}")

for name in ("bootstrap", "setup-git", "refresh-unslop", "check"):
    if name not in root.get("tasks", {}):
        errs.append(f"repo-root task missing: {name}")
for name in ("update:tools", "update:apps", "update:plugins", "update:dotfiles", "update:all", "setup-agents"):
    if name not in glob.get("tasks", {}):
        errs.append(f"global task missing: {name}")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
PY
ok "manifest shape"

# 3. The real parser, when a mise exists. On the work laptop this is skipped;
#    the rehearsal on the personal Mac is where it runs.
if command -v mise >/dev/null 2>&1; then
  mise bootstrap --dry-run >/dev/null || fail "mise bootstrap --dry-run"
  ok "mise bootstrap --dry-run"
else
  printf 'skip mise bootstrap --dry-run: mise is not on PATH\n'
fi
