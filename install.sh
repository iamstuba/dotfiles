#!/bin/sh
# Installer for github.com/iamstuba/dotfiles. On a fresh Mac:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/iamstuba/dotfiles/main/install.sh)"
# From the clone: sh install.sh. A few attended minutes, then unattended until
# "Restart now". Rerunnable: what exists is skipped, nothing is pulled.
# --dry-run prints every mutating command.
# Environment: DOTFILES, DOTFILES_WORK, GIT_NAME, GIT_EMAIL, GIT_PROFILES,
# DOTFILES_BREW_FALLBACK (read by the pre-packages hook).
set -eu

case "${1:-}" in --dry-run) DRY_RUN=1 ;; esac
DOTFILES=${DOTFILES:-$HOME/Projects/iamstuba/dotfiles}
mise=$HOME/.local/bin/mise
repo=https://github.com/iamstuba/dotfiles.git
scratch=https://github.com/iamstuba/dotfiles-scratch.git
key=$HOME/.ssh/id_ed25519_github
clt=/Library/Developer/CommandLineTools

if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then bold=; reset=; else bold=$(printf '\033[1m'); reset=$(printf '\033[0m'); fi
say() { printf '%s==> %s%s\n' "$bold" "$*" "$reset"; }
die() { echo "install: $*" >&2; exit 1; }
run() { if [ "${DRY_RUN:-}" ]; then echo "+ $*"; else "$@"; fi; }
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
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# Never reinstalled: mise.run would replace a self-updated binary with its pinned one.
if [ ! -x "$mise" ]; then
  if [ "${DRY_RUN:-}" ]; then echo "+ curl -fsSL https://mise.run | sh"; else curl -fsSL https://mise.run | sh; fi
fi

# Before the clone and the CLT exist. -p ssh keeps gh out of git's credential
# config; key upload is setup-git's job.
if ! gh auth status >/dev/null 2>&1; then
  run gh auth login -w -p ssh --skip-ssh-key -s admin:public_key,admin:ssh_signing_key
fi

ask GIT_NAME "Git name"
ask GIT_EMAIL "Git email"
if [ -z "${GIT_PROFILES+set}" ]; then
  [ -t 0 ] || die "GIT_PROFILES is unset and there is no terminal to ask"
  printf 'Git profiles as dir=email, comma separated, or empty: '
  read -r GIT_PROFILES
fi
export GIT_NAME GIT_EMAIL GIT_PROFILES

# MISE_ENV lives in mise's early-init file, never in a shell rc.
if [ -z "${DOTFILES_WORK:-}" ]; then
  [ -t 0 ] || die "DOTFILES_WORK is unset and there is no terminal to ask"
  printf 'Is this a work machine? [y/N] '
  read -r answer
  case "$answer" in y | Y | yes) DOTFILES_WORK=1 ;; *) DOTFILES_WORK=0 ;; esac
fi
miserc=$HOME/.config/mise/miserc.toml
if [ "$DOTFILES_WORK" = 1 ] && ! grep -qs '"work"' "$miserc"; then
  if [ "${DRY_RUN:-}" ]; then
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
    label=$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | sort -V | tail -n 1 || true)
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

# Owner-only, so a failure is a note. GIT_TERMINAL_PROMPT=0 keeps git from asking for a password.
if [ ! -d "$DOTFILES/.scratch/.git" ]; then
  if ! run env GIT_TERMINAL_PROMPT=0 "$mise" x github-cli -- git clone "$scratch" "$DOTFILES/.scratch"; then
    echo "install: could not clone dotfiles-scratch (owner-only), continuing"
  fi
fi

run "$mise" -C "$DOTFILES" run setup-git

say "Done. Restart now, then follow \"After the restart\" in the README."
