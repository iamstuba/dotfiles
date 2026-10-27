#!/bin/sh
# Smoke test: parses the manifest and runs every script, dry or, for the
# installer and setup-git, for real against stubs. One file, extended by each
# area, so `mise run check` stays one command.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

# mise looks for config in every directory above the one it runs in, and a
# clone under a bootstrapped HOME has ~/.config/mise/config.toml above it. A
# temp HOME does not hide that file, so every mise run below that is meant to
# see only this repo stops its search here.
mise_ceiling=$(dirname "$root")

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

for f in install.sh tests/smoke.sh bin/*; do
  [ -f "$f" ] || continue
  case "$(head -n 1 "$f")" in
    *bash*) bash -n "$f" || fail "syntax $f" ;;
    *) sh -n "$f" || fail "syntax $f" ;;
  esac
done
# The zsh files carry no shebang, because they are sourced and never run.
if command -v zsh >/dev/null 2>&1; then
  for f in home/.zshenv config/zsh/.zprofile config/zsh/.zshrc \
           config/zsh/aliases.zsh config/zsh/functions.zsh; do
    [ -f "$f" ] || continue
    zsh -n "$f" || fail "syntax $f"
  done
fi
ok "syntax"

# Every tracked TOML and YAML file reaches python through `yq -o json`. A
# fresh Mac's python is the CLT's 3.9, which carries json and neither tomllib
# nor PyYAML, so this block and the two YAML probes below skipped on every
# machine this repo has ever run on. yq is in [tools]; the guard below is what
# catches its absence, because the inventory block at the end only checks that
# tools resolved on a machine that has mise.
command -v yq >/dev/null 2>&1 \
  || fail "yq is not on PATH; it is in [tools] and every config probe here reads through it"

# One file at a time, and never as `yq ... | python3`. This file is sh with
# set -eu and no pipefail, so a pipeline reports only python's status and a yq
# failure would pass the moment the python side tolerated empty stdin.
root_json=$(yq -p toml -o json mise.toml) || fail "mise.toml does not parse"
global_json=$(yq -p toml -o json config/mise/config.toml) || fail "config/mise/config.toml does not parse"
work_json=$(yq -p toml -o json config/mise/config.work.toml) || fail "config/mise/config.work.toml does not parse"
global_personal_json=$(yq -p toml -o json config/mise/config.personal.toml) || fail "config/mise/config.personal.toml does not parse"
root_work_json=$(yq -p toml -o json mise.work.toml) || fail "mise.work.toml does not parse"
personal_json=$(yq -p toml -o json mise.personal.toml) || fail "mise.personal.toml does not parse"

# The shell area's tracked TOML, each one optional and each parsed on its own
# so a failure names the file. Absent is the JSON null, never an empty string:
# empty would let a yq that exited 0 with no output skip a file quietly, which
# is the failure this whole port exists to remove.
starship_json=null yazi_json=null tuicr_json=null
if [ -f config/starship.toml ]; then
  starship_json=$(yq -p toml -o json config/starship.toml) || fail "config/starship.toml does not parse"
fi
if [ -f config/yazi/theme.toml ]; then
  yazi_json=$(yq -p toml -o json config/yazi/theme.toml) || fail "config/yazi/theme.toml does not parse"
fi
if [ -f config/tuicr/config.toml ]; then
  tuicr_json=$(yq -p toml -o json config/tuicr/config.toml) || fail "config/tuicr/config.toml does not parse"
fi

ROOT_JSON=$root_json ROOT_WORK_JSON=$root_work_json PERSONAL_JSON=$personal_json GLOBAL_JSON=$global_json WORK_JSON=$work_json \
GLOBAL_PERSONAL_JSON=$global_personal_json \
STARSHIP_JSON=$starship_json YAZI_JSON=$yazi_json TUICR_JSON=$tuicr_json \
python3 - <<'PY' || fail "manifest shape"
import sys, os, json, pathlib, re

root = json.loads(os.environ["ROOT_JSON"])
global_cfg = json.loads(os.environ["GLOBAL_JSON"])
work = json.loads(os.environ["WORK_JSON"]) or {}  # yq reads an empty file as null
root_work = json.loads(os.environ["ROOT_WORK_JSON"])
personal = json.loads(os.environ["PERSONAL_JSON"])
global_personal = json.loads(os.environ["GLOBAL_PERSONAL_JSON"])
errs = []

if "dotfiles" in global_cfg or "bootstrap" in global_cfg:
    errs.append("global file carries dotfiles or bootstrap; those belong in mise.toml")
if "tools" in global_cfg and next(iter(global_cfg["tools"])) != "node":
    errs.append("node must be the first tool so npm: tools run on it")
if "tools" in root:
    errs.append("repo-root file carries tools; they are only on PATH inside the clone")
if set(work) - {"tools", "bootstrap", "env"}:
    errs.append(f"overlay carries unexpected tables: {sorted(set(work) - {'tools', 'bootstrap', 'env'})}")
# Only the work Mac uses gitlab.com, so glab and its env live in this overlay
# and nowhere a personal Mac loads.
if work.get("tools", {}).get("gitlab:gitlab-org/cli") != "latest":
    errs.append("work overlay does not declare \"gitlab:gitlab-org/cli\" = \"latest\", so the work Mac has no glab")
if work.get("env", {}).get("GLAB_SEND_TELEMETRY") != "0":
    errs.append("work overlay does not set GLAB_SEND_TELEMETRY = \"0\", so glab reports usage")
if work.get("env", {}).get("GLAB_CONFIG_DIR") != "{{ env.HOME }}/.config/glab-cli":
    errs.append("work overlay does not pin GLAB_CONFIG_DIR to ~/.config/glab-cli, so a GUI-launched glab misses the login")
for p in sorted([*pathlib.Path(".").glob("mise*.toml"), *pathlib.Path("config/mise").glob("*.toml")]):
    if p != pathlib.Path("config/mise/config.work.toml") and "gitlab:" in p.read_text():
        errs.append(f"{p} names gitlab:, which belongs only in config/mise/config.work.toml")
if set(root_work) - {"bootstrap", "dotfiles"}:
    errs.append(f"repo-root overlay carries more than packages and its link: {sorted(set(root_work) - {'bootstrap', 'dotfiles'})}")
# Its one row links the global overlay. Any other row belongs in mise.toml or
# mise.personal.toml, and without this one the work overlay stops loading.
if set(root_work.get("dotfiles", {})) != {"~/.config/mise/config.work.toml"}:
    errs.append(f"mise.work.toml's dotfiles are {sorted(root_work.get('dotfiles', {}))}, not just config.work.toml, so the work overlay stops loading or carries another Mac's link")
for target in root_work.get("dotfiles", {}):
    if target in root.get("dotfiles", {}):
        errs.append(f"{target} is in both mise.toml and mise.work.toml, so personal gets it too")
if set(root_work.get("bootstrap", {})) - {"packages"}:
    errs.append("repo-root overlay's bootstrap carries more than packages")
# An entry there outranks mise.toml, so it may only turn a declared package off.
for pkg, spec in root_work.get("bootstrap", {}).get("packages", {}).items():
    if spec != {"state": "absent"}:
        errs.append(f"repo-root overlay entry {pkg} should only set state = \"absent\"")
    if pkg not in root.get("bootstrap", {}).get("packages", {}):
        errs.append(f"repo-root overlay marks {pkg} absent, which mise.toml never declares")
# LibreWolf is the personal Mac's one browser and Chrome the work Mac's, so
# the cask sits in mise.toml with an absent line in the work overlay.
# LibreWolf replaced Zen, so neither file may name Zen again, even in a comment.
if root.get("bootstrap", {}).get("packages", {}).get("brew-cask:librewolf") != "latest":
    errs.append("mise.toml does not declare brew-cask:librewolf = \"latest\", so a personal Mac loses its daily browser")
if root_work.get("bootstrap", {}).get("packages", {}).get("brew-cask:librewolf") != {"state": "absent"}:
    errs.append("mise.work.toml does not mark brew-cask:librewolf absent, so the work Mac gets it")
for name in ("mise.toml", "mise.work.toml"):
    if re.search(r"\bzen\b", pathlib.Path(name).read_text(), re.I):
        errs.append(f"{name} names Zen, which LibreWolf replaced")
# The personal overlay adds dotfiles and hooks. One also in mise.toml would
# reach the work Mac anyway, which is the one thing this file exists to prevent.
if set(personal) - {"dotfiles", "bootstrap"}:
    errs.append(f"personal overlay carries unexpected tables: {sorted(set(personal) - {'dotfiles', 'bootstrap'})}")
if set(personal.get("bootstrap", {})) - {"hooks"}:
    errs.append("personal overlay's bootstrap carries more than hooks")
if "remove-bundled-apps" not in json.dumps(personal.get("bootstrap", {}).get("hooks", {})):
    errs.append("personal overlay no longer runs remove-bundled-apps")
if "remove-bundled-apps" in json.dumps(root.get("bootstrap", {}).get("hooks", {})):
    errs.append("mise.toml runs remove-bundled-apps, so the work Mac loses its apps too")
if "librewolf-policies" not in json.dumps(personal.get("bootstrap", {}).get("hooks", {})):
    errs.append("personal overlay no longer runs librewolf-policies, so Proton Pass and Refined GitHub never install")
if "librewolf-policies" in json.dumps(root.get("bootstrap", {}).get("hooks", {})):
    errs.append("mise.toml runs librewolf-policies, so the work Mac gets a LibreWolf domain")
for target in personal.get("dotfiles", {}):
    if target in root.get("dotfiles", {}):
        errs.append(f"{target} is in both mise.toml and mise.personal.toml, so work gets it too")
if "~/.config/mise/config.personal.toml" not in personal.get("dotfiles", {}):
    errs.append("mise.personal.toml no longer links config.personal.toml, so a personal Mac loses pi")

# pi is personal-only. Anything of pi's in either half of the manifest reaches
# the work Mac, because mise cannot switch off what a loaded file declares.
def strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for v in x.values():
            yield from strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from strings(v)

pi_cmd = re.compile(r"(?:^|[\s;&|(`])pi(?:\s|$)|~/\.pi\b")
for name, cfg in (("config/mise/config.toml", global_cfg), ("mise.toml", root)):
    for key in cfg.get("tools", {}):
        if re.split(r"[:/]", key)[-1] in ("pi", "pi-coding-agent"):
            errs.append(f"{name} declares {key}; pi is in config.personal.toml")
    if "pi" in cfg.get("settings", {}).get("minimum_release_age_excludes", []):
        errs.append(f"{name} excludes pi from the release age; config.personal.toml does")
    for target in cfg.get("dotfiles", {}):
        if target == "~/.pi" or target.startswith("~/.pi/"):
            errs.append(f"{name} links {target}; pi's links are in mise.personal.toml")
    for text in strings([cfg.get("tasks", {}), cfg.get("bootstrap", {}).get("hooks", {})]):
        for line in text.splitlines():
            if pi_cmd.search(line):
                errs.append(f"{name} runs pi: {line.strip()!r}")

# The global personal overlay holds pi's tool, its exclude and its tasks. A
# block named after a config.toml task may carry depends_post and nothing
# else: run or description there replaces the task instead of adding to it.
if set(global_personal) - {"tools", "settings", "tasks"}:
    errs.append(f"config.personal.toml carries unexpected tables: {sorted(set(global_personal) - {'tools', 'settings', 'tasks'})}")
for name, task in global_personal.get("tasks", {}).items():
    if name in global_cfg.get("tasks", {}) and set(task) != {"depends_post"}:
        errs.append(f"config.personal.toml's {name} carries {sorted(task)}, not only depends_post")
    for dep in task.get("depends_post", []):
        if dep not in global_personal.get("tasks", {}):
            errs.append(f"config.personal.toml's {name} runs {dep} after it, which the file never defines")

for target, src in {**root.get("dotfiles", {}), **personal.get("dotfiles", {}), **root_work.get("dotfiles", {})}.items():
    source = src if isinstance(src, str) else src.get("source", "")
    if any(c in target + source for c in "*?["):
        errs.append(f"wildcard in dotfiles entry {target}")
    if not pathlib.Path(source).exists():
        errs.append(f"dotfiles source missing: {source} (each area adds its own lines)")

for domain, keys in root["bootstrap"]["macos"].get("defaults", {}).items():
    for key, value in keys.items():
        if not isinstance(value, (bool, int, float, str)):
            errs.append(f"defaults {domain}.{key} is a {type(value).__name__}; mise skips arrays and dicts")

# Onboarding state and usage history would carry this Mac's state to the next
# one. The audio priority device lists would too, and the scalar check above
# already refuses them.
vorssaint = root["bootstrap"]["macos"].get("defaults", {}).get("com.vorssaint.utils", {})
for key in {"hasOnboarded", "commandBarQueryHabits", "commandBarUsage"} & set(vorssaint):
    errs.append(f"defaults com.vorssaint.utils.{key} is this Mac's state, not a setting")
# The app stores the hold as a float, and mise would write 250 as an integer.
if not isinstance(vorssaint.get("quitProtectionQuitHoldDurationMs"), float):
    errs.append("defaults com.vorssaint.utils.quitProtectionQuitHoldDurationMs is missing or not a float")

hooks = set(root["bootstrap"].get("hooks", {}))
if hooks != {"pre-packages", "post-defaults", "final"}:
    errs.append(f"hooks are {sorted(hooks)}")

# mise resolves a brew package through its tap's published api/ JSON and, when
# that 404s, by evaluating the .rb, which wants Ruby 3 or newer against the 2.6
# macOS ships. A tap is not required to publish that JSON and neither of the
# two this repo uses does, so a tap entry here fails the packages phase
# outright, on a real run as much as a dry one. Measured both ways:
# brew:FelixKratz/formulae/sketchybar and brew-cask:nikitabobko/tap/aerospace
# fail identically, so casks are no exception and the rule covers both
# prefixes. It is deliberately broader than the measurement: a tap that does
# publish api/ JSON would resolve, and this still rejects it. Lift the rule
# when such a tap is actually wanted, rather than leaving the door open now.
for key in root["bootstrap"].get("packages", {}):
    backend, _, name = key.partition(":")
    if backend in ("brew", "brew-cask") and "/" in name:
        errs.append(f"{key} names a third-party tap, which mise cannot resolve. "
                    "Install it from bin/brew-tap-packages instead")

# bin/brew-tap-packages is the only path to those packages, and the same
# script upgrades them, so the hook must still reach it. mise also accepts a
# bare string or an array here; this hook is a table with one `run` line and
# the assertion reads it as one, so a change of form fails loudly rather than
# matching nothing.
pre_run = root["bootstrap"]["hooks"]["pre-packages"]["run"]
if "bin/brew-tap-packages install" not in pre_run:
    errs.append("pre-packages hook no longer installs the tap packages, and "
                "[bootstrap.packages] cannot carry them")

age = global_cfg.get("settings", {}).get("minimum_release_age")
if not isinstance(age, str):
    errs.append(f"minimum_release_age must be a duration string, got {age!r}")

# Every tracked TOML the shell area added, parsed rather than diffed. A file
# that does not parse never reaches here: yq refuses it above and names it.
for path, var in (("config/starship.toml", "STARSHIP_JSON"),
                  ("config/yazi/theme.toml", "YAZI_JSON"),
                  ("config/tuicr/config.toml", "TUICR_JSON")):
    cfg = json.loads(os.environ[var])
    if cfg is None:
        continue
    p = pathlib.Path(path)
    if path == "config/starship.toml":
        selected = cfg.get("palette")
        if selected and selected not in cfg.get("palettes", {}):
            errs.append(f"starship selects palette {selected!r}, which it does not define")
    if path == "config/yazi/theme.toml":
        # Parsing is not enough. A fetch through a markdown converter once
        # stripped every Nerd Font glyph from this file and it still parsed,
        # which would have shipped yazi with no separators and no icons.
        glyphs = sum(1 for c in p.read_text() if 0xE000 <= ord(c) <= 0xF8FF)
        if glyphs < 8:
            errs.append(f"{path} carries {glyphs} private-use glyphs, expected at least 8")

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

# HOME is a temp directory so nothing on this Mac is read as state.
tmp_home=$(mktemp -d)
trap 'rm -rf "$tmp_home"' EXIT

out=$(HOME=$tmp_home sh bin/macos-post-defaults --dry-run) || fail "macos-post-defaults --dry-run"
echo "$out" | grep -q 'persistent-apps -array' || fail "post-defaults: Dock array write missing"
echo "$out" | grep -q 'dict-add 64 ' || fail "post-defaults: hotkey 64 missing"
echo "$out" | grep -q 'dict-add 65 ' || fail "post-defaults: hotkey 65 missing"
ok "macos-post-defaults --dry-run"

HOME=$tmp_home sh bin/remove-bundled-apps --dry-run >/dev/null || fail "remove-bundled-apps --dry-run"
# The --bogus calls set DRY_RUN=1, so a parser that wrongly accepts the
# argument still only prints and leaves this Mac alone.
DRY_RUN=1 sh bin/remove-bundled-apps --bogus >/dev/null 2>&1 && fail "remove-bundled-apps: unknown argument accepted"
ok "remove-bundled-apps --dry-run"

# LibreWolf's policies. Firefox merges policy sources by top-level key, so the
# tracked ExtensionSettings replaces LibreWolf's whole block and must restate
# its "*" and uBlock Origin entries.
lw_plist=assets/librewolf-policies.plist
plutil -lint -s "$lw_plist" || fail "$lw_plist does not lint"
lw_json=$(plutil -convert json -o - "$lw_plist") || fail "$lw_plist does not convert to JSON"
lw_out=$(HOME=$tmp_home sh bin/librewolf-policies --dry-run) || fail "librewolf-policies --dry-run"
DRY_RUN=1 sh bin/librewolf-policies --bogus >/dev/null 2>&1 && fail "librewolf-policies: unknown argument accepted"
# A Mac without LibreWolf skips the bundled policies.json comparison. Set
# LIBREWOLF_APP to a fake bundle to run it there.
LW_JSON=$lw_json LW_OUT=$lw_out LW_APP=${LIBREWOLF_APP:-/Applications/LibreWolf.app} \
python3 - <<'PY' || fail "librewolf policies"
import json, os, pathlib, sys

policies = json.loads(os.environ["LW_JSON"])
errs = []
# The script and the plist each list the keys, so this compares the two.
# defaults import would wipe the keys Gecko writes, so only per-key writes pass.
written = []
for line in os.environ["LW_OUT"].splitlines():
    words = line.split()
    if words[:4] != ["+", "defaults", "write", "net.librewolf.librewolf"] or len(words) < 6:
        errs.append(f"librewolf-policies --dry-run printed {line[:80]!r}, not a defaults write of one key")
    else:
        written.append(words[4])
if sorted(written) != sorted(policies):
    errs.append(f"librewolf-policies writes {written}, but the plist holds {sorted(policies)}")
want = {"EnterprisePoliciesEnabled", "ExtensionSettings", "Homepage"}
if set(policies) != want:
    errs.append(f"plist top-level keys are {sorted(policies)}, not {sorted(want)}; each one overrides LibreWolf's own policy of that name")
if policies.get("EnterprisePoliciesEnabled") is not True:
    errs.append("EnterprisePoliciesEnabled is not true, so LibreWolf ignores its defaults domain")
if policies.get("Homepage") != {"StartPage": "previous-session"}:
    errs.append("Homepage is not just StartPage = previous-session, so the tabs do not come back")
ext = policies.get("ExtensionSettings", {})
addons = {
    "uBlock0@raymondhill.net",
    "78272b6fa58f4a1abaac99321d503a20@proton.me",
    "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}",
}
if set(ext) != addons | {"*"}:
    errs.append(f"ExtensionSettings holds {sorted(ext)}, not *, uBlock Origin, Proton Pass and Refined GitHub")
for guid in sorted(addons & set(ext)):
    if ext[guid].get("installation_mode") != "normal_installed":
        errs.append(f"{guid} is not normal_installed, so it either never installs or cannot be disabled")
    # A URL naming another GUID would install whatever that listing is.
    if guid not in ext[guid].get("install_url", ""):
        errs.append(f"{guid}'s install_url does not name its own GUID")
if "locale" in ext.get("*", {}).get("allowed_types", ["locale"]):
    errs.append("ExtensionSettings * allows language packs, which LibreWolf blocks")
# Catches LibreWolf changing its own entries upstream, which the tracked block
# would otherwise silently undo.
app = pathlib.Path(os.environ["LW_APP"])
if app.exists():
    bundled = json.loads((app / "Contents/Resources/distribution/policies.json").read_text())
    for key, entry in bundled["policies"]["ExtensionSettings"].items():
        if ext.get(key) != entry:
            errs.append(f"ExtensionSettings {key} differs from {app.name}'s bundled policies.json; restate LibreWolf's entry")
else:
    print(f"skip LibreWolf bundled policies: {app} is missing")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
PY
ok "librewolf policies"

# The tap packages, which mise cannot resolve and so never appears in the
# bootstrap plan beyond the hook line that calls this. This script is the only
# place they are named, and both the hook and update:apps go through it, so the
# two actions are asserted separately.
out=$(HOME=$tmp_home sh bin/brew-tap-packages install --dry-run) || fail "brew-tap-packages install --dry-run"
for tapped in FelixKratz/formulae/sketchybar FelixKratz/formulae/borders; do
  echo "$out" | grep -q "brew install .*$tapped" || fail "brew-tap-packages: install misses $tapped"
done
echo "$out" | grep -q 'brew install --cask .*nikitabobko/tap/aerospace' \
  || fail "brew-tap-packages: install misses nikitabobko/tap/aerospace"
echo "$out" | grep -q 'NONINTERACTIVE=1 /bin/bash -c .*Homebrew/install' \
  || fail "brew-tap-packages: Homebrew's installer can prompt"
out=$(HOME=$tmp_home sh bin/brew-tap-packages upgrade --dry-run) || fail "brew-tap-packages upgrade --dry-run"
# Separately asserted because `brew upgrade`, unlike `brew install`, will not
# tap on demand, so an upgrade that lost its formulae fails silently on a
# machine where the tap is present anyway.
echo "$out" | grep -q 'brew upgrade .*FelixKratz/formulae/borders' \
  || fail "brew-tap-packages: upgrade misses the formulae"
echo "$out" | grep -q 'brew upgrade --cask .*nikitabobko/tap/aerospace' \
  || fail "brew-tap-packages: upgrade misses the cask"
sh bin/brew-tap-packages >/dev/null 2>&1 && fail "brew-tap-packages: missing action accepted"
sh bin/brew-tap-packages install --bogus >/dev/null 2>&1 && fail "brew-tap-packages: unknown argument accepted"
ok "brew-tap-packages --dry-run"

# update:apps quits LibreWolf before mise replaces its bundle, and reopens it
# after. The task text runs the way mise runs it, against stubs that log, so
# nothing on this Mac quits, opens or upgrades.
upd=$tmp_home/update-apps
mkdir -p "$upd/stubs" "$upd/dotfiles/bin"
: >"$upd/dotfiles/bin/brew-tap-packages"
# Each stub logs its arguments, and the one named in UPD_FAIL exits 1.
for name in osascript open sh; do
  printf '#!/bin/sh\necho "%s $*" >>"$UPD_LOG"\n[ "$UPD_FAIL" != %s ]\n' "$name" "$name" >"$upd/stubs/$name"
done
# mise reads [bootstrap.packages] from the directory it starts in and its
# parents, and finds none from ~, where it runs global tasks. The mise stub
# checks only its start directory and marks a run there without the table, so
# the log comparisons fail.
printf '[bootstrap.packages]\n' >"$upd/dotfiles/mise.toml"
cat >"$upd/stubs/mise" <<'EOF'
#!/bin/sh
dir=$PWD
if [ "$1" = -C ]; then dir=$2; shift 2; fi
if grep -qxF '[bootstrap.packages]' "$dir/mise.toml" 2>/dev/null; then
  echo "mise $*" >>"$UPD_LOG"
else
  echo "mise $* without [bootstrap.packages]" >>"$UPD_LOG"
fi
[ "$UPD_FAIL" != mise ]
EOF
printf '#!/bin/sh\n' >"$upd/stubs/sleep"
# The pgrep stub finds LibreWolf running on its first UPD_RUNNING_CHECKS calls.
# It logs any other arguments, so a guard that lost -x or named another
# process fails the log comparison.
cat >"$upd/stubs/pgrep" <<'EOF'
#!/bin/sh
[ "$*" = "-xq librewolf" ] || echo "pgrep $*" >>"$UPD_LOG"
n=$(($(cat "$UPD_COUNT" 2>/dev/null || echo 0) + 1))
echo "$n" >"$UPD_COUNT"
[ "$n" -le "$UPD_RUNNING_CHECKS" ]
EOF
chmod +x "$upd"/stubs/*
upd_run=$(yq -r '.tasks."update:apps".run' config/mise/config.toml) || fail "update:apps has no run text"
update_apps() { # $1: how many pgrep calls find LibreWolf running, $2: the stub that fails
  : >"$upd/log"
  rm -f "$upd/count"
  # The task runs from $upd, which holds no mise.toml, like ~. The repo root
  # would hide a task that never leaves the caller's directory.
  (cd "$upd" && PATH=$upd/stubs:/usr/bin:/bin DOTFILES=$upd/dotfiles UPD_LOG=$upd/log UPD_COUNT=$upd/count \
    UPD_RUNNING_CHECKS=$1 UPD_FAIL=${2:-} /bin/sh -o errexit -c "$upd_run" 2>"$upd/err")
}
upd_quit='osascript -e with timeout of 30 seconds -e tell application id "net.librewolf.librewolf" to quit -e end timeout'
upd_mise='mise bootstrap packages upgrade --yes'
upd_upgrade="$upd_mise
sh $upd/dotfiles/bin/brew-tap-packages upgrade"
upd_open='open -b net.librewolf.librewolf'
upd_log_is() { # $1: the run, $2: the log it must have written
  [ "$(cat "$upd/log")" = "$2" ] || fail "update:apps $1 logged:
$(cat "$upd/log")"
}
upd_quiet() { # $1: the run
  [ -s "$upd/err" ] && fail "update:apps $1 wrote to stderr: $(cat "$upd/err")"
  return 0
}

update_apps 0 || fail "update:apps without LibreWolf exited nonzero"
upd_log_is "without LibreWolf" "$upd_upgrade"
upd_quiet "without LibreWolf"

update_apps 1 || fail "update:apps with LibreWolf exited nonzero"
upd_log_is "with LibreWolf" "$upd_quit
$upd_upgrade
$upd_open"
upd_quiet "with LibreWolf"

# A denied Automation prompt fails osascript, and the timeout must still name
# the problem rather than errexit ending the task with no message.
for failing in "" osascript; do
  run="with LibreWolf that never quits${failing:+ and a failing osascript}"
  update_apps 999 "$failing" && fail "update:apps upgraded $run"
  upd_log_is "$run" "$upd_quit
$upd_open"
  grep -qxF 'update:apps: LibreWolf did not quit; close it and rerun' "$upd/err" \
    || fail "update:apps $run printed: $(cat "$upd/err")"
done

update_apps 1 mise && fail "update:apps hid a failed upgrade"
upd_log_is "with a failed upgrade" "$upd_quit
$upd_mise
$upd_open"

update_apps 1 open || fail "update:apps failed an upgrade that worked because the reopen failed"
upd_log_is "with a failed reopen" "$upd_quit
$upd_upgrade
$upd_open"
upd_quiet "with a failed reopen"
ok "update:apps quits and reopens LibreWolf"

# setup-git and install.sh, run for real in a temp HOME. The forge CLIs,
# ssh-keygen and ssh-add are stubs that log their arguments, so nothing
# reaches GitHub, GitLab or the keychain. gh and glab keep what they were given
# in the case's state directory and answer from it, so a rerun sees what the
# first run did. setup-git's DOTFILES names a directory with no clone, so no
# remote is flipped.
# The git section probes these homes, so the path is physical for the reason
# it gives there.
sg=$(cd "$tmp_home" && pwd -P)/setup-git
mkdir -p "$sg/stubs"
cat >"$sg/stubs/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >>"$SG_LOG"
case "$1 $2" in
  "auth status") [ -f "$SG_STATE/gh-login" ] ;;
  "auth login") : >"$SG_STATE/gh-login" ;;
  "ssh-key list") cat "$SG_STATE/gh-keys" 2>/dev/null || true ;;
  "ssh-key add") printf '%s %s\n' "$(cut -d' ' -f2 "$3")" "$5" >>"$SG_STATE/gh-keys" ;;
  "api meta") echo 'ssh-ed25519 AAAAstubhostkey' ;;
esac
EOF
# The installer never loads the overlay's [env], so each script must set glab's
# env itself. A call without it logs as such and fails the log comparison.
# SG_GLAB_ADD=taken fails the upload with GitLab's duplicate-key error, and
# SG_GLAB_ADD=fail with a 401.
cat >"$sg/stubs/glab" <<'EOF'
#!/bin/sh
if [ "${GLAB_CONFIG_DIR:-}" = "$HOME/.config/glab-cli" ] && [ "${GLAB_SEND_TELEMETRY:-}" = 0 ] \
  && [ "${GITLAB_HOST:-}" = gitlab.com ]; then
  echo "glab $*" >>"$SG_LOG"
else
  echo "glab without its env: $*" >>"$SG_LOG"
fi
case "$1 $2" in
  "config get") if [ -f "$SG_STATE/glab-login" ]; then echo stub-user; fi ;;
  "auth login") : >"$SG_STATE/glab-login" ;;
  "ssh-key list") cat "$SG_STATE/glab-keys" 2>/dev/null || true ;;
  "ssh-key add")
    case "${SG_GLAB_ADD:-}" in
      taken) echo 'ERROR: 400 {fingerprint_sha256: [has already been taken]}' >&2; exit 1 ;;
      fail) echo 'ERROR: 401 Unauthorized' >&2; exit 1 ;;
    esac
    printf 'stub\t%s\tauth_and_signing\n' "$(cut -d' ' -f1,2 "$3")" >>"$SG_STATE/glab-keys" ;;
esac
EOF
# No mkdir: the real ssh-keygen fails when the key's directory is missing.
cat >"$sg/stubs/ssh-keygen" <<'EOF'
#!/bin/sh
echo "ssh-keygen $*" >>"$SG_LOG"
while [ $# -gt 1 ]; do [ "$1" = -f ] && f=$2; shift; done
echo stub >"$f"
echo "ssh-ed25519 AAAAstub-$(basename "$f") stub" >"$f.pub"
EOF
printf '#!/bin/sh\necho "ssh-add $*" >>"$SG_LOG"\n' >"$sg/stubs/ssh-add"
chmod +x "$sg"/stubs/*
# The installer's own stubs, kept off setup-git's PATH. sudo logs all but the
# keepalive's -n calls. sleep is short, so the keepalive loop ends a second
# after the installer does instead of a minute.
mkdir -p "$sg/install-stubs"
printf '#!/bin/sh\n[ "$1" = -n ] || echo "sudo $*" >>"$SG_LOG"\n' >"$sg/install-stubs/sudo"
printf '#!/bin/sh\nexec /bin/sleep 1\n' >"$sg/install-stubs/sleep"
# Installed at ~/.local/bin/mise, where the installer looks. x runs the tool
# through to its stub, and anything else only logs.
cat >"$sg/install-stubs/mise" <<'EOF'
#!/bin/sh
echo "mise $*" >>"$SG_LOG"
if [ "$1" = x ]; then
  while [ "$1" != -- ]; do shift; done
  shift
  exec "$@"
fi
EOF
chmod +x "$sg"/install-stubs/*

sg_case() { # $1: case name, $2: the env miserc names, or nothing for no miserc
  rm -rf "${sg:?}/$1"
  mkdir -p "$sg/$1/home" "$sg/$1/state"
  if [ -n "$2" ]; then
    mkdir -p "$sg/$1/home/.config/mise"
    printf 'env = ["%s"]\n' "$2" >"$sg/$1/home/.config/mise/miserc.toml"
  fi
}
sg_run() { # $1: case name, then NAME=value pairs and setup-git's arguments
  c=$sg/$1
  shift
  : >"$c/log"
  # env -i keeps the caller's DRY_RUN, GIT_* and XDG_* out of the run.
  (cd "$c" && env -i PATH="$sg/stubs:/usr/bin:/bin" HOME="$c/home" SG_LOG="$c/log" SG_STATE="$c/state" \
    DOTFILES="$c/no-clone" GIT_NAME='Test Person' "$@" </dev/null >"$c/out" 2>&1)
}
sg_install() { # $1: case name, then NAME=value pairs
  c=$sg/$1
  shift
  : >"$c/log"
  mkdir -p "$c/home/.local/bin" "$c/clone/.git" "$c/clone/.scratch/.git"
  cp "$sg/install-stubs/mise" "$c/home/.local/bin/mise"
  # The clone and the scratch clone already exist, so the installer clones
  # nothing. The Command Line Tools check reads the real /Library, and
  # smoke cannot run on a Mac without them.
  (cd "$c" && env -i PATH="$sg/install-stubs:$sg/stubs:/usr/bin:/bin" HOME="$c/home" SG_LOG="$c/log" \
    SG_STATE="$c/state" DOTFILES="$c/clone" GIT_NAME='Test Person' GIT_PROFILES= "$@" \
    sh "$root/install.sh" </dev/null >"$c/out" 2>&1)
}
sg_install_tail() { # $1: case name; what every installer run ends with
  printf 'mise trust %s\n' "$sg/$1/clone/mise.toml" "$sg/$1/clone/mise.work.toml" \
    "$sg/$1/clone/mise.personal.toml" "$sg/$1/clone/config/mise/config.toml" \
    "$sg/$1/clone/config/mise/config.work.toml" "$sg/$1/clone/config/mise/config.personal.toml"
  printf 'mise -C %s bootstrap --yes\nmise -C %s run setup-git\n' "$sg/$1/clone" "$sg/$1/clone"
}
sg_snap() { # Every file in the case's HOME with its checksum.
  (cd "$sg/$1/home" && find . \( -type f -o -type l \) -exec cksum {} + | sort)
}
sg_file_is() { # $1: case, $2: file under HOME, $3: its expected content
  [ "$(cat "$sg/$1/home/$2" 2>/dev/null)" = "$3" ] \
    || fail "setup-git $1: ~/$2 is:
$(cat "$sg/$1/home/$2" 2>&1)"
}
sg_log_is() { # $1: case, $2: the log it must have written
  [ "$(cat "$sg/$1/log")" = "$2" ] || fail "case $1 logged:
$(cat "$sg/$1/log")"
}
# A rerun with the same input changes no file and sends only the reads.
sg_rerun_quiet() { # $1: case, then sg_run's arguments
  before=$(sg_snap "$1")
  sg_run "$@" sh "$root/bin/setup-git" || fail "setup-git $1 rerun exited nonzero: $(cat "$sg/$1/out")"
  [ "$(sg_snap "$1")" = "$before" ] || fail "setup-git $1 rerun changed files"
  glab_reads=
  if grep -qs '^env *=.*"work"' "$sg/$1/home/.config/mise/miserc.toml"; then
    glab_reads="glab config get user --host gitlab.com
glab ssh-key list --per-page 100
"
  fi
  sg_log_is "$1" "gh auth status
gh ssh-key list
gh ssh-key list
${glab_reads}gh config set git_protocol ssh"
}
sg_host=$(hostname)
sg_note='the work Mac signs with ~/.ssh/id_ed25519_gitlab.pub. Edit [user] by hand.'

# A personal Mac, fresh: the GitHub key everywhere and no GitLab anything.
sg_case personal-fresh personal
h=$sg/personal-fresh/home
set -- personal-fresh GIT_EMAIL=personal@example.com GIT_PROFILES='~/Work=work@example.com'
before=$(sg_snap personal-fresh)
sg_run "$@" sh "$root/bin/setup-git" --dry-run || fail "setup-git personal-fresh --dry-run exited nonzero: $(cat "$sg/personal-fresh/out")"
[ "$(sg_snap personal-fresh)" = "$before" ] || fail "setup-git personal-fresh --dry-run changed files"
sg_log_is personal-fresh "gh auth status"
grep -qxF "+ write $h/.gitconfig-local" "$sg/personal-fresh/out" \
  || fail "setup-git personal-fresh --dry-run did not print the local file: $(cat "$sg/personal-fresh/out")"
sg_run "$@" sh "$root/bin/setup-git" || fail "setup-git personal-fresh exited nonzero: $(cat "$sg/personal-fresh/out")"
sg_log_is personal-fresh "gh auth status
gh auth login -w -p ssh --skip-ssh-key -s admin:public_key,admin:ssh_signing_key
ssh-keygen -t ed25519 -C personal@example.com -f $h/.ssh/id_ed25519_github
ssh-add --apple-use-keychain $h/.ssh/id_ed25519_github
gh ssh-key list
gh ssh-key add $h/.ssh/id_ed25519_github.pub --type authentication --title $sg_host
gh ssh-key list
gh ssh-key add $h/.ssh/id_ed25519_github.pub --type signing --title $sg_host
gh config set git_protocol ssh
gh api meta --jq .ssh_keys[]"
sg_file_is personal-fresh .gitconfig-local "[user]
	name = Test Person
	email = personal@example.com
	signingkey = $h/.ssh/id_ed25519_github.pub
[commit]
	gpgsign = true

[includeIf \"gitdir/i:~/Work/\"]
	path = ~/.gitconfig-work"
sg_file_is personal-fresh .gitconfig-work "[user]
	email = work@example.com
	signingkey = $h/.ssh/id_ed25519_github.pub"
[ -e "$h/.ssh/id_ed25519_gitlab" ] && fail "setup-git personal-fresh made a GitLab key"
sg_rerun_quiet "$@"
grep -qF "$sg_note" "$sg/personal-fresh/out" && fail "setup-git personal-fresh printed the work Mac note"
ok "setup-git, a fresh personal Mac"

# The work Mac, fresh: the default identity signs with the GitLab key, and each
# profile with the key it names, GitHub when it names none.
sg_case work-fresh work
h=$sg/work-fresh/home
set -- work-fresh GIT_EMAIL=work@example.com GIT_PROFILES='~/Work=w@example.com=gitlab, ~/Personal=p@example.com'
sg_run "$@" sh "$root/bin/setup-git" || fail "setup-git work-fresh exited nonzero: $(cat "$sg/work-fresh/out")"
sg_log_is work-fresh "gh auth status
gh auth login -w -p ssh --skip-ssh-key -s admin:public_key,admin:ssh_signing_key
ssh-keygen -t ed25519 -C work@example.com -f $h/.ssh/id_ed25519_github
ssh-add --apple-use-keychain $h/.ssh/id_ed25519_github
gh ssh-key list
gh ssh-key add $h/.ssh/id_ed25519_github.pub --type authentication --title $sg_host
gh ssh-key list
gh ssh-key add $h/.ssh/id_ed25519_github.pub --type signing --title $sg_host
glab config get user --host gitlab.com
glab auth login --hostname gitlab.com --web -g ssh
ssh-keygen -t ed25519 -C work@example.com -f $h/.ssh/id_ed25519_gitlab
ssh-add --apple-use-keychain $h/.ssh/id_ed25519_gitlab
glab ssh-key list --per-page 100
glab ssh-key add $h/.ssh/id_ed25519_gitlab.pub --title $sg_host --usage-type auth_and_signing
gh config set git_protocol ssh
gh api meta --jq .ssh_keys[]"
sg_file_is work-fresh .gitconfig-local "[user]
	name = Test Person
	email = work@example.com
	signingkey = $h/.ssh/id_ed25519_gitlab.pub
[commit]
	gpgsign = true

[includeIf \"gitdir/i:~/Work/\"]
	path = ~/.gitconfig-work
[includeIf \"gitdir/i:~/Personal/\"]
	path = ~/.gitconfig-personal"
sg_file_is work-fresh .gitconfig-work "[user]
	email = w@example.com
	signingkey = $h/.ssh/id_ed25519_gitlab.pub"
sg_file_is work-fresh .gitconfig-personal "[user]
	email = p@example.com
	signingkey = $h/.ssh/id_ed25519_github.pub"
grep -qF "$sg_note" "$sg/work-fresh/out" && fail "setup-git work-fresh printed the note over the file it just wrote"
sg_rerun_quiet "$@"
grep -qF "$sg_note" "$sg/work-fresh/out" && fail "setup-git work-fresh printed the note on a rerun"
ok "setup-git, the work Mac fresh, with profiles"

# Refusals stop before any login, key or file. The first entry in the second
# case is valid, so a check that ran entry by entry would write its file.
for refusal in \
  ':~/W=w@example.com=gitlab' \
  'personal:~/W=w@example.com=gitlab' \
  'work:~/Ok=o@example.com,~/W=w@example.com=bitbucket' \
  'work:~/W=w@example.com=github=x' \
  'work:~/W='
do
  sg_case refusal "${refusal%%:*}"
  profiles=${refusal#*:}
  before=$(sg_snap refusal)
  sg_run refusal GIT_EMAIL=e@example.com GIT_PROFILES="$profiles" sh "$root/bin/setup-git" \
    && fail "setup-git accepted '$profiles'"
  bad=${profiles##*,}
  grep -qF "profile '$bad'" "$sg/refusal/out" || fail "setup-git refused '$profiles' without naming '$bad': $(cat "$sg/refusal/out")"
  [ "$(sg_snap refusal)" = "$before" ] || fail "setup-git wrote files before refusing '$profiles'"
  sg_log_is refusal ""
done
ok "setup-git refusals"

# The work Mac already set up, as this repo's own Mac was: a personal [user], no
# includes, and a profile file written by hand. setup-git appends the missing
# includes, writes the missing profile file, keeps the rest byte for byte and
# leaves [user] to the note.
sg_case existing work
h=$sg/existing/home
sg_local="[user]
	name = Test Person
	email = personal@example.com
	signingkey = ~/.ssh/id_ed25519_github.pub
[commit]
	gpgsign = true"
printf '%s\n' "$sg_local" >"$h/.gitconfig-local"
printf '[user]\n\temail = old@example.com\n' >"$h/.gitconfig-work"
set -- existing GIT_EMAIL=work@example.com GIT_PROFILES='~/projects/iamstuba=personal@example.com=github,~/Work=w@example.com=gitlab'
before=$(sg_snap existing)
sg_run "$@" sh "$root/bin/setup-git" --dry-run || fail "setup-git existing --dry-run exited nonzero: $(cat "$sg/existing/out")"
[ "$(sg_snap existing)" = "$before" ] || fail "setup-git existing --dry-run changed files"
sg_log_is existing "gh auth status
glab config get user --host gitlab.com"
for want in "+ append $h/.gitconfig-local" '    [includeIf "gitdir/i:~/projects/iamstuba/"]' "+ write $h/.gitconfig-iamstuba"; do
  grep -qxF -- "$want" "$sg/existing/out" || fail "setup-git existing --dry-run did not print '$want': $(cat "$sg/existing/out")"
done
sg_run "$@" sh "$root/bin/setup-git" || fail "setup-git existing exited nonzero: $(cat "$sg/existing/out")"
sg_file_is existing .gitconfig-local "$sg_local

[includeIf \"gitdir/i:~/projects/iamstuba/\"]
	path = ~/.gitconfig-iamstuba

[includeIf \"gitdir/i:~/Work/\"]
	path = ~/.gitconfig-work"
sg_file_is existing .gitconfig-iamstuba "[user]
	email = personal@example.com
	signingkey = $h/.ssh/id_ed25519_github.pub"
sg_file_is existing .gitconfig-work "[user]
	email = old@example.com"
grep -qxF "setup-git: ~/.gitconfig-local signs with ~/.ssh/id_ed25519_github.pub; $sg_note" "$sg/existing/out" \
  || fail "setup-git existing printed no note: $(cat "$sg/existing/out")"
sg_rerun_quiet "$@"
grep -qF "$sg_note" "$sg/existing/out" || fail "setup-git existing dropped the note on a rerun"
# The owner's hand edit, after which the note stops.
sed 's|id_ed25519_github.pub$|id_ed25519_gitlab.pub|; s|personal@example.com$|work@example.com|' \
  "$h/.gitconfig-local" >"$sg/existing/edited" && mv "$sg/existing/edited" "$h/.gitconfig-local"
sg_rerun_quiet "$@"
grep -qF "$sg_note" "$sg/existing/out" && fail "setup-git existing printed the note after the hand edit"
# git signs with the private half too, so naming it is no reason for the note.
sed "s|~/.ssh/id_ed25519_gitlab.pub\$|$h/.ssh/id_ed25519_gitlab|" \
  "$h/.gitconfig-local" >"$sg/existing/edited" && mv "$sg/existing/edited" "$h/.gitconfig-local"
grep -qxF "	signingkey = $h/.ssh/id_ed25519_gitlab" "$h/.gitconfig-local" || fail "setup-git existing: the second hand edit missed"
sg_rerun_quiet "$@"
grep -qF "$sg_note" "$sg/existing/out" && fail "setup-git existing printed the note for the private key path"
ok "setup-git, the work Mac already set up"

# Every refused upload stops setup-git before it writes the identity, a
# duplicate included. The list check reads the whole account, so a duplicate
# can only be this key on another account.
for refusal in 'taken:has already been taken' 'fail:401 Unauthorized'; do
  sg_case upload work
  sg_run upload GIT_EMAIL=work@example.com GIT_PROFILES= SG_GLAB_ADD="${refusal%%:*}" sh "$root/bin/setup-git" \
    && fail "setup-git passed a GitLab upload refused with '${refusal#*:}'"
  grep -qxF "glab ssh-key add $sg/upload/home/.ssh/id_ed25519_gitlab.pub --title $sg_host --usage-type auth_and_signing" \
    "$sg/upload/log" || fail "setup-git never tried the GitLab upload: $(cat "$sg/upload/log")"
  grep -qF "${refusal#*:}" "$sg/upload/out" || fail "setup-git hid GitLab's refusal: $(cat "$sg/upload/out")"
  [ -e "$sg/upload/home/.gitconfig-local" ] && fail "setup-git wrote ~/.gitconfig-local after a refused GitLab upload"
done
ok "setup-git, a refused GitLab upload"

# The installer through to its last step, against the stub mise. A personal
# Mac never calls glab and gets no GitLab key.
sg_case install-personal ""
h=$sg/install-personal/home
sg_install install-personal DOTFILES_WORK=0 GIT_EMAIL=personal@example.com \
  || fail "install.sh personal exited nonzero: $(cat "$sg/install-personal/out")"
sg_log_is install-personal "sudo -v
mise x github-cli -- gh auth status
gh auth status
mise x github-cli -- gh auth login -w -p ssh --skip-ssh-key -s admin:public_key,admin:ssh_signing_key
gh auth login -w -p ssh --skip-ssh-key -s admin:public_key,admin:ssh_signing_key
ssh-keygen -t ed25519 -C personal@example.com -f $h/.ssh/id_ed25519_github
ssh-add --apple-use-keychain $h/.ssh/id_ed25519_github
$(sg_install_tail install-personal)"
[ -e "$h/.ssh/id_ed25519_gitlab" ] && fail "install.sh personal made a GitLab key"
sg_file_is install-personal .config/mise/miserc.toml 'env = ["personal"]'
ok "install.sh, a personal Mac"

# The work Mac, fresh: the GitLab login right after the work question, the
# GitLab key right after the GitHub key, then setup-git uploads it. A rerun
# of both asks for nothing and sends nothing.
sg_case install-work ""
h=$sg/install-work/home
sg_install install-work DOTFILES_WORK=1 GIT_EMAIL=work@example.com \
  || fail "install.sh work exited nonzero: $(cat "$sg/install-work/out")"
sg_log_is install-work "sudo -v
mise x github-cli -- gh auth status
gh auth status
mise x github-cli -- gh auth login -w -p ssh --skip-ssh-key -s admin:public_key,admin:ssh_signing_key
gh auth login -w -p ssh --skip-ssh-key -s admin:public_key,admin:ssh_signing_key
mise x gitlab:gitlab-org/cli -- glab config get user --host gitlab.com
glab config get user --host gitlab.com
mise x gitlab:gitlab-org/cli -- glab auth login --hostname gitlab.com --web -g ssh
glab auth login --hostname gitlab.com --web -g ssh
ssh-keygen -t ed25519 -C work@example.com -f $h/.ssh/id_ed25519_github
ssh-add --apple-use-keychain $h/.ssh/id_ed25519_github
ssh-keygen -t ed25519 -C work@example.com -f $h/.ssh/id_ed25519_gitlab
ssh-add --apple-use-keychain $h/.ssh/id_ed25519_gitlab
$(sg_install_tail install-work)"
sg_file_is install-work .config/mise/miserc.toml 'env = ["work"]'
# What the stub mise's `run setup-git` stands for.
set -- install-work GIT_EMAIL=work@example.com GIT_PROFILES=
sg_run "$@" sh "$root/bin/setup-git" || fail "setup-git install-work exited nonzero: $(cat "$sg/install-work/out")"
sg_log_is install-work "gh auth status
gh ssh-key list
gh ssh-key add $h/.ssh/id_ed25519_github.pub --type authentication --title $sg_host
gh ssh-key list
gh ssh-key add $h/.ssh/id_ed25519_github.pub --type signing --title $sg_host
glab config get user --host gitlab.com
glab ssh-key list --per-page 100
glab ssh-key add $h/.ssh/id_ed25519_gitlab.pub --title $sg_host --usage-type auth_and_signing
gh config set git_protocol ssh
gh api meta --jq .ssh_keys[]"
grep -qxF "	signingkey = $h/.ssh/id_ed25519_gitlab.pub" "$h/.gitconfig-local" \
  || fail "setup-git install-work: ~/.gitconfig-local does not sign with the GitLab key"
# The rerun names no env and has no terminal, so only miserc can answer.
before=$(sg_snap install-work)
sg_install install-work GIT_EMAIL=work@example.com \
  || fail "install.sh work rerun exited nonzero: $(cat "$sg/install-work/out")"
sg_log_is install-work "sudo -v
mise x github-cli -- gh auth status
gh auth status
mise x gitlab:gitlab-org/cli -- glab config get user --host gitlab.com
glab config get user --host gitlab.com
$(sg_install_tail install-work)"
[ "$(sg_snap install-work)" = "$before" ] || fail "install.sh work rerun changed files"
sg_rerun_quiet "$@"
grep -qF "$sg_note" "$sg/install-work/out" && fail "setup-git install-work printed the note on a rerun"
ok "install.sh and setup-git, the work Mac"

# miserc is the one answer to which Mac this is. DOTFILES_WORK only seeds it,
# so one that contradicts it, a miserc env naming neither or both, or a DOTFILES_WORK
# that is neither 1 nor 0 stops the installer before the password prompt.
for conflict in \
  'personal:DOTFILES_WORK=1:DOTFILES_WORK=1, but' \
  'work:DOTFILES_WORK=0:DOTFILES_WORK=0, but' \
  'other:DOTFILES_WORK=1:sets env to neither work nor personal' \
  'work", "personal:DOTFILES_WORK=1:names both work and personal' \
  ':DOTFILES_WORK=yes:DOTFILES_WORK must be 1 or 0'
do
  miserc_env=${conflict%%:*} rest=${conflict#*:}
  sg_case install-conflict "$miserc_env"
  before=$(sg_snap install-conflict)
  sg_install install-conflict "${rest%%:*}" GIT_EMAIL=e@example.com \
    && fail "install.sh ran with miserc env '$miserc_env' and ${rest%%:*}"
  grep -qF "${rest#*:}" "$sg/install-conflict/out" \
    || fail "install.sh stopped without saying '${rest#*:}': $(cat "$sg/install-conflict/out")"
  sg_log_is install-conflict ""
  # sg_install adds the stub mise, which is the case's own file, not the installer's.
  [ "$(sg_snap install-conflict | grep -v '/.local/bin/mise$')" = "$before" ] \
    || fail "install.sh changed files before stopping on miserc env '$miserc_env' and ${rest%%:*}"
done
ok "install.sh, miserc decides the env"

out=$(HOME=$tmp_home DOTFILES=$root DOTFILES_WORK=0 GIT_NAME=Test GIT_EMAIL=test@example.com GIT_PROFILES= \
  sh install.sh --dry-run) || fail "install.sh --dry-run"
echo "$out" | grep -q 'ssh-keygen' || fail "install: key generation missing"
echo "$out" | grep -q 'bootstrap --yes' || fail "install: bootstrap command missing"
echo "$out" | grep -q 'run setup-git' || fail "install: setup-git command missing"
echo "$out" | grep -q 'env = \["work"\]' && fail "install: wrote the work overlay on a personal answer"
echo "$out" | grep -q 'env = \["personal"\]' || fail "install: personal answer did not write miserc.toml"
echo "$out" | grep -qE 'glab|gitlab' && fail "install: a personal dry run names glab or the GitLab key"
out=$(HOME=$tmp_home DOTFILES=$root DOTFILES_WORK=1 GIT_NAME=Test GIT_EMAIL=test@example.com GIT_PROFILES= \
  sh install.sh --dry-run 2>&1) || fail "install.sh --dry-run (work)"
hint='mise x claude -- claude'
echo "$out" | grep -qF -- "$hint" && fail "install: a clean dry run printed the failure hint"
# An empty DOTFILES_WORK with no terminal to ask forces a failure.
if fail_out=$(HOME=$tmp_home DOTFILES=$root DOTFILES_WORK= GIT_NAME=Test GIT_EMAIL=test@example.com GIT_PROFILES= \
  sh install.sh --dry-run 2>&1 </dev/null); then
  fail "install: a failed run exited 0"
fi
echo "$fail_out" | grep -qF -- "~/.local/bin/$hint" || fail "install: a failed run printed no mise claude hint"
echo "$out" | grep -q 'env = \["work"\]' || fail "install: work answer did not write miserc.toml"
echo "$out" | grep -qF 'glab auth login --hostname gitlab.com --web -g ssh' || fail "install: work dry run prints no GitLab login"
echo "$out" | grep -qF "ssh-keygen -t ed25519 -C test@example.com -f $tmp_home/.ssh/id_ed25519_gitlab" \
  || fail "install: work dry run prints no GitLab key"
echo "$out" | grep -q 'env = \["personal"\]' && fail "install: wrote the personal overlay on a work answer"
# The zsh probe below grants the same trust to its own temp HOME, so without
# this the probe would stay green while a bootstrapped Mac went back to mise
# warning on every shell start. Only the work answer reaches this far.
for f in mise.toml mise.work.toml mise.personal.toml config/mise/config.toml config/mise/config.work.toml \
         config/mise/config.personal.toml; do
  echo "$out" | grep -q "mise trust $root/$f" || fail "install: no mise trust for $f"
done
sh install.sh --bogus >/dev/null 2>&1 && fail "install: unknown argument accepted"
ok "install.sh --dry-run"

# The shell, started for real. Grepping a config file for the line that was
# supposed to set something proves a string is present; `setopt` in a loaded
# shell proves the option is on.
if command -v zsh >/dev/null 2>&1; then
  zsh_home=$(mktemp -d)
  zsh_err=$(mktemp)
  trap 'rm -rf "$tmp_home" "$zsh_home" "$zsh_err"' EXIT
  mkdir -p "$zsh_home/.config"
  # Exactly what bootstrap links, so .zshenv resolves DOTFILES through a symlink.
  ln -s "$root/home/.zshenv" "$zsh_home/.zshenv"
  ln -s "$root/config/zsh" "$zsh_home/.config/zsh"

  # And what bootstrap trusts. .zshrc activates mise, the suite runs from the
  # repo root, and an untrusted config there costs three stderr lines that the
  # rule below fails on: the named trust warning, plus one `migrate: error
  # parsing config file` per mise invocation, which is the same cause and not
  # a second one. install.sh runs mise trust against the real HOME, so granting
  # it here is the probe matching a bootstrapped Mac rather than filtering mise
  # out of the stderr rule.
  #
  # Trust is the one thing this probe writes, and MISE_STATE_DIR outranks both
  # HOME and an inherited XDG_STATE_HOME, so it is pinned into the temp HOME
  # rather than left to whoever ran `mise run check`.
  mise_state=$zsh_home/.local/state/mise
  if command -v mise >/dev/null 2>&1; then
    # Recorded per directory and it does not cascade, so this covers the repo
    # root and nothing under it. install.sh names the two configs in
    # config/mise as well; this HOME links neither, so the probe never loads
    # them. Captured because mise reports success on stderr too.
    trust_out=$(HOME=$zsh_home MISE_STATE_DIR=$mise_state MISE_CEILING_PATHS=$mise_ceiling \
      mise trust "$root/mise.toml" 2>&1) \
      || fail "mise trust failed against the probe's HOME: $trust_out"
  fi

  # ZDOTDIR points into tracked space, so a shell that writes under it dirties
  # the working tree. Compared before against after rather than required
  # empty, so the check still means something with work in progress.
  before=$(git -C "$root" status --porcelain 2>/dev/null || true)

  # ZDOTDIR is unset for the probe. A shell inherits it from whoever runs
  # `mise run check`, and zsh reads $ZDOTDIR/.zshenv in preference to
  # $HOME/.zshenv, so leaving it set tests the caller's install, not this one.
  # MISE_STATE_DIR is pinned for the same reason: the mise this shell activates
  # has to read the trust granted above and not the caller's. The ceiling stops
  # it finding the caller's global config by searching the clone's parents.
  #
  # The caller's mise tool directories and shims come off PATH for the same
  # reason. This shell's mise reads no config that names those tools, so a shim
  # found on PATH errors on stderr the moment .zshrc runs it.
  #
  # The output is cut into labelled sections, so an alias cannot satisfy an
  # assertion meant for a key binding.
  mise_data=${MISE_DATA_DIR:-$HOME/.local/share/mise}
  probe_path=$(printf '%s\n' "$PATH" | tr : '\n' | grep -v "^$mise_data/" | paste -sd : -)
  out=$(unset ZDOTDIR; PATH=$probe_path HOME=$zsh_home MISE_STATE_DIR=$mise_state MISE_CEILING_PATHS=$mise_ceiling zsh -i -c '
    echo "### env";       printenv
    echo "### histfile";  echo "HISTFILE=$HISTFILE"
    # Physical, because ZDOTDIR reaches the repo through a symlink and the
    # literal path looks like it is under $HOME either way.
    echo "HISTDIR=$(cd ${HISTFILE:h} && pwd -P)"
    echo "### path";      print -l $path
    echo "### setopt";    setopt
    echo "### bindkey";   bindkey
    echo "### widgets";   zle -l
    # Resolved the way .zshrc resolves it, so this tracks the config rather
    # than assuming every terminal sends the same sequence for Delete.
    echo "### delkey";    bindkey -- "${terminfo[kdch1]:-^[[3~}"
    echo "### alias";     alias
    echo "### functions"; functions +
  ' 2>"$zsh_err") || fail "interactive zsh exited non-zero"
  if [ -s "$zsh_err" ]; then
    cat "$zsh_err" >&2
    fail "interactive zsh wrote to stderr; a guard is missing"
  fi

  after=$(git -C "$root" status --porcelain 2>/dev/null || true)
  [ "$before" = "$after" ] || fail "a shell load changed the working tree"

  # One labelled block of the probe output. printf, not echo: the lpath alias
  # body contains a literal backslash-n, and echo turns it into a real newline
  # and splits the line in two.
  section() {
    printf '%s\n' "$out" | awk -v want="### $1" '$0 == want { f = 1; next } /^### / { f = 0 } f'
  }
  want() {  # section-name pattern message
    section "$1" | grep -q -- "$2" || fail "shell: $3"
  }
  deny() {
    section "$1" | grep -q -- "$2" && fail "shell: $3"
    return 0
  }

  for var in XDG_CONFIG_HOME ZDOTDIR EDITOR GIT_EDITOR RIPGREP_CONFIG_PATH \
             EZA_CONFIG_DIR BAT_THEME; do
    want env "^$var=" "$var is not exported"
  done
  want path "^$root/bin$" "\$DOTFILES/bin is not on PATH"
  want path "^$zsh_home/.local/bin$" "~/.local/bin is not on PATH"

  deny histfile "^HISTDIR=$root" "HISTFILE resolves into the repo"
  want histfile "^HISTFILE=$zsh_home/" "HISTFILE is not under \$HOME"
  # The compdump is the other half of the same trap, reached through the symlink.
  for stray in .zsh_history .zcompdump; do
    [ -e "$root/config/zsh/$stray" ] && fail "shell: a load left $stray in tracked space"
  done

  for opt in sharehistory extendedhistory histignorealldups histignorespace \
             histreduceblanks interactivecomments extendedglob nolistbeep; do
    want setopt "^$opt$" "$opt is not set"
  done
  deny setopt '^incappendhistory$' "INC_APPEND_HISTORY is on alongside SHARE_HISTORY"

  # Anchored on the binding, not the widget name. `functions +` lists
  # edit-command-line whether or not anything is bound to it, so an unanchored
  # grep passed with the bindkey line deleted.
  want bindkey '^"\^G" edit-command-line$' "Ctrl-G is not bound"
  # Proves .zshrc still carries the line, and nothing more. zsh binds a key to
  # a widget that does not exist without complaint, so this can pass with the
  # plugin gone. The widget assertions below are what cover that.
  want bindkey '^"\^@" autosuggest-accept$' "Ctrl-Space is not bound"
  want bindkey '^"\^\[\[1;5C" forward-word$' "Ctrl-right is not bound"
  want bindkey '^"\^\[\[1;5D" backward-word$' "Ctrl-left is not bound"
  want delkey 'delete-char' "the delete key is not bound"

  # The three brew plugins, each proved by something it defines rather than by
  # a binding pointing at it. No guard: a brew phase that failed partway is the
  # fresh-Mac state this is here to catch, so absence has to fail.
  want widgets '^autosuggest-accept ' "zsh-autosuggestions did not load"
  want widgets '^fzf-tab-complete$' "fzf-tab did not load"
  # Syntax highlighting names no widget of its own; it wraps the ones already
  # bound. _zsh_highlight is the entry point its README tells integrators to use.
  want functions '^_zsh_highlight$' "zsh-syntax-highlighting did not load"

  for name in gs gss gwip gll lg ll l reload! cleanup lpath; do
    want alias "^$name=" "alias $name is missing"
  done
  want alias 'grep -qe "--wip--"' "gunwip still passes its pattern as an option"
  # Counted from the file, not from memory: the number moves every time
  # an alias is added.
  count=$(section alias | grep -c "^g[a-z]*='\{0,1\}git " || true)
  [ "$count" = 30 ] || fail "shell: $count git aliases, expected 30"

  for name in c h g md; do
    want functions "^$name$" "function $name is missing"
  done

  # Every alias the shell defines must be one this repo wrote or one zsh ships.
  # An allowlist rather than a denylist of employer names, so it catches a leak
  # this test was never told to look for, and so no employer is named here.
  zsh -f -i -c 'alias' 2>/dev/null | cut -d= -f1 > "$zsh_home/allowed"
  sed -n 's/^alias \([^=]*\)=.*/\1/p' "$root/config/zsh/aliases.zsh" >> "$zsh_home/allowed"
  sort -u -o "$zsh_home/allowed" "$zsh_home/allowed"
  section alias | cut -d= -f1 | sort -u > "$zsh_home/loaded"
  unexpected=$(comm -23 "$zsh_home/loaded" "$zsh_home/allowed")
  [ -z "$unexpected" ] || fail "shell: aliases not in the tracked file: $(echo $unexpected)"

  # An allowed alias can still carry a work path or a work host in its body.
  deny alias '/Users/\|[a-z0-9-]\{2,\}\.\(com\|io\|dev\|net\|org\)' \
    "an alias body carries a personal path or a remote host"

  # .zprofile runs for login shells only, so a non-login probe never reads it.
  # macOS /etc/zprofile runs path_helper first and appends what .zshenv set
  # behind /usr/bin, which is the order .zprofile exists to correct.
  # PATH is scrubbed to the system minimum first. Inheriting this shell's PATH
  # would put Homebrew there already and the next assertion could never fail.
  login=$(unset ZDOTDIR; HOME=$zsh_home PATH=/usr/bin:/bin zsh -l -i -c 'print -l $path' 2>/dev/null) \
    || fail "login zsh exited non-zero"
  # Position, not presence. A Mac that once had Homebrew installed by hand
  # keeps /etc/paths.d/homebrew, so path_helper supplies /opt/homebrew/bin on
  # its own and a presence check can never fail. Only .zprofile's line puts it
  # ahead of /usr/local/bin.
  at() {
    printf '%s\n' "$login" | grep -n -x -- "$1" | head -1 | cut -d: -f1
  }
  brew_at=$(at /opt/homebrew/bin); local_at=$(at /usr/local/bin)
  repo_at=$(at "$root/bin"); usr_at=$(at /usr/bin)
  [ -n "$brew_at" ] && [ -n "$local_at" ] && [ "$brew_at" -lt "$local_at" ] \
    || fail "shell: .zprofile did not put Homebrew ahead of /usr/local/bin"
  [ -n "$repo_at" ] && [ -n "$usr_at" ] && [ "$repo_at" -lt "$usr_at" ] \
    || fail "shell: a login shell puts \$DOTFILES/bin behind /usr/bin"

  want env "^EZA_CONFIG_DIR=$zsh_home/.config/eza$" "EZA_CONFIG_DIR does not point at the tracked theme directory"
  if [ -f "$root/config/bat/themes/tokyonight_night.tmTheme" ]; then
    want env "^BAT_THEME=tokyonight_night$" "BAT_THEME does not name the tracked bat theme"
  else
    printf 'skip BAT_THEME: config/bat/themes/tokyonight_night.tmTheme is not fetched yet\n'
  fi

  ok "interactive zsh"
