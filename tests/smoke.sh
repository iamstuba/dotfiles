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

# Every tracked TOML the shell area added, parsed rather than diffed.
for path in ("config/starship.toml", "config/yazi/theme.toml", "config/tuicr/config.toml"):
    p = pathlib.Path(path)
    if not p.exists():
        continue
    try:
        cfg = load(path)
    except tomllib.TOMLDecodeError as exc:
        errs.append(f"{path} does not parse: {exc}")
        continue
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

  # ZDOTDIR points into tracked space, so a shell that writes under it dirties
  # the working tree. Compared before against after rather than required
  # empty, so the check still means something with work in progress.
  before=$(git -C "$root" status --porcelain 2>/dev/null || true)

  # ZDOTDIR is unset for the probe. A shell inherits it from whoever runs
  # `mise run check`, and zsh reads $ZDOTDIR/.zshenv in preference to
  # $HOME/.zshenv, so leaving it set tests the caller's install, not this one.
  # The output is cut into labelled sections, so an alias cannot satisfy an
  # assertion meant for a key binding.
  out=$(unset ZDOTDIR; HOME=$zsh_home zsh -i -c '
    echo "### env";       printenv
    echo "### histfile";  echo "HISTFILE=$HISTFILE"
    # Physical, because ZDOTDIR reaches the repo through a symlink and the
    # literal path looks like it is under $HOME either way.
    echo "HISTDIR=$(cd ${HISTFILE:h} && pwd -P)"
    echo "### path";      print -l $path
    echo "### setopt";    setopt
    echo "### bindkey";   bindkey
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
  want bindkey '^"\^@" autosuggest-accept$' "Ctrl-Space is not bound"
  want bindkey '^"\^\[\[1;5C" forward-word$' "Ctrl-right is not bound"
  want bindkey '^"\^\[\[1;5D" backward-word$' "Ctrl-left is not bound"
  want delkey 'delete-char' "the delete key is not bound"

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
  [ -f "$root/config/eza/theme.yml" ] || fail "shell: config/eza/theme.yml is missing"
  if python3 -c 'import yaml' 2>/dev/null; then
    python3 -c 'import yaml,sys; yaml.safe_load(open("config/eza/theme.yml"))' \
      || fail "config/eza/theme.yml does not parse"
  else
    printf 'skip eza theme parse: python3 has no yaml module\n'
  fi
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

# The real parser, when a mise exists. The rehearsal is where this runs.
if command -v mise >/dev/null 2>&1; then
  mise bootstrap --dry-run >/dev/null || fail "mise bootstrap --dry-run"
  ok "mise bootstrap --dry-run"
else
  printf 'skip mise bootstrap --dry-run: mise is not on PATH\n'
fi
