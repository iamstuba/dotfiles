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

ROOT_JSON=$root_json GLOBAL_JSON=$global_json WORK_JSON=$work_json \
STARSHIP_JSON=$starship_json YAZI_JSON=$yazi_json TUICR_JSON=$tuicr_json \
python3 - <<'PY' || fail "manifest shape"
import sys, os, json, pathlib

root = json.loads(os.environ["ROOT_JSON"])
global_cfg = json.loads(os.environ["GLOBAL_JSON"])
work = json.loads(os.environ["WORK_JSON"])
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
# The zsh probe below grants the same trust to its own temp HOME, so without
# this the probe would stay green while a bootstrapped Mac went back to mise
# warning on every shell start. Only the work answer reaches this far.
for f in mise.toml config/mise/config.toml config/mise/config.work.toml; do
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
    trust_out=$(HOME=$zsh_home MISE_STATE_DIR=$mise_state \
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
  # has to read the trust granted above and not the caller's.
  # The output is cut into labelled sections, so an alias cannot satisfy an
  # assertion meant for a key binding.
  out=$(unset ZDOTDIR; HOME=$zsh_home MISE_STATE_DIR=$mise_state zsh -i -c '
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
  # Physical, because mktemp hands back /var/... and git matches a profile's
  # gitdir pattern against the resolved /private/var path, so a logical ~ misses.
  git_home=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$git_home/.config" "$git_home/Work/repo" "$git_home/Personal/repo"
  # A directory symlink, exactly as the [dotfiles] row spells it.
  ln -s "$root/config/git" "$git_home/.config/git"

  # Byte for byte what setup-git writes for GIT_PROFILES='~/Work=work@example.com'.
  # A fixture that drifts from it proves nothing about the real machine.
  cat >"$git_home/.gitconfig-local" <<LOCAL
[user]
	name = Test Person
	email = personal@example.com
	signingkey = $git_home/.ssh/id_ed25519_github.pub
[commit]
	gpgsign = true

[includeIf "gitdir/i:~/Work/"]
	path = ~/.gitconfig-work
LOCAL
  printf '[user]\n\temail = work@example.com\n' >"$git_home/.gitconfig-work"

  # GIT_CONFIG_NOSYSTEM keeps Apple's system gitconfig out of every answer.
  # XDG_CONFIG_HOME is unset for the reason the bat block unsets it: .zshenv
  # exports it into whoever runs `mise run check`, and leaving it set points
  # git at the caller's real ~/.config/git instead of this temp one.
  git_probe() {
    # cd out of the repo first. The smoke test runs from $root, and a git that
    # starts there reads this repo's .git/config too, so one `git config --local
    # user.name` here would answer for the tracked file and pass.
    (unset XDG_CONFIG_HOME
     cd "$git_home"
     HOME=$git_home GIT_CONFIG_NOSYSTEM=1 git "$@")
  }

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
  git_probe -C "$git_home/Work/repo" init -q || fail "git: init failed in the temp work tree"
  git_probe -C "$git_home/Personal/repo" init -q || fail "git: init failed in the temp personal tree"
  email=$(git_probe -C "$git_home/Work/repo" config --get user.email || true)
  [ "$email" = "work@example.com" ] \
    || fail "git: the work profile did not match inside ~/Work (got ${email:-nothing})"
  email=$(git_probe -C "$git_home/Personal/repo" config --get user.email || true)
  [ "$email" = "personal@example.com" ] \
    || fail "git: the personal identity did not survive outside ~/Work (got ${email:-nothing})"

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

    # Two commits, so there is a real diff to render. The fixture local file
    # turns gpgsign on and names a key that does not exist, so it is off here.
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

  rm -rf "$git_home"
  # A warning, not a failure: a machine mid-migration is a legal state, and the
  # fresh Mac this repo targets has no ~/.gitconfig at all.
  if [ -e "$HOME/.gitconfig" ]; then
    printf 'warn ~/.gitconfig exists here, so git ignores ~/.config/git/config; move it aside\n'
  fi
  ok "git config"
else
  printf 'skip git config: git is not on PATH\n'
fi

# Both tracked YAML files, through one probe. Each names dotted paths and the
# value it expects, so a missing path and a changed value fail separately.
probe_yaml() {
  # A label, the file, and a JSON object of path to expected value.
  [ -f "$2" ] || fail "$1: $2 is missing"
  cfg_json=$(yq -p yaml -o json "$2") || fail "$2 does not parse"
  SRC=$2 CFG_JSON=$cfg_json WANT_JSON=$3 python3 - <<'PROBE' || fail "$1"
import sys, os, json

cfg = json.loads(os.environ["CFG_JSON"])
src = os.environ["SRC"]
errs = []
missing = object()

def resolve(path):
    node = cfg
    for key in path.split("."):
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

# The real parser, when a mise exists. This block went red on every Mac with
# mise on it until the three tap entries left [bootstrap.packages]; see the
# note there. It has no value as a pass/fail gate unless it can reach one.
if command -v mise >/dev/null 2>&1; then
  mise bootstrap --dry-run >/dev/null || fail "mise bootstrap --dry-run"
  ok "mise bootstrap --dry-run"
else
  printf 'skip mise bootstrap --dry-run: mise is not on PATH\n'
fi

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
  awk '
    /^[[:space:]]*\[/ {
      h = $0
      sub(/[[:space:]]*#.*$/, "", h); sub(/^[[:space:]]+/, "", h); sub(/[[:space:]]+$/, "", h)
      if (h == "[tools]") { intools = 1; next }
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
      if (n == 0) {
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
  # carries one binary and it is named yq.
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
lazydocker lazydocker
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
work_keys=$(tools_in config/mise/config.work.toml) || fail "tools: config/mise/config.work.toml"
all_keys="$tools_keys
$work_keys"

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
  # The overlay's tools exist only where the overlay loads. MISE_ENV is the
  # documented switch, and miserc.toml is what install.sh actually writes;
  # that file sets MISE_ENV for mise itself and is invisible as a variable
  # here, so both are consulted.
  overlay=no
  case "${MISE_ENV:-}" in *work*) overlay=yes ;; esac
  if grep -qs '^env *=.*"work"' "${XDG_CONFIG_HOME:-$HOME/.config}/mise/miserc.toml"; then
    overlay=yes
  fi
  check_keys=$tools_keys
  [ "$overlay" = no ] || check_keys=$all_keys

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