else
  printf 'skip interactive zsh: zsh is not on PATH\n'
fi

# `bat cache --build` is in the bootstrap task, and a theme that fails to load
# falls back silently, so the name resolving is not proof. The bootstrap task
# runs from mise without XDG_CONFIG_HOME exported, and bat defaults to
# ~/.config/bat on macOS, so both are covered here.
if command -v bat >/dev/null 2>&1; then
  bat_home=$(mktemp -d)
  mkdir -p "$bat_home/.config/bat/themes"
  # File-level, exactly as the [dotfiles] row spells it.
  ln -s "$root/config/bat/themes/tokyonight_night.tmTheme" \
        "$bat_home/.config/bat/themes/tokyonight_night.tmTheme"
  # XDG_CONFIG_HOME and XDG_CACHE_HOME are unset for these three runs. They are
  # inherited from whoever calls `mise run check`, and .zshenv exports the
  # first, so leaving them set points bat at the caller's real ~/.config/bat.
  # Unset is also the case the bootstrap task actually runs in.
  (unset XDG_CONFIG_HOME XDG_CACHE_HOME
   HOME=$bat_home bat cache --build >/dev/null 2>&1) || fail "bat cache --build"
  (unset XDG_CONFIG_HOME XDG_CACHE_HOME
   HOME=$bat_home bat --list-themes 2>/dev/null) | grep -qx 'tokyonight_night' \
    || fail "bat: the theme does not resolve through the symlink"
  # #c0caf5 is the theme's foreground. A silent fallback paints something else.
  (unset XDG_CONFIG_HOME XDG_CACHE_HOME
   HOME=$bat_home BAT_THEME=tokyonight_night bat --color=always --style=plain \
     "$root/config/ripgrep/config" 2>/dev/null) | grep -q '38;2;192;202;245' \
    || fail "bat: rendered colours do not come from the tracked theme"
  rm -rf "$bat_home"
  ok "bat cache --build"
