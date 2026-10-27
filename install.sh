#!/bin/sh
# Installer for github.com/iamstuba/dotfiles. On a fresh Mac:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/iamstuba/dotfiles/main/install.sh)"
# From the clone: sh install.sh. A few attended minutes, then unattended until
# "Restart now". Rerunnable: what exists is skipped, nothing is pulled.
# --dry-run prints every mutating command.
# Environment: DOTFILES, DOTFILES_WORK, GIT_NAME, GIT_EMAIL, GIT_PROFILES.
set -eu

die() { echo "install: $*" >&2; exit 1; }
case "${1:-}" in "") ;; --dry-run) DRY_RUN=1 ;; *) die "unknown argument $1" ;; esac
DOTFILES=${DOTFILES:-$HOME/Projects/iamstuba/dotfiles}


# Names the Claude Code mise manages, so nobody installs a second copy to
# debug with. mise x fetches it if bootstrap has not. Before the clone exists
# there is nothing to cd into.
on_exit() {
  status=$?
  if [ "$status" != 0 ]; then
    cd_clone=
    [ -d "$DOTFILES/.git" ] && cd_clone="cd '$DOTFILES' && "
    echo "install: failed. To debug, open a second tab and run ${cd_clone}~/.local/bin/mise x claude -- claude" >&2
  fi
  exit "$status"
}
trap on_exit EXIT

mise=$HOME/.local/bin/mise
repo=https://github.com/iamstuba/dotfiles.git
scratch=git@github.com:iamstuba/dotfiles-scratch.git
key=$HOME/.ssh/id_ed25519_github
gitlab_key=$HOME/.ssh/id_ed25519_gitlab
scopes=admin:public_key,admin:ssh_signing_key
clt=/Library/Developer/CommandLineTools

bold=$(printf '\033[1m')
reset=$(printf '\033[0m')
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then bold= reset=; fi
say() { printf '%s==> %s%s\n' "$bold" "$*" "$reset"; }
run() { if [ "${DRY_RUN:-}" ]; then printf '+ %s\n' "$*"; else "$@"; fi; }
gh() { "$mise" x github-cli -- gh "$@"; }
# The overlay's [env] never reaches the installer, so glab's is set here, the
# same three as setup-git sets.
glab() {
  GLAB_CONFIG_DIR=$HOME/.config/glab-cli GLAB_SEND_TELEMETRY=0 GITLAB_HOST=gitlab.com \
    "$mise" x gitlab:gitlab-org/cli -- glab "$@"
}
ask() {
  eval "val=\${$1:-}"
  if [ -z "$val" ]; then
    [ -t 0 ] || die "$1 is unset and there is no terminal to ask"
    printf '%s: ' "$2"
    read -r val
  fi
  eval "$1=\$val"
}

say "Attended phase: a few prompts, then you can leave."

# miserc is the one answer to which Mac this is: mise loads the overlay it
# names, setup-git reads it, and so do the GitLab steps below. The work
# question, or DOTFILES_WORK, only seeds it on a Mac whose miserc sets no env.
# Settled first, so a contradiction stops before the password prompt.
case "${DOTFILES_WORK:-}" in "" | 0 | 1) ;; *) die "DOTFILES_WORK must be 1 or 0, not $DOTFILES_WORK" ;; esac
miserc=$HOME/.config/mise/miserc.toml
if grep -qs '^env *=.*"work"' "$miserc" && grep -qs '^env *=.*"personal"' "$miserc"; then
  die "$miserc names both work and personal; keep one"
elif grep -qs '^env *=.*"work"' "$miserc"; then
  machine_env=work
elif grep -qs '^env *=.*"personal"' "$miserc"; then
  machine_env=personal
elif grep -qs '^env *=' "$miserc"; then
  die "$miserc sets env to neither work nor personal; fix it by hand"
else
  machine_env=
fi
if [ -n "$machine_env" ]; then
  case "${DOTFILES_WORK:-}:$machine_env" in
    1:personal | 0:work) die "DOTFILES_WORK=$DOTFILES_WORK, but $miserc says $machine_env; fix one of them" ;;
  esac
else
  if [ -z "${DOTFILES_WORK:-}" ]; then
    [ -t 0 ] || die "DOTFILES_WORK is unset and there is no terminal to ask"
    printf 'Is this a work Mac (loads the work overlay)? [y/N] '
    read -r answer
    case "$answer" in y | Y | yes) DOTFILES_WORK=1 ;; *) DOTFILES_WORK=0 ;; esac
  fi
  # Every Mac gets exactly one env: mise.personal.toml carries what a work Mac
  # must not get, since mise cannot switch off an entry mise.toml declares.
  if [ "$DOTFILES_WORK" = 1 ]; then machine_env=work; else machine_env=personal; fi
  if [ "${DRY_RUN:-}" ]; then
    echo "+ write env = [\"$machine_env\"] to $miserc"
  else
    mkdir -p "$HOME/.config/mise"
    printf 'env = ["%s"]\n' "$machine_env" >>"$miserc"
  fi
