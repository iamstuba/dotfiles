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
mise=$HOME/.local/bin/mise
repo=https://github.com/iamstuba/dotfiles.git
scratch=git@github.com:iamstuba/dotfiles-scratch.git
key=$HOME/.ssh/id_ed25519_github
scopes=admin:public_key,admin:ssh_signing_key
clt=/Library/Developer/CommandLineTools

bold=$(printf '\033[1m')
reset=$(printf '\033[0m')
if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then bold= reset=; fi
say() { printf '%s==> %s%s\n' "$bold" "$*" "$reset"; }
run() { if [ "${DRY_RUN:-}" ]; then printf '+ %s\n' "$*"; else "$@"; fi; }
gh() { "$mise" x github-cli -- gh "$@"; }
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

# One password covers the CLT, /opt/homebrew and the GarageBand deletion.
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
    printf 'Git profiles as dir=email, comma separated, or empty: '
    read -r GIT_PROFILES
  fi
fi
export GIT_NAME GIT_EMAIL GIT_PROFILES

# MISE_ENV lives in mise's early-init file, never in a shell rc.
if [ -z "${DOTFILES_WORK:-}" ]; then
  [ -t 0 ] || die "DOTFILES_WORK is unset and there is no terminal to ask"
  printf 'Is this a work Mac (loads the work overlay)? [y/N] '
  read -r answer
  case "$answer" in y | Y | yes) DOTFILES_WORK=1 ;; *) DOTFILES_WORK=0 ;; esac
fi
miserc=$HOME/.config/mise/miserc.toml
if [ "$DOTFILES_WORK" = 1 ]; then
  if grep -qs '^env *=.*"work"' "$miserc"; then
    :
  elif grep -qs '^env *=' "$miserc"; then
    # A second env key would be invalid TOML and stop mise loading config.
    echo "install: $miserc already sets env; add \"work\" to it by hand"
  elif [ "${DRY_RUN:-}" ]; then
    echo "+ write env = [\"work\"] to $miserc"
  else
    mkdir -p "$HOME/.config/mise"
    printf 'env = ["work"]\n' >>"$miserc"
  fi
fi

# Here so the passphrase prompt is early; setup-git only generates when missing.
if [ ! -f "$key" ]; then
  run mkdir -p "$HOME/.ssh"
  run ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$key"
  run ssh-add --apple-use-keychain "$key"
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
for f in mise.toml config/mise/config.toml config/mise/config.work.toml; do
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