else
  printf 'skip bat cache --build: bat is not on PATH\n'
fi

# Git, asked rather than grepped. That config/git/config contains the string
# `gpg.format` proves only that this commit wrote it. Whether git reads the
# file through the symlink, whether the include fires and whether the profile
# pattern matches are the three things that actually break.
if command -v git >/dev/null 2>&1; then
  # The homes the setup-git runs above wrote, so git resolves the identity
  # setup-git actually produces. git matches a profile's gitdir pattern against
  # the resolved /private/var path. mktemp hands back /var/..., so both homes
  # are physical paths, or a logical ~ would miss.
  git_home=$sg/personal-fresh/home
  git_work_home=$sg/work-fresh/home
  for h in "$git_home" "$git_work_home"; do
    mkdir -p "$h/.config" "$h/Work/repo" "$h/Personal/repo" "$h/Other/repo"
    # A directory symlink, exactly as the [dotfiles] row spells it.
    ln -s "$root/config/git" "$h/.config/git"
  done

  # GIT_CONFIG_NOSYSTEM keeps Apple's system gitconfig out of every answer.
  # XDG_CONFIG_HOME is unset for the reason the bat block unsets it: .zshenv
  # exports it into whoever runs `mise run check`, and leaving it set points
  # git at the caller's real ~/.config/git instead of this temp one.
  git_at() { # $1: the HOME to run in, then git's arguments
    # cd out of the repo first. The smoke test runs from $root, and a git that
    # starts there reads this repo's .git/config too, so one `git config --local
    # user.name` here would answer for the tracked file and pass.
    (home=$1
     shift
     unset XDG_CONFIG_HOME
     cd "$home"
     HOME=$home GIT_CONFIG_NOSYSTEM=1 git "$@")
  }
  git_probe() { git_at "$git_home" "$@"; }

  resolved=$(git_probe config --list) || fail "git: config --list failed under the temp HOME"
  for kv in \
    'gpg.format=ssh' \
    'push.default=current' \
    'push.autosetupremote=true' \
    'branch.sort=-committerdate' \
    'commit.verbose=true' \
    'diff.algorithm=histogram' \
    'diff.renames=copies' \
    'fetch.prune=true' \
    'grep.linenumber=true' \
    'grep.extendedregexp=true' \
    'help.autocorrect=prompt' \
    'init.defaultbranch=main' \
    'merge.conflictstyle=zdiff3' \
    'pull.ff=only' \
    'rebase.autostash=true' \
    'rebase.updaterefs=true' \
    'rebase.instructionformat=[%an - %ar] %s' \
    'rerere.enabled=true' \
    'rerere.autoupdate=true' \
    'credential.https://github.com.helper=!gh auth git-credential' \
    'core.pager=delta' \
    'interactive.difffilter=delta --color-only' \
    'delta.navigate=true' \
    'delta.line-numbers=true' \
    'delta.syntax-theme=tokyonight_night' \
    'delta.minus-style=syntax #4a272f' \
    'delta.minus-non-emph-style=syntax #4a272f' \
    'delta.minus-emph-style=syntax #713137' \
    'delta.minus-empty-line-marker-style=syntax #4a272f' \
    'delta.line-numbers-minus-style=#914c54' \
    'delta.plus-style=syntax #243e4a' \
    'delta.plus-non-emph-style=syntax #243e4a' \
    'delta.plus-emph-style=syntax #2c5a66' \
    'delta.plus-empty-line-marker-style=syntax #243e4a' \
    'delta.line-numbers-plus-style=#449dab' \
    'delta.line-numbers-zero-style=#3b4261' \
    'user.name=Test Person' \
    'user.email=personal@example.com' \
    'commit.gpgsign=true'
  do
    printf '%s\n' "$resolved" | grep -qxF -- "$kv" || fail "git: $kv did not resolve"
  done

  # Identity reaching git is half of it; reaching it from the untracked file is
  # the other half. --show-origin names the file that won.
  git_probe config --show-origin --get user.name | grep -q '\.gitconfig-local' \
    || fail "git: user.name does not come from ~/.gitconfig-local"
  git_probe config --get core.editor >/dev/null 2>&1 \
    && fail "git: core.editor is set; GIT_EDITOR in .zshenv is the one place the editor is named"

  # Three and no more. Anything that is a plain git invocation is a shell alias.
  aliases="gone browse churn"
  for a in $aliases; do
    git_probe config --get "alias.$a" >/dev/null || fail "git: alias $a is missing"
  done
  want=$(printf '%s\n' $aliases | wc -l | tr -d ' ')
  count=$(printf '%s\n' "$resolved" | grep -c '^alias\.' || true)
  [ "$count" = "$want" ] || fail "git: $count gitconfig aliases, expected $want"

  # Profiles, inside real repositories. Nothing else exercises the trailing
  # slash in `gitdir/i:~/Work/`, which is what makes it match subdirectories.
  # --show-origin puts a tab between the file and the value.
  tab=$(printf '\t')
  identity_is() { # $1: home, $2: repo under it, $3: email, $4: signing key name, $5: the file that wins
    git_at "$1" -C "$1/$2" init -q || fail "git: init failed in ~/$2"
    got=$(git_at "$1" -C "$1/$2" config --show-origin --get user.email || true)
    [ "$got" = "file:$1/$5$tab$3" ] \
      || fail "git: ~/$2 under $1 resolves user.email to ${got:-nothing}, not $3 from ~/$5"
    got=$(git_at "$1" -C "$1/$2" config --show-origin --get user.signingkey || true)
    [ "$got" = "file:$1/$5$tab$1/.ssh/$4.pub" ] \
      || fail "git: ~/$2 under $1 resolves user.signingkey to ${got:-nothing}, not ~/.ssh/$4.pub from ~/$5"
  }
  identity_is "$git_home" Work/repo work@example.com id_ed25519_github .gitconfig-work
  identity_is "$git_home" Personal/repo personal@example.com id_ed25519_github .gitconfig-local
  identity_is "$git_work_home" Work/repo w@example.com id_ed25519_gitlab .gitconfig-work
  identity_is "$git_work_home" Personal/repo p@example.com id_ed25519_github .gitconfig-personal
  identity_is "$git_work_home" Other/repo work@example.com id_ed25519_gitlab .gitconfig-local

  # The row is a directory symlink for one reason: it carries config/git/ignore
  # to ~/.config/git/ignore, and no other probe here would notice its absence.
  for pattern in .DS_Store ._resource .Spotlight-V100 .Trashes notes.swp \
                 CLAUDE.local.md AGENTS.local.md .claude/settings.local.json \
                 .claude/.cc-writes/log .pi/state .pi-subagents/x .pi-goal/x; do
    git_probe -C "$git_home/Personal/repo" check-ignore -q "$pattern" \
      || fail "git: the global ignore does not cover $pattern through the symlink"
  done

  # delta, the pager. Guarded on bat as well, because delta reads its syntax
  # theme out of bat's cache. The bootstrap task's `bat cache --build` is what
  # makes the name resolve, and this builds one the same way. The two
  # backgrounds below are delta's own keys and survive a syntax theme that never
  # loaded, so they cannot be the whole assertion. The theme file is tracked, so
  # its absence fails here rather than skipping.
  if command -v delta >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
    mkdir -p "$git_home/.config/bat/themes"
    ln -s "$root/config/bat/themes/tokyonight_night.tmTheme" \
          "$git_home/.config/bat/themes/tokyonight_night.tmTheme"
    # Both XDG vars are unset for the reason the bat block unsets both: they
    # come from whoever calls `mise run check`, and a set XDG_CACHE_HOME sends
    # this build into that caller's own bat cache and reads the result back.
    (unset XDG_CONFIG_HOME XDG_CACHE_HOME
     HOME=$git_home bat cache --build >/dev/null 2>&1) \
      || fail "delta: bat cache --build failed under the temp HOME"

    # Two commits, so there is a real diff to render. setup-git's local file
    # turns gpgsign on and names a stub key, so it is off here.
    delta_repo=$git_home/Personal/repo
    printf 'one\ntwo\n' >"$delta_repo/f.txt"
    git_probe -C "$delta_repo" add f.txt || fail "delta: staging the first revision failed"
    git_probe -C "$delta_repo" -c commit.gpgsign=false commit -qm one \
      || fail "delta: the first fixture commit failed"
    printf 'one\nTWO\nthree\n' >"$delta_repo/f.txt"
    git_probe -C "$delta_repo" add f.txt || fail "delta: staging the second revision failed"
    git_probe -C "$delta_repo" -c commit.gpgsign=false commit -qm two \
      || fail "delta: the second fixture commit failed"

    # git pages to a terminal only, and this runs on a pipe, so delta is invoked
    # by hand. `core.pager = delta` reaching git is asserted in the list above.
    # The two run separately so a git failure cannot hide behind delta's exit.
    raw=$(git_probe -C "$delta_repo" log -p -1 --no-color) \
      || fail "delta: git log failed in the fixture repo"
    # Exported, not prefixed. A prefix binds to the printf, and delta is the
    # process that wants the config.
    rendered=$(unset XDG_CONFIG_HOME XDG_CACHE_HOME
               cd "$delta_repo"
               HOME=$git_home
               GIT_CONFIG_NOSYSTEM=1
               export HOME GIT_CONFIG_NOSYSTEM
               printf '%s\n' "$raw" | delta --paging=never) \
      || fail "delta: rendering the diff failed"
    # #243e4a is plus-style's background, #4a272f is minus-style's, both from the
    # tracked [delta] block.
    printf '%s' "$rendered" | grep -q '48;2;36;62;74' \
      || fail "delta: the added line carries no tokyonight plus background"
    printf '%s' "$rendered" | grep -q '48;2;74;39;47' \
      || fail "delta: the removed line carries no tokyonight minus background"
    # #c0caf5 is the tmTheme's foreground and the only byte here that proves
    # syntax-theme resolved. A name that does not exist paints both backgrounds
    # above, writes one line to stderr and exits 0.
    printf '%s' "$rendered" | grep -q '38;2;192;202;245' \
      || fail "delta: the diff text is not coloured by the tokyonight_night syntax theme"
    ok "delta pager"
  else
    printf 'skip delta pager: delta, bat or the tracked bat theme is missing\n'
  fi

  # The include is the last line of the tracked file so the machine's own file
  # wins. Nothing tracked overlaps ~/.gitconfig-local today, so the order only
  # shows itself once something does.
  printf '[init]\n\tdefaultBranch = trunk\n' >>"$git_home/.gitconfig-local"
  branch=$(git_probe config --get init.defaultBranch || true)
  [ "$branch" = trunk ] \
    || fail "git: ~/.gitconfig-local loses to the tracked config; the include is not last"

  # A warning, not a failure: a machine mid-migration is a legal state, and the
  # fresh Mac this repo targets has no ~/.gitconfig at all.
  if [ -e "$HOME/.gitconfig" ]; then
    printf 'warn ~/.gitconfig exists here, so git ignores ~/.config/git/config; move it aside\n'
  fi
  ok "git config"