fi

# One password covers the CLT, /opt/homebrew and, on a personal Mac, the GarageBand loops.
run sudo -v
if [ -z "${DRY_RUN:-}" ]; then
  while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null || true; sleep 60; done &
fi

# Never reinstalled: mise.run would replace a self-updated binary with its pinned one.
if [ ! -x "$mise" ]; then
  if [ "${DRY_RUN:-}" ]; then echo "+ curl -fsSL https://mise.run | sh"; else curl -fsSL https://mise.run | sh; fi
fi

# Before the clone and the CLT exist. -p ssh keeps gh out of git's credential
# config; key upload is setup-git's job.
if [ "${DRY_RUN:-}" ]; then
  echo "+ gh auth status || gh auth login -w -p ssh --skip-ssh-key -s $scopes"
elif ! gh auth status >/dev/null 2>&1; then
  gh auth login -w -p ssh --skip-ssh-key -s "$scopes"
fi

ask GIT_NAME "Git name"
ask GIT_EMAIL "Git email"
# Profiles are optional, so no terminal means none.
if [ -z "${GIT_PROFILES+set}" ]; then
  GIT_PROFILES=
  if [ -t 0 ]; then
    printf 'Git profiles as dir=email[=github|gitlab], comma separated, or empty: '
    read -r GIT_PROFILES
  fi
fi
export GIT_NAME GIT_EMAIL GIT_PROFILES

# Work only, by miserc, so a personal Mac never logs into GitLab. A
# login on a host with credentials always asks to re-authenticate, so check first.
if [ "$machine_env" = work ]; then
  if [ "${DRY_RUN:-}" ]; then
    echo "+ glab config get user --host gitlab.com || glab auth login --hostname gitlab.com --web -g ssh"
  elif [ -z "$(glab config get user --host gitlab.com 2>/dev/null || true)" ]; then
    glab auth login --hostname gitlab.com --web -g ssh
  fi
fi

# Here so the passphrase prompts are early; setup-git only generates when missing.
make_key() {
  run mkdir -p "$HOME/.ssh"
  run ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$1"
  run ssh-add --apple-use-keychain "$1"
}
[ -f "$key" ] || make_key "$key"
if [ "$machine_env" = work ] && [ ! -f "$gitlab_key" ]; then
  make_key "$gitlab_key"
fi

say "Unattended from here. Come back later, approve the dialogs on screen, then restart."

# The shim fools `command -v git`, so test the real file. Homebrew's
# placeholder trick makes softwareupdate list the CLT and install it blocking.
if [ ! -e "$clt/usr/bin/git" ]; then
  say "Installing the Xcode Command Line Tools"
  placeholder=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  run touch "$placeholder"
  if [ "${DRY_RUN:-}" ]; then
    label="<label from softwareupdate -l>"
  else
    label=$(softwareupdate -l 2>/dev/null \
      | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | sort -V | tail -n 1 || true)
  fi
  if [ -n "$label" ]; then
    run sudo softwareupdate -i "$label"
    run sudo xcode-select --switch "$clt"
  elif [ -t 0 ]; then
    run xcode-select --install
    printf 'Press return when the Command Line Tools have finished installing. '
    read -r _
  else
    die "no Command Line Tools label found and no terminal to wait on; install them and rerun"
  fi
  run rm -f "$placeholder"
fi

# HTTPS because no key is registered yet; setup-git flips it to SSH.
if [ ! -d "$DOTFILES/.git" ]; then
  run git clone "$repo" "$DOTFILES"
fi

# Config with hooks and dotfiles needs trust. --yes because mise marks bootstrap destructive.
for f in mise.toml mise.work.toml mise.personal.toml config/mise/config.toml config/mise/config.work.toml config/mise/config.personal.toml; do
  run "$mise" trust "$DOTFILES/$f"
done
run "$mise" -C "$DOTFILES" bootstrap --yes

run "$mise" -C "$DOTFILES" run setup-git

# After setup-git: the key is registered and GitHub's host keys are trusted.
# Owner-only, so a failure is a note. BatchMode stops ssh from asking anything.
if [ ! -d "$DOTFILES/.scratch/.git" ]; then
  if ! run env GIT_SSH_COMMAND="ssh -o BatchMode=yes" git clone "$scratch" "$DOTFILES/.scratch"; then
    echo "install: could not clone dotfiles-scratch (owner-only), continuing"
  fi
fi

say "Done. Restart now, then follow \"After the restart\" in the README."
