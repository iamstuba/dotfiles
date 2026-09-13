#!/bin/sh
# Smoke test: parses the manifest and runs every script dry. One file,
# extended by each area, so `mise run check` stays one command.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

for f in install.sh tests/smoke.sh bin/*; do
  [ -f "$f" ] || continue
  case "$(head -n 1 "$f")" in
    *bash*) bash -n "$f" || fail "syntax $f" ;;
    *) sh -n "$f" || fail "syntax $f" ;;
  esac
done
ok "syntax"

# tomllib needs Python 3.11; the CLT ships 3.9, so a fresh Mac skips this and
# relies on the mise dry-run below.
if python3 -c 'import tomllib' 2>/dev/null; then
python3 - <<'PY' || fail "manifest shape"
import sys, tomllib, pathlib

def load(p):
    with open(p, "rb") as f:
        return tomllib.load(f)

root = load("mise.toml")
global_cfg = load("config/mise/config.toml")
work = load("config/mise/config.work.toml")
errs = []

if "dotfiles" in global_cfg or "bootstrap" in global_cfg:
    errs.append("global file carries dotfiles or bootstrap; those belong in mise.toml")
if "tools" in global_cfg and next(iter(global_cfg["tools"])) != "node":
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

age = global_cfg.get("settings", {}).get("minimum_release_age")
if not isinstance(age, str):
    errs.append(f"minimum_release_age must be a duration string, got {age!r}")

for name in ("bootstrap", "setup-git", "refresh-unslop", "check"):
    if name not in root.get("tasks", {}):
        errs.append(f"repo-root task missing: {name}")
for name in ("update:tools", "update:apps", "update:plugins", "update:dotfiles", "update:all", "setup-agents"):
    if name not in global_cfg.get("tasks", {}):
        errs.append(f"global task missing: {name}")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
PY
ok "manifest shape"
else
  printf 'skip manifest shape: python3 has no tomllib\n'
fi

# HOME is a temp directory so nothing on this Mac is read as state.
tmp_home=$(mktemp -d)
trap 'rm -rf "$tmp_home"' EXIT

out=$(HOME=$tmp_home sh bin/macos-post-defaults --dry-run) || fail "macos-post-defaults --dry-run"
echo "$out" | grep -q 'persistent-apps -array' || fail "post-defaults: Dock array write missing"
echo "$out" | grep -q 'dict-add 64 ' || fail "post-defaults: hotkey 64 missing"
echo "$out" | grep -q 'dict-add 65 ' || fail "post-defaults: hotkey 65 missing"
ok "macos-post-defaults --dry-run"

out=$(HOME=$tmp_home GIT_NAME=Test GIT_EMAIL=test@example.com GIT_PROFILES='~/Work=work@example.com' \
  DOTFILES=$root sh bin/setup-git --dry-run) || fail "setup-git --dry-run"
echo "$out" | grep -q -- '--type authentication' || fail "setup-git: authentication key registration missing"
echo "$out" | grep -q -- '--type signing' || fail "setup-git: signing key registration missing"
echo "$out" | grep -q 'write .*/.gitconfig-local' || fail "setup-git: local gitconfig write missing"
echo "$out" | grep -q 'write .*/.gitconfig-work' || fail "setup-git: profile file write missing"
ok "setup-git --dry-run"

out=$(HOME=$tmp_home DOTFILES=$root DOTFILES_WORK=0 GIT_NAME=Test GIT_EMAIL=test@example.com GIT_PROFILES= \
  sh install.sh --dry-run) || fail "install.sh --dry-run"
echo "$out" | grep -q 'ssh-keygen' || fail "install: key generation missing"
echo "$out" | grep -q 'bootstrap --yes' || fail "install: bootstrap command missing"
echo "$out" | grep -q 'run setup-git' || fail "install: setup-git command missing"
echo "$out" | grep -q 'env = \["work"\]' && fail "install: wrote the work overlay on a personal answer"
out=$(HOME=$tmp_home DOTFILES=$root DOTFILES_WORK=1 GIT_NAME=Test GIT_EMAIL=test@example.com GIT_PROFILES= \
  sh install.sh --dry-run) || fail "install.sh --dry-run (work)"
echo "$out" | grep -q 'env = \["work"\]' || fail "install: work answer did not write miserc.toml"
sh install.sh --bogus >/dev/null 2>&1 && fail "install: unknown argument accepted"
ok "install.sh --dry-run"

# The real parser, when a mise exists. The rehearsal is where this runs.
if command -v mise >/dev/null 2>&1; then
  mise bootstrap --dry-run >/dev/null || fail "mise bootstrap --dry-run"
  ok "mise bootstrap --dry-run"
else
  printf 'skip mise bootstrap --dry-run: mise is not on PATH\n'
fi