else
  printf 'skip git config: git is not on PATH\n'
fi

# ssh offers github.com and gitlab.com each its own key and nothing else.
# ssh_config takes the first value per keyword, so a host stanza after Host *
# loses any keyword Host * ever sets.
host_at() {
  # The first line number of an exact Host line, or nothing.
  awk -v h="Host $1" '$0 == h { print NR; exit }' config/ssh/config
}
github_at=$(host_at github.com) gitlab_at=$(host_at gitlab.com) any_at=$(host_at '*')
[ -n "$github_at" ] && [ -n "$gitlab_at" ] && [ -n "$any_at" ] \
  || fail "ssh: config/ssh/config lacks a Host github.com, Host gitlab.com or Host * line"
[ "$github_at" -lt "$gitlab_at" ] && [ "$gitlab_at" -lt "$any_at" ] \
  || fail "ssh: the stanzas are not in the order github.com, gitlab.com, *"
# ssh -G resolves the config as a connection would and opens no key, so the
# answer is the same on a Mac without ~/.ssh/id_ed25519_gitlab. ssh takes ~
# from the passwd entry, not HOME, so a temp HOME would change nothing. -T
# stops the pseudo-terminal warning a pipe would print.
for forge in github gitlab; do
  ssh_resolved=$(ssh -T -G "$forge.com" -F config/ssh/config </dev/null) \
    || fail "ssh: ssh -G $forge.com exits non-zero"
  ids=$(printf '%s\n' "$ssh_resolved" | grep '^identityfile ' || true)
  [ "$ids" = "identityfile ~/.ssh/id_ed25519_$forge" ] \
    || fail "ssh: $forge.com is offered $(printf '%s' "${ids:-nothing}" | tr '\n' ' '), not just ~/.ssh/id_ed25519_$forge"
  printf '%s\n' "$ssh_resolved" | grep -qx 'identitiesonly yes' \
    || fail "ssh: $forge.com lacks IdentitiesOnly yes, so the agent offers every key it holds"
done
ok "ssh host stanzas"

# Tracked config files, through one probe. Each names dotted paths and the value
# it expects, so a missing path and a changed value fail separately.
#
# A numeric segment indexes a list. The Claude hook command sits under two of
# them, and without indexing that assertion would have to be dropped: a dropped
# assertion is how the yazi theme shipped with every glyph missing.
#
# The fourth argument names paths that must not resolve at all. Absence is its
# own assertion and the expected-value map cannot make it, because a missing
# path is how that map reports a failure.
probe_yaml() {
  # A label, the file, a JSON object of path to expected value, and optionally a
  # JSON array of paths that must be absent.
  [ -f "$2" ] || fail "$1: $2 is missing"
  cfg_json=$(yq -p yaml -o json "$2") || fail "$2 does not parse"
  SRC=$2 CFG_JSON=$cfg_json WANT_JSON=$3 ABSENT_JSON=${4:-[]} python3 - <<'PROBE' || fail "$1"
import sys, os, json

cfg = json.loads(os.environ["CFG_JSON"])
src = os.environ["SRC"]
errs = []
missing = object()

def resolve(path):
    node = cfg
    for key in path.split("."):
        if isinstance(node, list):
            if not key.isdigit() or int(key) >= len(node):
                return missing
            node = node[int(key)]
            continue
        if not isinstance(node, dict) or key not in node:
            return missing
        node = node[key]
    return node

for path, expected in json.loads(os.environ["WANT_JSON"]).items():
    got = resolve(path)
    if got is missing:
        errs.append(f"{src}: {path} is missing")
    elif got != expected:
        errs.append(f"{src}: {path} is {got!r}, expected {expected!r}")

for path in json.loads(os.environ["ABSENT_JSON"]):
    got = resolve(path)
    # An empty array is a present key, and the write this catches makes one.
    if got is not missing:
        errs.append(f"{src}: {path} is present as {got!r}, expected absent")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
PROBE
  ok "$1"
}


# The eza theme, out of the zsh block where it used to live. Nothing here needs
# zsh, so a machine without one skipped it for no reason.
#
# It used to assert only that the file parses, weaker than every other theme
# probe here. colourful is what eza wants before it honours most of the file,
# the directory colour is the one most visible on screen, and the last key in
# the file catches a truncated fetch. A fetch through a markdown converter has
# already stripped one tracked theme in this repo.
probe_yaml "eza theme" config/eza/theme.yml '{
  "colourful": true,
  "filekinds.directory.foreground": "#7aa2f7",
  "broken_path_overlay.foreground": "#ff007c"
}'

# lazygit, parsed rather than run. It has no flag that dumps the config it
# resolved, only its defaults, and it wants a terminal. One theme colour is
# enough: it fails when the theme block is absent, truncated or recoloured.
probe_yaml "lazygit config" config/lazygit/config.yml '{
  "os.editPreset": "nvim-remote",
  "gui.nerdFontsVersion": "3",
  "disableStartupPopups": true,
  "git.paging.colorArg": "always",
  "git.paging.pager": "delta --dark --paging=never",
  "gui.theme.activeBorderColor": ["#ff9e64", "bold"]
}'

# The shared instruction file, which both agents read through their own
# symlink. `mise run refresh-unslop` rewrites everything between the markers,
# so the three ways it can go wrong are a marker that is not there exactly
# once, a block carrying no rules, and a fetch that took the user's own rules
# down with it. The last one is why this probe reads above the first marker.
#
# Counting the rules rather than asking whether the block is empty is the same
# lesson the yazi theme taught: a fetch through a markdown converter stripped
# every glyph from that file and it still parsed. Upstream calls its rule
# numbers stable ids and leaves a gap when it drops one, so the count only ever
# grows and a floor cannot go red on an honest upstream change.
#
# A missing file never reaches here: the manifest section above fails on any
# [dotfiles] row whose source does not exist.
AGENTS_FILE=home/.agents/AGENTS.md python3 - <<'AGENTS' || fail "shared instruction file"
import sys, os, re, pathlib

src = os.environ["AGENTS_FILE"]
text = pathlib.Path(src).read_text()
start, end = "<!-- unslop:start -->", "<!-- unslop:end -->"
errs = []

for marker in (start, end):
    seen = text.count(marker)
    if seen != 1:
        errs.append(f"{src}: {marker} appears {seen} times, expected once")

if not errs:
    above, _, rest = text.partition(start)
    block = rest.partition(end)[0]
    # The attribution comment refresh-unslop writes itself is not content. A
    # fetch that left only that behind has lost the rules.
    body = re.sub(r"<!--.*?-->", "", block, flags=re.S)
    rules = len(re.findall(r"^\d+\. ", body, flags=re.M))
    if not above.strip():
        errs.append(f"{src}: nothing above {start}; the user's own rules are gone")
    if rules < 10:
        errs.append(f"{src}: the block between the markers carries {rules} "
                    "numbered rules, expected at least 10")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
AGENTS
ok "shared instruction file"

# Claude Code's settings, which yq parses as YAML unchanged. Read from the file
# rather than asked of the tool, which every probe here prefers: `claude` has no
# subcommand that prints the settings it resolved, and a bare `claude config`
# is taken as a prompt and answered.
#
# Three of the eight paths are what an unattended pane depends on: auto mode,
# the denied credential paths, and five minutes before a long test suite is
# killed. The hook is the fourth and the one that earns its place. `herdr
# integration install claude` writes the same entry with this laptop's home path
# baked in, and the tracked file is a symlink it can reach, so an absolute path
# here is a bootstrap side effect to remove rather than a state to commit.
# Asserted whole rather than as a `bash ~/` prefix, since the rest of the line
# is just as fixed, and with the matcher and timeout beside it: an entry that
# lost either one binds to nothing or waits forever.
#
# The deny list is asserted as one list rather than counted. A count of thirteen
# passes a file where `~/.ssh/**` became `~/.ssh.bak/**`.
#
# Neither `allow` nor `ask` may be there, and neither may arrive empty either.
# Approvals belong in ~/.claude/settings.local.json, which this repo does not
# track; an `allow` here would be the client writing into the symlink, and on
# the work laptop it would be employer paths in a public repo. `ask` is gone by
# decision: in a pane nobody is watching, a prompt is a stall.
probe_yaml "claude settings" home/.claude/settings.json '{
  "model": "opus",
  "effortLevel": "high",
  "permissions.defaultMode": "auto",
  "permissions.deny": [
    "Read(.env)",
    "Read(.env.*)",
    "Read(secrets/**)",
    "Read(~/.ssh/**)",
    "Edit(~/.ssh/**)",
    "Read(~/.aws/**)",
    "Edit(~/.aws/**)",
    "Read(~/.config/gh/hosts.yml)",
    "Edit(~/.config/gh/hosts.yml)",
    "Read(~/.claude.json)",
    "Edit(~/.claude.json)",
    "Read(~/.pi/agent/auth.json)",
    "Edit(~/.pi/agent/auth.json)"
  ],
  "env.BASH_DEFAULT_TIMEOUT_MS": "300000",
  "hooks.SessionStart.0.matcher": "*",
  "hooks.SessionStart.0.hooks.0.command": "bash ~/.claude/hooks/herdr-agent-state.sh session",
  "hooks.SessionStart.0.hooks.0.timeout": 10
}' '["permissions.allow", "permissions.ask"]'

# pi's settings. The provider and model are the pair that decides whether a
# fresh Mac's first `pi` opens on a working model or on a login error, so both
# are asserted by name; they flip together the day there is a ChatGPT
# subscription. The pinned source is the whole point of tracking `packages`:
# someone else's skills land on this machine only when the tag here moves.
#
# `enableInstallTelemetry` is asserted although nothing in this repo sets it by
# hand, because pi writes this file itself from /settings and a toggle there
# would put the vendor ping back with nothing else to notice it.
# `defaultThinkingLevel` is deliberately left out for the mirror-image reason:
# changing it from /thinking is ordinary use and should not turn this red.
#
# The three empty arrays are load-bearing and read backwards. In pi 0.85.1 an
# absent key loads everything that type; an empty array is the only way to say
# none (`applyPackageFilter`, "Empty array explicitly disables all resources of
# this type"). Dropping them would install a third party's extensions, which are
# executable, on the next bootstrap.
probe_yaml "pi settings" home/.pi/agent/settings.json '{
  "theme": "Tokyo Night",
  "defaultProvider": "openai",
  "defaultModel": "gpt-5.6-terra",
  "enableInstallTelemetry": false,
  "packages.0.source": "git:github.com/mattpocock/skills@v1.2.3",
  "packages.0.extensions": [],
  "packages.0.prompts": [],
  "packages.0.themes": []
}'

# The same pinned source, twice: `setup-agents:pi` installs it and these
# settings declare it. Bumping one and not the other leaves pi loading skills it
# was not told about, which is the thing the pin exists to prevent.
SRC=$(printf '%s' "$global_personal_json" | yq -r '.tasks."setup-agents:pi".run') \
WANT=$(yq -p yaml -o json home/.pi/agent/settings.json | yq -r '.packages[0].source') \
python3 - <<'PISRC' || fail "pi skills pin"
import sys, os, re

run = os.environ["SRC"]
want = os.environ["WANT"]
installed = re.findall(r"^\s*pi install (\S+)", run, flags=re.M)
if installed != [want]:
    print(f"  setup-agents:pi runs `pi install` on {installed}, but pi's settings "
          f"pin {want!r}", file=sys.stderr)
    sys.exit(1)
PISRC
ok "pi skills pin"

# The clean filter, asserted where it actually runs rather than in the worktree.
# Reading this file for the absence of lastChangelogVersion would be red forever
# on any machine that uses pi: ~/.pi/agent/settings.json is a symlink to it, pi
# writes the key through the link on every update, and the filter strips it on
# commit without touching the worktree. So the key comes back and stays.
#
# What matters is the filter working, so that is what is asserted: the
# attribute is still wired in .gitattributes, and the blob git stored carries no
# key. Before the first commit of this file there is no blob, which is the one
# case that has nothing to say rather than something to hide.
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  attr=$(git -C "$root" check-attr filter -- home/.pi/agent/settings.json)
  case "$attr" in
    *": filter: pi-settings") ;;
    *) fail "pi clean filter: .gitattributes no longer names the filter for pi's settings ($attr)" ;;
  esac
  # Repo-local by design: a --global write would land in the tracked git config.
  # [tasks.bootstrap] registers it, so a clone that has not bootstrapped yet is
  # a warning and not a failure, the way ~/.gitconfig is above.
  if [ -z "$(git -C "$root" config --get filter.pi-settings.clean || true)" ]; then
    printf 'warn filter.pi-settings.clean is not registered in this clone; run mise run bootstrap\n'
  fi
  if git -C "$root" cat-file -e HEAD:home/.pi/agent/settings.json 2>/dev/null; then
    git -C "$root" show HEAD:home/.pi/agent/settings.json \
      | python3 -c 'import json,sys; sys.exit(1 if "lastChangelogVersion" in json.load(sys.stdin) else 0)' \
      || fail "pi clean filter: the committed settings carry lastChangelogVersion"
  else
    printf 'skip pi clean filter blob: pi settings are not committed yet\n'
  fi
  ok "pi clean filter"
else
  printf 'skip pi clean filter: not a git checkout\n'
fi

# pi's theme, vendored byte-for-byte from folke/tokyonight.nvim at
# extras/pi/tokyonight_night.json and owned from here on. No refresh task: a
# colour file has no upstream fixes worth chasing.
#
# The name is "Tokyo Night", not the file's stem. pi registers a custom theme
# under the `name` inside the JSON and ignores the filename, so the settings key
# has to carry that string; upstream names only the other three variants after
# themselves. The two are asserted equal below, which is the assertion that
# actually decides whether pi opens themed or on its default.
#
# userMessageBg is what separates Night from Storm and Moon, and bashMode is the
# last key in the file, so a truncated fetch cannot pass. The repo has shipped a
# theme through a markdown converter with every glyph dropped once already.
probe_yaml "pi theme" home/.pi/agent/themes/tokyonight_night.json '{
  "name": "Tokyo Night",
  "colors.accent": "#7aa2f7",
  "colors.userMessageBg": "#16161e",
  "colors.bashMode": "#ff9e64"
}'

# The count and the cross-file link, neither of which probe_yaml can say. The
# names are pi 0.85.1's own required set out of modes/interactive/theme/
# theme-json.js; a theme missing one loads as an error, not a fallback. Names
# rather than a count, so a misspelled token cannot pass by keeping the total
# right, and the five pi marks optional are allowed rather than demanded.
SETTINGS=$(yq -p yaml -o json home/.pi/agent/settings.json) \
THEME=$(yq -p yaml -o json home/.pi/agent/themes/tokyonight_night.json) \
python3 - <<'PITHEME' || fail "pi theme tokens"
import sys, os, json

REQUIRED = set("""
accent border borderAccent borderMuted success error warning muted dim text
thinkingText selectedBg userMessageBg userMessageText customMessageBg
customMessageText customMessageLabel toolPendingBg toolSuccessBg toolErrorBg
toolTitle toolOutput mdHeading mdLink mdLinkUrl mdCode mdCodeBlock
mdCodeBlockBorder mdQuote mdQuoteBorder mdHr mdListBullet toolDiffAdded
toolDiffRemoved toolDiffContext syntaxComment syntaxKeyword syntaxFunction
syntaxVariable syntaxString syntaxNumber syntaxType syntaxOperator
syntaxPunctuation thinkingOff thinkingMinimal thinkingLow thinkingMedium
thinkingHigh thinkingXhigh bashMode
""".split())
OPTIONAL = {"scrollbarTrack", "scrollbarThumb", "searchMatchBg",
            "searchMatchText", "thinkingMax"}

theme = json.loads(os.environ["THEME"])
settings = json.loads(os.environ["SETTINGS"])
errs = []

got = set(theme.get("colors", {}))
for name in sorted(REQUIRED - got):
    errs.append(f"the theme is missing the required colour token {name}")
# Anything pi does not know is a typo in a required name or a token from a
# newer pi, and either way the file stopped being the port that was vendored.
for name in sorted(got - REQUIRED - OPTIONAL):
    errs.append(f"the theme carries {name}, which pi 0.85.1 does not define")

want = settings.get("theme")
if want != theme.get("name"):
    errs.append(f"settings ask for theme {want!r}, but the tracked theme is named "
                f"{theme.get('name')!r}; pi resolves by name and would fall back")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
PITHEME
ok "pi theme tokens"

# The bridge extension names three strings it does not own: two pi event names
# and herdr's event channel. Rename any of them upstream and the file still
# loads, still parses and quietly does nothing, which is the one failure that
# reading the file can never catch. So read them back out of the installed pi
# and the installed herdr. Proving it really emits needs a pi TUI inside a herdr
# pane, which a shell script cannot stand up; that half is verified by hand.
# The manifest shape probe already fails on a [dotfiles] source that is gone,
# so this one only has to care about what is inside the file.
bridge=home/.pi/agent/extensions/herdr-blocked-bridge.ts
for name in ui_prompt_start ui_prompt_end herdr:blocked; do
  grep -q "$name" "$bridge" || fail "$bridge names no $name"
done

if command -v pi >/dev/null 2>&1; then
  # The bin is a shim several symlinks deep; the package root is what holds the
  # compiled event names, and it is whatever the shim finally resolves into.
  pi_bin=$(readlink -f "$(command -v pi)" 2>/dev/null) || pi_bin=
  pi_root=${pi_bin%/dist/*}
  if [ -n "$pi_bin" ] && [ -d "$pi_root/dist/core" ]; then
    for name in ui_prompt_start ui_prompt_end; do
      grep -rq "$name" "$pi_root/dist/core" \
        || fail "the installed pi emits no $name, so the bridge would load and do nothing"
    done
    ok "pi blocked bridge names"
  else
    printf 'skip pi blocked bridge names: no package root under %s\n' "$(command -v pi)"
  fi
else
  printf 'skip pi blocked bridge names: pi is not on PATH\n'
fi

# herdr's own pi extension is the listener on the other end. It is
# herdr-managed and untracked, so the only honest source for the channel name
# is what `herdr integration install pi` writes. Into $tmp_home, which the trap
# above already cleans up, and it refuses a HOME with no extensions directory.
# A Mac without pi never runs that install, so it has nothing to check.
if ! command -v pi >/dev/null 2>&1; then
  printf 'skip herdr blocked listener: pi is not on PATH\n'
elif command -v herdr >/dev/null 2>&1; then
  herdr_pi=$tmp_home/herdr-pi
  mkdir -p "$herdr_pi/.pi/agent/extensions"
  if HOME=$herdr_pi herdr integration install pi >/dev/null 2>&1; then
    grep -rq "herdr:blocked" "$herdr_pi/.pi/agent/extensions" \
      || fail "the installed herdr listens for no herdr:blocked, so the bridge would emit into nothing"
    ok "herdr blocked listener"
  else
    printf 'skip herdr blocked listener: herdr integration install pi failed here\n'
  fi
else
  printf 'skip herdr blocked listener: herdr is not on PATH\n'
fi

# herdr's config, validated by herdr rather than by this script. `config check`
# has no path argument and reads $XDG_CONFIG_HOME/herdr/config.toml, so the
# tracked file is reached through a temp XDG root holding a symlink to it.
# Inside $tmp_home, so the trap above already cleans it up.
if command -v herdr >/dev/null 2>&1; then
  herdr_xdg=$tmp_home/herdr-xdg
  mkdir -p "$herdr_xdg/herdr"
  ln -sf "$root/config/herdr/config.toml" "$herdr_xdg/herdr/config.toml"
  # herdr prints its diagnostics and falls back to defaults rather than dying,
  # so the exit status is the whole signal; the output is for the reader.
  if ! out=$(XDG_CONFIG_HOME=$herdr_xdg herdr config check 2>&1); then
    printf '%s\n' "$out" >&2
    fail "herdr config check rejects config/herdr/config.toml"
  fi
  ok "herdr config check"
else
  printf 'skip herdr config check: herdr is not on PATH\n'
fi

# The four Plannotator keys, by command name. `config check` passes a file whose
# key blocks parsed and then resolved to nothing, so the names are asserted here
# and, on a machine that has bootstrapped, against the actions the installed
# plugin actually publishes. That second half is what turns an upstream rename
# red instead of silent. It reads plugins.json, the registry `herdr plugin
# install` writes, because `herdr plugin action list` needs a running server.
herdr_json=$(yq -p toml -o json config/herdr/config.toml) \
  || fail "config/herdr/config.toml does not parse"
CFG_JSON=$herdr_json PLUGINS=${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins.json \
python3 - <<'HERDRKEYS' || fail "herdr keys"
import sys, os, json

want = {
    "annotate.capture",
    "annotate.copy-context",
    "annotate.copy-archive",
    "annotate.manage",
}
cfg = json.loads(os.environ["CFG_JSON"])
errs = []

blocks = cfg.get("keys", {}).get("command", [])
got = {b.get("command") for b in blocks}
for missing in sorted(want - got):
    errs.append(f"config/herdr/config.toml binds no key to {missing}")
for extra in sorted(got - want):
    errs.append(f"config/herdr/config.toml binds {extra}, which is not one of the four")

# Every block is a plugin action on a prefix key. A block that lost its type
# would parse and then do something else entirely on the same keystroke.
for b in blocks:
    if b.get("type") != "plugin_action":
        errs.append(f"{b.get('command')} is type {b.get('type')!r}, expected 'plugin_action'")
    if not str(b.get("key", "")).startswith("prefix+"):
        errs.append(f"{b.get('command')} is bound to {b.get('key')!r}, which leaves the prefix")

path = os.environ["PLUGINS"]
if os.path.exists(path):
    with open(path) as fh:
        published = {
            f"{p['plugin_id']}.{a['id']}"
            for p in json.load(fh)
            for a in p.get("actions", [])
        }
    for gone in sorted(want - published):
        errs.append(f"{gone} is bound here but the installed plugin publishes no such action")
else:
    print(f"skip herdr keys against the installed plugin: {path} is missing")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
HERDRKEYS
ok "herdr keys"

# Karabiner's file is read as parsed JSON, since Karabiner may rewrite it with
# its own key order and indentation. Nothing here can press a key, so only
# typing on the board by hand proves that it types its keycaps.
#
# The § key is grave_accent_and_tilde only after the built-in swap runs, and
# Karabiner runs that swap before complex rules. Without the swap entry the
# same rules land on <>, so this probe checks the two together. right_option
# is Ghostty's Alt, and a rule emitting it turns a backtick into an Alt
# sequence, so the raw text may not name it at all, descriptions included.
[ -f config/karabiner/karabiner.json ] || fail "karabiner config: config/karabiner/karabiner.json is missing"
ROOT_JSON=$root_json python3 - <<'KARABINER' || fail "karabiner config"
import sys, os, json

src = "config/karabiner/karabiner.json"
errs = []
with open(src) as fh:
    text = fh.read()
cfg = json.loads(text)

row = json.loads(os.environ["ROOT_JSON"]).get("dotfiles", {}).get("~/.config/karabiner")
if row != "config/karabiner":
    errs.append(f"mise.toml maps ~/.config/karabiner to {row!r}, expected the directory config/karabiner")

if cfg.get("global", {}).get("show_in_menu_bar") is not False:
    errs.append(f"{src}: global.show_in_menu_bar is not false")
if "right_option" in text:
    errs.append(f"{src}: names right_option, which is Ghostty's Alt")

profiles = cfg.get("profiles", [])
if len(profiles) != 1:
    errs.append(f"{src}: {len(profiles)} profiles, expected 1")
profile = profiles[0] if profiles else {}
if profile.get("selected") is not True:
    errs.append(f"{src}: the profile is not selected")
if profile.get("virtual_hid_keyboard", {}).get("keyboard_type_v2") != "iso":
    errs.append(f"{src}: keyboard_type_v2 is not iso")

# One entry, the built-in board. An external board gets its own entry the day
# the user buys one.
devices = profile.get("devices", [])
if len(devices) != 1 or devices[0].get("identifiers") != {"is_keyboard": True} \
        or devices[0].get("swap_grave_accent_and_non_us_backslash") is not True:
    errs.append(f"{src}: devices is {devices!r}, expected only the built-in swap entry")

mods = profile.get("complex_modifications", {})
params = mods.get("parameters", {})
for key in ("basic.to_if_alone_timeout_milliseconds", "basic.to_if_held_down_threshold_milliseconds"):
    if params.get(key) != 200:
        errs.append(f"{src}: {key} is {params.get(key)!r}, expected 200")

rules = mods.get("rules", [])
if len(rules) != 3:
    errs.append(f"{src}: {len(rules)} rules, expected Caps Lock, Shift+§ and §")
else:
    def sole_manipulator(rule):
        found = rule.get("manipulators", [])
        if len(found) != 1:
            errs.append(f"{src}: rule {rule.get('description')!r} has {len(found)} manipulators, expected 1")
            return {}
        return found[0]
    caps, shifted, bare = (sole_manipulator(r) for r in rules)
    # optional any keeps Shift+Caps and Command+Caps working.
    if caps.get("from") != {"key_code": "caps_lock", "modifiers": {"optional": ["any"]}} \
            or caps.get("to") != [{"key_code": "left_control"}] \
            or caps.get("to_if_alone") != [{"key_code": "escape"}]:
        errs.append(f"{src}: the first rule is not Caps Lock to left_control, Escape alone")
    # Karabiner takes the first match, so Shift+§ has to come before bare §.
    for m, name in ((shifted, "second"), (bare, "third")):
        if m.get("from", {}).get("key_code") != "grave_accent_and_tilde":
            errs.append(f"{src}: the {name} rule is not on § (grave_accent_and_tilde)")
    if shifted.get("from", {}).get("modifiers") != {"mandatory": ["shift"]}:
        errs.append(f"{src}: the second rule does not require Shift")
    if "modifiers" in bare.get("from", {}):
        errs.append(f"{src}: the third rule takes modifiers, so it shadows Option+§ or Command+§")
    # Option+¨ is the dead tilde that Space commits, and Shift+Option+´ is a
    # direct backtick on Finnish.
    if shifted.get("to") != [{"key_code": "close_bracket", "modifiers": ["left_option"]},
                             {"key_code": "spacebar"}]:
        errs.append(f"{src}: Shift+§ does not emit left Option+¨ then Space")
    if bare.get("to") != [{"key_code": "equal_sign", "modifiers": ["left_shift", "left_option"]}]:
        errs.append(f"{src}: § does not emit left Shift+Option+´")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
KARABINER
ok "karabiner config"

# AeroSpace's file, parsed and read as structure. The real parser needs the
# server running, so a person checks by hand that AeroSpace accepts the file.
# A config file replaces every default bind, so the bind sets are exact. A bind
# this file leaves out does nothing.
#
# Borders reads its colours from the bar's palette, so this probe checks that
# file too. It sources the palette with an empty environment, so the caller's
# own variables cannot fill a name the file forgot.
#
# A missing aerospace.toml never reaches here: the manifest section above fails
# on its row. Its row for the palette names the directory, so the file itself
# needs the guard.
[ -f config/sketchybar/colors.sh ] || fail "aerospace config: config/sketchybar/colors.sh is missing"
sh -n config/sketchybar/colors.sh || fail "syntax config/sketchybar/colors.sh"
aerospace_json=$(yq -p toml -o json config/aerospace/aerospace.toml) \
  || fail "config/aerospace/aerospace.toml does not parse"
ROOT_JSON=$root_json AEROSPACE_JSON=$aerospace_json python3 - <<'AEROSPACE' || fail "aerospace config"
import sys, os, re, json, subprocess

src = "config/aerospace/aerospace.toml"
palette = "config/sketchybar/colors.sh"
errs = []
cfg = json.loads(os.environ["AEROSPACE_JSON"])
with open(src) as fh:
    text = fh.read()

rows = json.loads(os.environ["ROOT_JSON"]).get("dotfiles", {})
for target, want in (("~/.config/aerospace/aerospace.toml", src),
                     ("~/.config/sketchybar", "config/sketchybar")):
    if rows.get(target) != want:
        errs.append(f"mise.toml maps {target} to {rows.get(target)!r}, expected {want}")

if cfg.get("config-version") != 2:
    errs.append(f"{src}: config-version is {cfg.get('config-version')!r}, expected 2")
for key in ("start-at-login", "auto-reload-config"):
    if cfg.get(key) is not True:
        errs.append(f"{src}: {key} is not true")
# Under config-version 2 only a listed workspace survives being empty, and the
# bar draws all five.
if cfg.get("persistent-workspaces") != ["1", "2", "3", "4", "5"]:
    errs.append(f"{src}: persistent-workspaces is {cfg.get('persistent-workspaces')!r}, expected 1 to 5")

# The file is diff-only. These keys would only restate AeroSpace's fallback,
# and there is no [exec] table because its default PATH already finds borders.
for key in ("default-root-container-layout", "default-root-container-orientation",
            "key-mapping", "accordion-padding", "exec",
            "enable-normalization-flatten-containers",
            "enable-normalization-opposite-orientation-for-nested-containers"):
    if key in cfg:
        errs.append(f"{src}: sets {key}, which the file leaves to AeroSpace's fallback")
modes = cfg.get("mode", {})
# A round Borders stroke shows only its outer half, so each gap is exactly
# that half per window and the borders fill the space with nothing between.
# macOS keeps windows out of a notched display's top strip even with the menu
# bar hidden, so only a display without a notch adds the 38-point bar.
startup = cfg.get("after-startup-command", [])
width = re.search(r" width=(\d+) ", startup[0] if startup else "")
half = int(width.group(1)) // 2 if width else None
want_gaps = {"inner": {"horizontal": 2 * half, "vertical": 2 * half} if half else None,
             "outer": {"left": half, "right": half, "bottom": half,
                       "top": [{"monitor": {"built-in": half}}, 38 + half]} if half else None}
if cfg.get("gaps") != want_gaps:
    errs.append(f"{src}: gaps are {cfg.get('gaps')!r}, expected {want_gaps!r} for Borders' width")
if set(modes) != {"main", "service"}:
    errs.append(f"{src}: modes are {sorted(modes)}, expected main and service")

main = modes.get("main", {}).get("binding", {})
want_main = {
    "alt-h": "focus left", "alt-j": "focus down", "alt-k": "focus up", "alt-l": "focus right",
    "alt-shift-h": "move left", "alt-shift-j": "move down",
    "alt-shift-k": "move up", "alt-shift-l": "move right",
    "alt-minus": "resize smart -50", "alt-equal": "resize smart +50",
    "alt-q": "workspace 1", "alt-w": "workspace 2", "alt-e": "workspace 3",
    "alt-r": "workspace 4", "alt-t": "workspace 5",
    "alt-shift-q": "move-node-to-workspace --focus-follows-window 1",
    "alt-shift-w": "move-node-to-workspace --focus-follows-window 2",
    "alt-shift-e": "move-node-to-workspace --focus-follows-window 3",
    "alt-shift-r": "move-node-to-workspace --focus-follows-window 4",
    "alt-shift-t": "move-node-to-workspace --focus-follows-window 5",
    "alt-tab": "workspace-back-and-forth",
    "alt-shift-f": "fullscreen",
    "alt-shift-semicolon": "mode service",
}
if main != want_main:
    for key in sorted(set(main) | set(want_main)):
        if main.get(key) != want_main.get(key):
            errs.append(f"{src}: main bind {key} is {main.get(key)!r}, expected {want_main.get(key)!r}")
# Option with a digit types @ and $ on Finnish, Alt+F is zsh's forward-word,
# and Karabiner's § rules emit the last two chords, which AeroSpace would
# catch before the app does.
for key in main:
    if re.fullmatch(r"alt-(shift-)?\d", key) \
            or key in ("alt-f", "alt-shift-equal", "alt-rightSquareBracket"):
        errs.append(f"{src}: main mode binds {key}, which Finnish or Karabiner needs")

service = modes.get("service", {}).get("binding", {})
want_service = {
    "esc": ["reload-config", "mode main"],
    "r": ["flatten-workspace-tree", "mode main"],
    "f": ["layout floating tiling", "mode main"],
    "backspace": ["close-all-windows-but-current", "mode main"],
    "alt-shift-h": ["join-with left", "mode main"],
    "alt-shift-j": ["join-with down", "mode main"],
    "alt-shift-k": ["join-with up", "mode main"],
    "alt-shift-l": ["join-with right", "mode main"],
    "q": "enable off",
    "b": ["exec-and-forget sketchybar --bar hidden=toggle", "mode main"],
}
if service != want_service:
    for key in sorted(set(service) | set(want_service)):
        if service.get(key) != want_service.get(key):
            errs.append(f"{src}: service bind {key} is {service.get(key)!r}, expected {want_service.get(key)!r}")
if service.get("q") != "enable off":
    errs.append(f"{src}: service q is {service.get('q')!r}, expected 'enable off'")
# A mode command after enable registers hotkeys whose handler dies while the
# server is off.
for key, cmd in service.items():
    joined = " ".join(cmd) if isinstance(cmd, list) else str(cmd)
    if "enable" in joined and "mode" in joined:
        errs.append(f"{src}: service bind {key} runs both enable and mode")
# The bar subscribes to mode-changed, so this file only starts the bar and
# toggles it. The colors.sh path, the startup entry and service mode's b are
# the places the name may appear.
bar_start = ("exec-and-forget pkill -x sketchybar; for _ in {1..20}; do "
             "pgrep -qx sketchybar || break; sleep 0.1; done; sketchybar")
bar_toggle = "exec-and-forget sketchybar --bar hidden=toggle"
if "sketchybar" in text.replace("~/.config/sketchybar/colors.sh", "").replace(bar_start, "") \
        .replace(bar_toggle, ""):
    errs.append(f"{src}: names sketchybar outside the colors.sh path, the startup entry "
                "and the bar toggle")

# First match wins, so the float rule has to be last, and 0.21.3 refuses a
# callback with no if.
callbacks = cfg.get("on-window-detected", [])
if len(callbacks) != 4:
    errs.append(f"{src}: {len(callbacks)} window callbacks, expected 4")
for i, cb in enumerate(callbacks):
    if "if" not in cb:
        errs.append(f"{src}: window callback {i + 1} has no if")
if callbacks and (callbacks[-1].get("if") != "true" or callbacks[-1].get("run") != "layout floating"):
    errs.append(f"{src}: the last window callback is not if = 'true', run = 'layout floating'")
# The whole if string, so a changed joiner or a trailing && false cannot pass.
want_routes = [(["org.mozilla.thunderbird", "com.tinyspeck.slackmacgap"], "1"),
               (["net.librewolf.librewolf", "com.google.Chrome"], "2"),
               (["com.mitchellh.ghostty"], "3")]
for i, (ids, ws) in enumerate(want_routes):
    cb = callbacks[i] if i < len(callbacks) else {}
    want_if = " || ".join(f"test %{{app-bundle-id}} = {app}" for app in ids)
    if cb.get("if") != want_if or cb.get("run") != f"move-node-to-workspace {ws}":
        errs.append(f"{src}: window callback {i + 1} does not send {ids} to workspace {ws}")
for gone in ("app.zen-browser.zen", "net.imput.helium"):
    if gone in json.dumps(callbacks):
        errs.append(f"{src}: a window callback names {gone}, which this setup dropped")

startup = cfg.get("after-startup-command", [])
if len(startup) != 2:
    errs.append(f"{src}: after-startup-command has {len(startup)} entries, expected 2")
else:
    # The bar's entry must match Borders' kill and wait exactly, so a dropped wait fails.
    if startup[1] != bar_start:
        errs.append(f"{src}: after-startup-command's second entry is {startup[1]!r}, "
                    f"expected {bar_start!r}")
    # The whole kill and wait, so a dropped bound or a lone pgrep cannot pass.
    stop = ("pkill -x borders; for _ in {1..20}; do pgrep -qx borders || break; "
            "sleep 0.1; done; ")
    m = re.fullmatch(r"exec-and-forget (.*?)source ~/\.config/sketchybar/colors\.sh && (.*)",
                     startup[0])
    if m and m.group(1) != stop:
        errs.append(f"{src}: after-startup-command does not stop an earlier borders "
                    "and wait for it to exit")
    args = m.group(2).split() if m else []
    if not args or args[0] != "borders" \
            or "active_color=$ACCENT" not in args or "inactive_color=$GUTTER" not in args:
        errs.append(f"{src}: after-startup-command does not source the palette and start borders "
                    "with $ACCENT and $GUTTER")

# The names a bare shell exports, such as PWD and SHLVL, are subtracted so
# only the palette's own exports remain.
def exported(script):
    out = subprocess.run(["env", "-i", "/bin/sh", "-c", script, "sh", palette],
                         capture_output=True, text=True)
    if out.returncode != 0:
        errs.append(f"{palette}: sourcing it failed: {out.stderr.strip()}")
    return dict(line.split("=", 1) for line in out.stdout.splitlines() if "=" in line)
colors = exported('. "./$1" && env')
for name in exported("env"):
    colors.pop(name, None)
want_names = {"FG", "FG_DIM", "GREY", "GUTTER", "ACCENT", "BAR_COLOR", "ITEM_BG", "PILL_BG",
              "HAIRLINE", "POPUP_BG", "RED", "GREEN", "YELLOW", "ORANGE", "MAGENTA"}
if set(colors) != want_names:
    errs.append(f"{palette}: exports {sorted(colors)}, expected {sorted(want_names)}")
for name, value in sorted(colors.items()):
    if not re.fullmatch(r"0x[0-9a-f]{8}", value):
        errs.append(f"{palette}: {name} is {value!r}, not 0xAARRGGBB")
for name, want in (("ACCENT", "0xff7aa2f7"), ("GUTTER", "0xff3b4261")):
    if colors.get(name) != want:
        errs.append(f"{palette}: {name} is {colors.get(name)!r}, expected {want}")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
AEROSPACE
ok "aerospace config"

# The bar. Each script runs as SketchyBar runs it, with NAME, SENDER and
# CONFIG_DIR and nothing else from this shell, against stubs on PATH. The
# sketchybar stub writes each call as one shell-quoted line, so a label that
# splits into two arguments shows in the log, and a glyph reads as its code
# point, such as <U+F4BC>. The other stubs log their arguments, print the
# case's fixture and exit with its code.
bar_dir=config/sketchybar
[ -x /opt/homebrew/bin/bash ] || fail "bar: /opt/homebrew/bin/bash is missing; brew:bash installs it"
for f in $bar_dir/sketchybarrc $bar_dir/plugins/*; do
  [ "$(head -n 1 "$f")" = '#!/opt/homebrew/bin/bash' ] \
    || fail "bar: $f does not start with #!/opt/homebrew/bin/bash"
  [ -x "$f" ] || fail "bar: $f is not executable"
  /opt/homebrew/bin/bash -n "$f" || fail "syntax $f"
  # A theme change must touch colors.sh alone.
  if grep -Eq '0x[0-9a-fA-F]{8}' "$f"; then fail "bar: $f names a hex colour"; fi
done

bar=$tmp_home/bar
mkdir -p "$bar/stubs"
# The stubs run with an empty environment, where a mise shim finds no python.
printf '#!%s\n' "$(python3 -c 'import sys; print(sys.executable)')" >"$bar/stubs/sketchybar"
cat >>"$bar/stubs/sketchybar" <<'EOF'
import os, re, shlex, sys
args = ["sketchybar"] + [re.sub(r"[^\x00-\x7f]", lambda m: f"<U+{ord(m[0]):04X}>", a) for a in sys.argv[1:]]
with open(os.environ["BAR_LOG"], "a") as fh:
    fh.write(shlex.join(args) + "\n")
sys.exit(int(os.environ["BAR_SB_EXIT"]))
EOF
for name in networksetup pmset ipconfig memory_pressure ps sysctl pgrep date; do
  cat >"$bar/stubs/$name" <<'EOF'
#!/bin/sh
name=${0##*/}
echo "$name $*" >>"$BAR_LOG"
if [ -f "$BAR_FIX/$name" ]; then cat "$BAR_FIX/$name"; fi
exit "$(cat "$BAR_FIX/$name.exit" 2>/dev/null || echo 0)"
EOF
done
chmod +x "$bar"/stubs/*

bar_reset() { rm -rf "$bar/fix"; mkdir "$bar/fix"; : >"$bar/log"; }
bar_fixture() { # $1: command, $2: what it prints, $3: its exit code
  printf '%s\n' "$2" >"$bar/fix/$1"
  echo "${3:-0}" >"$bar/fix/$1.exit"
}
bar_run() { # $1: case, $2: script under config/sketchybar, $3: NAME, then its arguments
  # BAR_SB_EXIT, when set, is the exit code of every sketchybar call.
  bar_case=$1 bar_script=$2 bar_name=$3
  shift 3
  env -i HOME="$bar" PATH="$bar/stubs:/usr/bin:/bin" CONFIG_DIR="$root/$bar_dir" \
    NAME="$bar_name" SENDER=routine BAR_LOG="$bar/log" BAR_FIX="$bar/fix" BAR_SB_EXIT="${BAR_SB_EXIT:-0}" \
    "$root/$bar_dir/$bar_script" "$@" 2>"$bar/err" || fail "bar: $bar_case exited nonzero"
  if [ -s "$bar/err" ]; then fail "bar: $bar_case wrote to stderr: $(cat "$bar/err")"; fi
}
bar_log_is() { # $1: the log the last bar_run must have written
  [ "$(cat "$bar/log")" = "$1" ] || fail "bar: $bar_case logged:
$(cat "$bar/log")"
}
bar_color() { env -i /bin/sh -c '. "./$1" && eval "echo \$$2"' sh $bar_dir/colors.sh "$1"; }
bar_fg=$(bar_color FG) bar_red=$(bar_color RED)

# The Wi-Fi port is en7 here, so a hard-coded en0 fails.
bar_reset
bar_fixture networksetup 'Hardware Port: Ethernet Adapter (en3)
Device: en3
Ethernet Address: 4a:54:21:a3:2e:b9

Hardware Port: Wi-Fi
Device: en7
Ethernet Address: fc:b2:14:af:90:c5'
bar_run sketchybarrc sketchybarrc ""
BAR_LOG=$bar/log CONFIG_DIR=$root/$bar_dir BAR_COLOR=$(bar_color BAR_COLOR) FG=$bar_fg \
python3 - <<'BAR' || fail "bar: sketchybarrc"
import os, shlex, sys
errs = []
plugins = os.environ["CONFIG_DIR"] + "/plugins"
lines = open(os.environ["BAR_LOG"]).read().splitlines()
others = [l for l in lines if not l.startswith("sketchybar ")]
if others != ["networksetup -listallhardwareports"]:
    errs.append(f"ran {others}, expected only networksetup -listallhardwareports")

def pairs(args):
    out = {}
    for a in args:
        if "=" not in a:
            errs.append(f"{a!r} is not property=value")
            continue
        k, v = a.split("=", 1)
        out[k] = v
    return out

bar, defaults, items, flags = {}, {}, {}, []
for line in lines:
    if not line.startswith("sketchybar "):
        continue
    argv = shlex.split(line)[1:]
    i = 0
    while i < len(argv):
        flag, args, i = argv[i], [], i + 1
        while i < len(argv) and not argv[i].startswith("--"):
            args.append(argv[i])
            i += 1
        flags.append(flag)
        if flag == "--bar":
            bar.update(pairs(args))
        elif flag == "--default":
            defaults.update(pairs(args))
        elif flag == "--add" and len(args) == 3 and args[0] == "item":
            items[args[1]] = {"position": args[2], "props": {}, "events": []}
        elif flag in ("--set", "--subscribe") and args and args[0] in items:
            if flag == "--set":
                items[args[0]]["props"].update(pairs(args[1:]))
            else:
                items[args[0]]["events"] += args[1:]
        elif flag != "--update" or args:
            errs.append(f"unexpected {flag} {args}")
if not flags or flags[-1] != "--update":
    errs.append("the last call is not --update, so the readouts wait for their first poll")

# The bar covers the native menu bar, which macOS still slides in on a hover.
want_bar = {"height": "38", "position": "top", "y_offset": "0", "display": "all",
            "topmost": "on", "color": os.environ["BAR_COLOR"], "border_width": "0"}
if not os.environ["BAR_COLOR"].startswith("0xff"):
    errs.append(f"BAR_COLOR is {os.environ['BAR_COLOR']}, not opaque, so the native menu bar shows through")
if bar != want_bar:
    errs.append(f"bar is {bar}, expected {want_bar}")
want_defaults = {"icon.font": "Symbols Nerd Font:Regular:14.0", "icon.color": os.environ["FG"],
                 "label.font": "Monaspace Neon:Regular:13.0", "label.color": os.environ["FG"]}
for k, v in want_defaults.items():
    if defaults.get(k) != v:
        errs.append(f"default {k} is {defaults.get(k)!r}, expected {v!r}")

wifi_click = "open 'x-apple.systempreferences:com.apple.wifi-settings-extension'"
want = [
    ("clock", "right", {"update_freq": "30", "script": f"{plugins}/clock.sh"}, []),
    ("wifi", "right", {"update_freq": "60", "script": f"{plugins}/wifi.sh en7",
                       "click_script": wifi_click}, ["wifi_change", "system_woke"]),
    ("battery", "right", {"update_freq": "120", "script": f"{plugins}/battery.sh"},
     ["power_source_change", "system_woke"]),
    ("memory", "right", {"update_freq": "15", "script": f"{plugins}/memory.sh"}, []),
    ("cpu", "right", {"update_freq": "5", "script": f"{plugins}/cpu.sh"}, []),
    ("watchdog", "right", {"update_freq": "10", "script": f"{plugins}/watchdog.sh",
                           "drawing": "off"}, []),
]
if list(items) != [w[0] for w in want]:
    errs.append(f"items are {list(items)}, expected {[w[0] for w in want]}")
wiring = ("update_freq", "script", "click_script", "drawing")
for name, position, props, events in want:
    item = items.get(name)
    if item is None:
        continue
    got = {k: v for k, v in item["props"].items() if k in wiring}
    if item["position"] != position:
        errs.append(f"{name} is at {item['position']}, expected {position}")
    if got != props:
        errs.append(f"{name} is wired {got}, expected {props}")
    if item["events"] != events:
        errs.append(f"{name} subscribes to {item['events']}, expected {events}")
    script = item["props"].get("script", "").split(" ")[0]
    if not os.access(script, os.X_OK):
        errs.append(f"{name}'s script {script} is not an executable file")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
BAR

bar_reset
bar_fixture date '27/10/2026 16:17'
bar_run "clock" plugins/clock.sh clock
bar_log_is "date +%d/%m/%Y %H:%M
sketchybar --set clock drawing=on 'label=27/10/2026 16:17'"
bar_reset
bar_fixture date '' 1
bar_run "clock, date failing" plugins/clock.sh clock
bar_log_is "date +%d/%m/%Y %H:%M
sketchybar --set clock drawing=off"

# 32.2 over four cores rounds down to 8.
bar_reset
bar_fixture ps '  1.8
 10.0
 20.4'
bar_fixture sysctl 4
bar_run "cpu" plugins/cpu.sh cpu
bar_log_is "ps -A -o %cpu=
sysctl -n hw.ncpu
sketchybar --set cpu drawing=on 'icon=<U+F4BC>' label=8%"
bar_reset
bar_fixture ps '  1.8'
bar_fixture sysctl '' 1
bar_run "cpu, sysctl failing" plugins/cpu.sh cpu
bar_log_is "ps -A -o %cpu=
sysctl -n hw.ncpu
sketchybar --set cpu drawing=off"

bar_reset
bar_fixture memory_pressure 'The system has 17179869184 (1048576 pages with a page size of 16384).
Pageouts: 2585

System-wide memory free percentage: 77%'
bar_run "memory" plugins/memory.sh memory
bar_log_is "memory_pressure 
sketchybar --set memory drawing=on 'icon=<U+F035B>' label=23%"
bar_reset
bar_fixture memory_pressure '' 1
bar_run "memory, memory_pressure failing" plugins/memory.sh memory
bar_log_is "memory_pressure 
sketchybar --set memory drawing=off"

# pmset's battery line, with its tab, as this Mac prints it.
bar_batt() { # $1: power source, $2: percentage, $3: state
  printf "Now drawing from '%s'\n -InternalBattery-0 (id=27459683)\t%s%%; %s; 6:16 remaining present: true" \
    "$1" "$2" "$3"
}
bar_reset
bar_fixture pmset "$(bar_batt 'Battery Power' 73 discharging)"
bar_run "battery discharging" plugins/battery.sh battery
bar_log_is "pmset -g batt
sketchybar --set battery drawing=on 'icon=<U+F241>' icon.color=$bar_fg label=73% label.color=$bar_fg"
bar_reset
bar_fixture pmset "$(bar_batt 'AC Power' 45 charging)"
bar_run "battery charging" plugins/battery.sh battery
bar_log_is "pmset -g batt
sketchybar --set battery drawing=on 'icon=<U+F0084>' icon.color=$bar_fg label=45% label.color=$bar_fg"
bar_reset
bar_fixture pmset "$(bar_batt 'Battery Power' 20 discharging)"
bar_run "battery at 20%" plugins/battery.sh battery
bar_log_is "pmset -g batt
sketchybar --set battery drawing=on 'icon=<U+F243>' icon.color=$bar_red label=20% label.color=$bar_red"
bar_reset
bar_fixture pmset "Now drawing from 'AC Power'"
bar_run "no battery" plugins/battery.sh battery
bar_log_is "pmset -g batt
sketchybar --set battery drawing=off"

bar_reset
bar_fixture ipconfig '<dictionary> {
  InterfaceType : WiFi
  LinkStatusActive : TRUE
}'
bar_run "wifi active" plugins/wifi.sh wifi en7
bar_log_is "ipconfig getsummary en7
sketchybar --set wifi drawing=on 'icon=<U+F05A9>'"
bar_reset
bar_fixture ipconfig '<dictionary> {
  Active : FALSE
  LinkStatusActive : FALSE
}'
bar_run "wifi inactive" plugins/wifi.sh wifi en7
bar_log_is "ipconfig getsummary en7
sketchybar --set wifi drawing=on 'icon=<U+F05AA>'"
bar_reset
bar_fixture ipconfig '' 1
bar_run "wifi, ipconfig failing" plugins/wifi.sh wifi en7
bar_log_is "ipconfig getsummary en7
sketchybar --set wifi drawing=off"
bar_reset
bar_run "no wifi device" plugins/wifi.sh wifi
bar_log_is "sketchybar --set wifi drawing=off"

# AeroSpace starts the bar, so it is the watchdog's ancestor, and pgrep skips
# ancestors without -a. Without it the bar quits the moment AeroSpace starts it.
bar_reset
bar_run "watchdog, AeroSpace running" plugins/watchdog.sh watchdog
bar_log_is "pgrep -aqx AeroSpace"
bar_reset
bar_fixture pgrep '' 1
bar_run "watchdog, AeroSpace gone" plugins/watchdog.sh watchdog
bar_log_is "pgrep -aqx AeroSpace
sketchybar --exit"
ok "bar"

# Ghostty's file, read by Ghostty. validate-config rejects an unknown key, a
# bad enum value, an unknown theme and an unknown action, but not an unknown
# font, so a person checks the font by hand. The cask links no binary onto
# PATH, and outside a Ghostty window the app's own directory is not on it.
ghostty_bin=$(command -v ghostty 2>/dev/null || true)
if [ -z "$ghostty_bin" ] && [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]; then
  ghostty_bin=/Applications/Ghostty.app/Contents/MacOS/ghostty
fi
if [ -n "$ghostty_bin" ]; then
  if ! out=$("$ghostty_bin" +validate-config --config-file="$root/config/ghostty/config.ghostty" 2>&1); then
    printf '%s\n' "$out" >&2
    fail "ghostty +validate-config rejects config/ghostty/config.ghostty"
  fi
  # A file symlink, the way the row links it, so config-file resolves the way
  # it does on a real Mac. The temp HOME hides Application Support's
  # config.ghostty, which loads after the XDG file and would win.
  ghostty_xdg=$tmp_home/ghostty-xdg
  mkdir -p "$ghostty_xdg/ghostty"
  ln -sf "$root/config/ghostty/config.ghostty" "$ghostty_xdg/ghostty/config.ghostty"
  ghostty_resolved=$(HOME=$tmp_home XDG_CONFIG_HOME=$ghostty_xdg "$ghostty_bin" +show-config 2>&1) \
    || fail "ghostty +show-config"
  ghostty_default=$(HOME=$tmp_home "$ghostty_bin" +show-config --default 2>&1) \
    || fail "ghostty +show-config --default"
  ROOT_JSON=$root_json GHOSTTY_XDG=$ghostty_xdg GHOSTTY_RESOLVED=$ghostty_resolved \
    GHOSTTY_DEFAULT=$ghostty_default python3 - <<'GHOSTTY' || fail "ghostty config"
import sys, os, json

src = "config/ghostty/config.ghostty"
errs = []

def parse(lines):
    pairs = []
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) > 1 and value[0] == value[-1] == '"':
            value = value[1:-1]
        pairs.append((key.strip(), value))
    return pairs

# A keybind's value is trigger=action, and the trigger is what one line of
# the file replaces, so binds are keyed by trigger and everything else by key.
def table(pairs):
    scalars, binds = {}, {}
    for key, value in pairs:
        if key == "keybind":
            trigger, _, action = value.partition("=")
            binds[trigger] = action
        else:
            scalars[key] = value
    return scalars, binds

resolved, resolved_binds = table(parse(os.environ["GHOSTTY_RESOLVED"].splitlines()))
default, default_binds = table(parse(os.environ["GHOSTTY_DEFAULT"].splitlines()))
with open(src) as fh:
    tracked = parse(fh)

rows = json.loads(os.environ["ROOT_JSON"]).get("dotfiles", {})
if rows.get("~/.config/ghostty/config.ghostty") != src:
    errs.append(f"mise.toml maps ~/.config/ghostty/config.ghostty to {rows.get('~/.config/ghostty/config.ghostty')!r}, expected {src}")
# Ghostty still reads a plain config and loads config.ghostty after it, so a
# second row would split the settings across two files.
if "~/.config/ghostty/config" in rows:
    errs.append("mise.toml links ~/.config/ghostty/config beside config.ghostty")

want = {
    "font-family": "Monaspace Neon",
    "font-size": "12",
    "theme": "TokyoNight Night",
    "macos-option-as-alt": "right",
    "macos-titlebar-style": "hidden",
    "window-padding-x": "8",
    "window-padding-y": "8",
    "window-padding-balance": "true",
    "mouse-hide-while-typing": "true",
    "copy-on-select": "clipboard",
    "auto-update": "check",
    "config-file": "?" + os.environ["GHOSTTY_XDG"] + "/ghostty/config.local",
}
for key, value in want.items():
    if resolved.get(key) != value:
        errs.append(f"{src}: {key} resolves to {resolved.get(key)!r}, expected {value!r}")
# AeroSpace tiles a native tab as a window, so no key may open one.
if resolved_binds.get("super+t") != "new_window":
    errs.append(f"{src}: super+t is {resolved_binds.get('super+t')!r}, expected new_window")
for trigger, action in resolved_binds.items():
    if action == "new_tab":
        errs.append(f"{src}: {trigger} still opens a tab")

# Diff-only: a line that restates Ghostty's default is noise that hides the
# lines that matter.
for key, value in tracked:
    if key == "keybind":
        trigger, _, action = value.partition("=")
        if default_binds.get(trigger) == action:
            errs.append(f"{src}: keybind {trigger} restates the default {action}")
    elif default.get(key, "") == value:
        errs.append(f"{src}: {key} = {value} restates the default")

for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
GHOSTTY
  ok "ghostty config"
else
  printf 'skip ghostty config: no Ghostty binary on PATH or in /Applications\n'
fi

# The real parser, when a mise exists. This block went red on every Mac with
# mise on it until the three tap entries left [bootstrap.packages]; see the
# note there. It has no value as a pass/fail gate unless it can reach one.
#
# HOME is a temp directory, the way every other dry run above takes one. With
# the real HOME the dotfiles phase refuses to overwrite whatever already sits
# at a target and the run ends there, so the probe graded this laptop rather
# than the manifest and went redder with every row an area added. Against a
# fresh HOME the plan runs to the final hooks, which is the first time mise
# itself reaches the defaults, tools, task and hook phases here. The refusal
# is still worth knowing before a first bootstrap, so it is the warning below.
if command -v mise >/dev/null 2>&1; then
  # Inside $tmp_home so the trap above already cleans it up.
  mise_home=$tmp_home/mise-home
  mkdir -p "$mise_home"
  # HOME alone does not make it fresh. .zshenv exports XDG_CONFIG_HOME as an
  # absolute path, so both runs below would inherit the caller's and read the
  # real ~/.config/mise/config.toml through it. Measured: with it set,
  # `mise config ls` lists that file and all 30 of its tools. Unset for the
  # same reason the bat probe unsets it. Unsetting it is not enough on its own,
  # since mise still finds the same file by searching the clone's parents, so
  # both runs also take the ceiling set at the top of this file.
  #
  # MISE_TRUSTED_CONFIG_PATHS goes with it. This repo does not grant trust
  # through that variable, and inherited it would grant trust anyway: an
  # untrusted temp HOME exits 1 without it and 0 with it, which is exactly the
  # mutation the trust call below has to stay honest about.
  #
  # The same trust install.sh grants, pinned into the temp HOME for the reason
  # the zsh probe pins it: MISE_STATE_DIR outranks both HOME and an inherited
  # XDG_STATE_HOME. Untrusted, the dry run exits 1 on the manifest it never
  # read, so a missing grant cannot become a pass that asserted nothing.
  dry_state=$mise_home/.local/state/mise
  dry_trust=$(unset XDG_CONFIG_HOME MISE_TRUSTED_CONFIG_PATHS
              HOME=$mise_home MISE_STATE_DIR=$dry_state MISE_CEILING_PATHS=$mise_ceiling \
                mise trust "$root/mise.toml" 2>&1) \
    || fail "mise trust failed against the dry run's HOME: $dry_trust"
  # mise writes the plan to stderr, three hundred lines of it against this
  # manifest, so both streams are captured and printed only on a failure.
  plan=$(unset XDG_CONFIG_HOME MISE_TRUSTED_CONFIG_PATHS
         HOME=$mise_home MISE_STATE_DIR=$dry_state MISE_CEILING_PATHS=$mise_ceiling \
           mise bootstrap --dry-run 2>&1) || {
    printf '%s\n' "$plan" >&2
    fail "mise bootstrap --dry-run"
  }
  # The exit code alone does not say how far the run got, and the plan is now
  # hidden on success, so a mise that stopped early would look identical to one
  # that finished. This is the last phase header mise prints, and reaching it is
  # the whole reason the HOME above is a temp directory. A grep for package
  # names was the other candidate and lost: it echoed an assertion made
  # elsewhere, while this one is about truncation and nothing else asserts it.
  printf '%s\n' "$plan" | grep -q '^mise bootstrap: final hooks$' \
    || fail "mise bootstrap --dry-run stopped before the final hooks"
  ok "mise bootstrap --dry-run"
else
  printf 'skip mise bootstrap --dry-run: mise is not on PATH\n'
fi

# What the dotfiles phase above used to die on, read from the real HOME that
# the dry run deliberately cannot see. A warning and not a failure, for the
# same reason the ~/.gitconfig warning gives: a machine mid-migration is a
# legal state and the fresh Mac this repo targets holds none of these. Needs
# no mise, so it also tells a machine without one what a bootstrap would hit.
occupied=$(ROOT_JSON=$root_json python3 - <<'PY'
import os, json, pathlib

home = pathlib.Path.home()

def occupied(path):
    # What mise refuses, measured against `mise dot apply` 2026.9.8: a symlink
    # it overwrites, right or wrong or dangling, and anything else already
    # there it leaves alone and fails on. So a second bootstrap is silent here
    # and only a file placed by hand is named.
    if path.is_symlink():
        return False
    if path.exists():
        return True
    # A target under a parent that is a file does not exist and cannot be
    # created either. Rare, and the rule above would call it free.
    for parent in path.parents:
        if parent == home or parent == parent.parent:
            return False
        if parent.exists() and not parent.is_dir():
            return True
    return False

for target in json.loads(os.environ["ROOT_JSON"]).get("dotfiles", {}):
    # expanduser rather than slicing off "~/", so an absolute target is left
    # alone instead of being measured against the repo it is declared in.
    if occupied(pathlib.Path(target).expanduser()):
        print("  " + target)
PY
) || fail "dotfiles targets"
if [ -n "$occupied" ]; then
  printf 'warn a first bootstrap refuses these targets, which already hold files here; move them aside:\n%s\n' "$occupied"
fi
ok "dotfiles targets"

# Every tool in [tools], asserted present. `mise bootstrap --dry-run` above
# parses the manifest and installs nothing, so a backend that fails leaves no
# mark on this suite. Before this block, bat and delta were the only tools in
# the inventory named anywhere here, and both only as guards deciding whether
# to skip.
#
# The inventory is read from the tracked file rather than asked of mise. On a
# machine where ~/.config/mise/config.toml is not linked yet, mise reports no
# tools at all, so a probe that asked mise would print ok having asserted
# nothing. Reading the file cannot pass with zero coverage.
#
# `command -v` answers whether something on PATH has that name, not whether
# mise put it there. On a Mac carrying a brew bat or delta as well, a failed
# mise backend could still pass. A fresh Mac has no such overlap: brew installs
# eza, bash, the zsh plugins, btop, sketchybar and borders, and none of those
# is in [tools].
tools_in() {
  # One [tools] key per line. Strict: an unrecognised line is a failure, never
  # a skip, because a silently dropped tool is the failure this block exists to
  # catch. Verified against tomllib on both tracked files, keys and order.
  # A second argument lets the file have no [tools] table at all, which the
  # work overlay may; a table that yields nothing still fails.
  awk -v optional="${2:-}" '
    /^[[:space:]]*\[/ {
      h = $0
      sub(/[[:space:]]*#.*$/, "", h); sub(/^[[:space:]]+/, "", h); sub(/[[:space:]]+$/, "", h)
      if (h == "[tools]") { intools = 1; seen = 1; next }
      # [tools.foo] declares a tool the flat scan below would never see.
      if (h ~ /^\[tools\./) {
        printf "  %s:%d: sub-table %s; this reads flat keys only\n", FILENAME, FNR, h > "/dev/stderr"
        bad = 1
      }
      intools = 0
      next
    }
    !intools { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == "" || line ~ /^#/) next
      if (line ~ /^"[^"]+"[[:space:]]*=/) {            # "backend:name" = ...
        k = line; sub(/^"/, "", k); sub(/"[[:space:]]*=.*$/, "", k); print k; n++; next
      }
      if (line ~ /^[A-Za-z0-9_-]+[[:space:]]*=/) {     # bare-key = ...
        k = line; sub(/[[:space:]]*=.*$/, "", k); print k; n++; next
      }
      printf "  %s:%d: unrecognised line in [tools]: %s\n", FILENAME, FNR, $0 > "/dev/stderr"
      bad = 1
    }
    END {
      if (n == 0 && !(optional && !seen)) {
        printf "  %s: [tools] yielded no keys; the table moved or the file is unreadable\n", FILENAME > "/dev/stderr"
        bad = 1
      }
      exit bad
    }
  ' "$1"
}

tools_map() {
  # Inventory key, then the commands it installs, which is not the key wherever
  # a backend prefix or a package name differs from the binary: ripgrep installs
  # rg, github-cli installs gh, npm:typescript installs tsc. A key missing from
  # this table fails below, so a tool added to [tools] cannot go unasserted by
  # being forgotten.
  #
  # Read off a real install rather than guessed: every tool here was installed
  # into a throwaway HOME on 2026-09-13 with mise 2026.9.6 and the binaries
  # listed. Only the commands a tool is wanted for are asserted, so pnpm's pn,
  # pnpx and pnx and node's corepack, npm and npx are left out. yq joined
  # [tools] after that run, with the parser swap above; its release archive
  # carries one binary and it is named yq. glab was installed the same way on
  # 2026-10-27 with mise 2026.10.15, and its one binary is glab.
  #
  # An exception carries `-` in place of its commands and a reason after a #.
  # There are none. If this list ever reaches two or three, the rule that
  # everything must resolve is the thing that is wrong, not this table.
  cat <<'MAP'
node node
pnpm pnpm
fzf fzf
fd fd
ripgrep rg
zoxide zoxide
bat bat
jq jq
yq yq
yazi yazi ya
starship starship
glow glow
shellcheck shellcheck
github:agavra/tuicr tuicr
delta delta
lazygit lazygit
github-cli gh
gitlab:gitlab-org/cli glab
aqua:neovim/neovim nvim
stylua stylua
lua-language-server lua-language-server
marksman marksman
oxlint oxlint
oxfmt oxfmt
npm:typescript tsc
npm:vscode-langservers-extracted vscode-css-language-server vscode-eslint-language-server vscode-html-language-server vscode-json-language-server vscode-markdown-language-server
npm:yaml-language-server yaml-language-server
npm:bash-language-server bash-language-server
herdr herdr
claude claude
pi pi
MAP
}

tools_cmds() {
  # A key's command list, or non-zero when the key has no line at all. Field
  # one is the key, which is why keys must not contain spaces; none do.
  tools_map | awk -v k="$1" '$1 == k {
    $1 = ""; sub(/[[:space:]]*#.*$/, ""); sub(/^[[:space:]]+/, ""); print; f = 1
  } END { exit !f }'
}

# Drift first, and with no mise guard on it. This half reads two tracked files
# and nothing else, so gating it behind `command -v mise` would hand it the
# disease this block was written to cure: a check that has never once run on
# the machine it was written on.
tools_keys=$(tools_in config/mise/config.toml) || fail "tools: config/mise/config.toml"
work_keys=$(tools_in config/mise/config.work.toml optional) || fail "tools: config/mise/config.work.toml"
personal_keys=$(tools_in config/mise/config.personal.toml) || fail "tools: config/mise/config.personal.toml"
all_keys="$tools_keys${work_keys:+
$work_keys}
$personal_keys"

drift=
for key in $all_keys; do
  tools_cmds "$key" >/dev/null || drift="$drift
  $key is in [tools] with no line in tools_map; add the command it installs"
done
for mapped in $(tools_map | awk '{ print $1 }'); do
  printf '%s\n' "$all_keys" | grep -qxF -- "$mapped" \
    || drift="$drift
  $mapped is in tools_map but no longer in [tools]; delete the line"
done
if [ -n "$drift" ]; then
  fail "tools inventory$drift"
fi
ok "tools inventory ($(printf '%s\n' "$all_keys" | wc -l | tr -d ' ') tools)"

# Resolution. Skipped whole when mise is absent, because without mise nothing
# in [tools] can be installed and every assertion below would be noise.
if command -v mise >/dev/null 2>&1; then
  # An overlay's tools exist only where the overlay loads. MISE_ENV is the
  # documented switch, and miserc.toml is what install.sh actually writes;
  # that file sets MISE_ENV for mise itself and is invisible as a variable
  # here, so both are consulted.
  env_loads() {
    case "${MISE_ENV:-}" in *"$1"*) return 0 ;; esac
    grep -qs "^env *=.*\"$1\"" "${XDG_CONFIG_HOME:-$HOME/.config}/mise/miserc.toml"
  }
  check_keys=$tools_keys
  if env_loads work && [ -n "$work_keys" ]; then
    check_keys="$check_keys
$work_keys"
  fi
  if env_loads personal; then
    check_keys="$check_keys
$personal_keys"
  fi

  missing= asserted=0 skipped=0
  for key in $check_keys; do
    cmds=$(tools_cmds "$key") || fail "tools: $key lost its map line mid-run"
    if [ "$cmds" = "-" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    for cmd in $cmds; do
      if command -v "$cmd" >/dev/null 2>&1; then
        asserted=$((asserted + 1))
      else
        missing="$missing
  $key declares $cmd, which is not on PATH"
      fi
    done
  done
  [ -z "$missing" ] || fail "tools did not install:$missing"
  ok "tools resolve ($asserted commands, $skipped exceptions)"
else
  printf 'skip tools resolve: mise is not on PATH\n'
fi

# glab reads GLAB_CONFIG_DIR as given, so an unrendered "{{ env.HOME }}" would
# send its login to a relative directory named after the template. The temp
# HOME holds only the work overlay. Offline, because mise env otherwise asks
# gitlab.com which version "latest" is; offline it warns and still renders.
if command -v mise >/dev/null 2>&1; then
  # Inside $tmp_home so the trap above already cleans it up.
  env_home=$tmp_home/work-env
  mkdir -p "$env_home/.config/mise"
  ln -s "$root/config/mise/config.work.toml" "$env_home/.config/mise/config.work.toml"
  work_env=$(unset XDG_CONFIG_HOME
             cd "$env_home"
             HOME=$env_home MISE_ENV=work MISE_CEILING_PATHS=$env_home MISE_OFFLINE=1 \
               mise env --json 2>"$env_home/stderr") \
    || fail "work env: mise env failed under the temp HOME: $(cat "$env_home/stderr")"
  WORK_ENV=$work_env WANT_DIR=$env_home/.config/glab-cli python3 - <<'PY' || fail "work env"
import json, os, sys
env = json.loads(os.environ["WORK_ENV"])
errs = []
if env.get("GLAB_CONFIG_DIR") != os.environ["WANT_DIR"]:
    errs.append(f"GLAB_CONFIG_DIR renders to {env.get('GLAB_CONFIG_DIR')!r}, not {os.environ['WANT_DIR']!r}")
if env.get("GLAB_SEND_TELEMETRY") != "0":
    errs.append(f"GLAB_SEND_TELEMETRY renders to {env.get('GLAB_SEND_TELEMETRY')!r}, not '0'")
for e in errs:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errs else 0)
PY
  ok "work env"
else
  printf 'skip work env: mise is not on PATH\n'
fi
