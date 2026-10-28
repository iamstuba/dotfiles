# Dotfiles

Configuration and setup for a personal Mac and the work Mac, each reproducible from a fresh install.

## Language

**Mac**:
Any Mac this repo bootstraps. Each is either a personal Mac or the work Mac. `~/.config/mise/miserc.toml` names its `personal` or `work` env and is the only place that answer lives. The installer's work question writes it once, and everything after reads it. Identity, secrets and paths that belong to one Mac or employer never enter tracked files.
_Avoid_: laptop, host, machine, personal machine

**Manifest**:
The two tracked mise config files that together declare what every Mac gets. The global file (`config/mise/config.toml`, symlinked) holds tools and settings; the repo-root `mise.toml` holds packages, the symlink map, macOS defaults and hooks. Both hold tasks, split by whether the task can reach the repo through `{{ config_root }}`: the global file is read from outside the clone, so tasks there cannot.
_Avoid_: Brewfile, package list

**Overlay**:
A pair of mise config files loaded only when `MISE_ENV` names them. Every Mac names exactly one, `work` or `personal`. Each overlay has one file beside each half of the manifest: `config/mise/config.<env>.toml` for tools, settings and tasks, and the repo-root `mise.<env>.toml` for packages, dotfiles and hooks, and each repo-root file links its own global one. mise cannot remove a tool, dotfile or task the manifest declares, so whatever one kind of Mac must not get lives in the other kind's overlay. The work overlay turns manifest packages off and adds the tools only work uses.
_Avoid_: profile, environment file, work manifest

**Trust**:
mise refuses to load a config file no human has marked trusted. Bootstrap trusts the manifest and the overlay; anything running against a throwaway HOME has to grant its own.
_Avoid_: allow, approve, whitelist

**Tap package**:
A Homebrew formula or cask that lives in a third-party tap rather than homebrew-core. mise cannot resolve one, so these stay out of the manifest's packages and brew installs them directly.
_Avoid_: brew fallback, source build, third-party formula

**Bootstrap**:
One run of the manifest that takes a fresh Mac to fully configured. Rerunnable.
_Avoid_: install, provision, setup

**Installer**:
The one-line `bash -c "$(curl ...)"` script that takes a fresh Mac through bootstrap. Two phases: attended, then unattended.
_Avoid_: setup script, curl-pipe-bash

**Attended phase**:
The first minutes of the installer, where a human says whether this is the work Mac unless miserc already does, types the password, logs into GitHub, answers identity questions and lets the SSH key into the keychain. On the work Mac they also log into GitLab and let its own key in.
_Avoid_: interactive part

**Unattended phase**:
The rest of the installer. Nothing asks; the human can leave.
_Avoid_: automatic part

**Hook**:
A shell command mise runs at a fixed point of bootstrap, with only system binaries on PATH. Three exist: `pre-packages`, `post-defaults`, `final`.
_Avoid_: script, step, phase

**Task**:
A mise task, run on demand or from bootstrap, with the manifest's tools on PATH. Anything that needs `bat`, `jq` or `herdr` is a task, never a hook.
_Avoid_: script, job, command

**Manual step**:
An action in the README that no tracked file can perform, done once after the restart.
_Avoid_: click, todo, post-install

**Local file**:
A machine-specific, untracked file read next to the tracked config when present. Holds identity, work-only settings and `MISE_ENV`.
_Avoid_: override, secrets file

**Profile**:
A directory tree paired with the git identity and signing key used inside it, in place of the Mac's default identity. Each profile is its own local file, included by path.
_Avoid_: work config, includeIf

**Workspace**:
An AeroSpace virtual desktop, addressed by a key and holding one or two windows.
_Avoid_: space, desktop, screen

**Bloat removal**:
The macOS defaults changes and removable Apple app deletions bootstrap applies. The app deletions run on a personal Mac only. Never disables SIP or launch services.
_Avoid_: debloat, hardening

**Input source**:
The macOS keyboard layout every Mac types with. Stock Finnish, picked in Setup Assistant. Left Option types characters and right Option is the terminal's Alt.
_Avoid_: keyboard layout, keymap

**Base**:
The upstream Neovim starting config copied into the repo once and owned from then on. Never pulled again.
_Avoid_: distro, distribution, framework

**Git TUI**:
The full-screen git client used for staging, branching and history. lazygit. Not where diffs get read for review.
_Avoid_: TUI, porcelain, git client

**Review TUI**:
The full-screen client for reading a diff or a pull request. tuicr. Owns no git state.
_Avoid_: TUI, diff viewer, code review tool

**Coding agent**:
An agent the repo installs and configures: Claude Code on every Mac, pi on a personal Mac only. herdr owns their panes on a personal Mac but is not one of them.
_Avoid_: assistant, AI, bot, LLM

**Shared instruction file**:
`home/.agents/AGENTS.md`, the one file every coding agent on a Mac reads as its global instructions, linked to a different path in each. Half the owner's own rules, half a vendored copy of someone else's writing rules.
_Avoid_: CLAUDE.md, rules file, system prompt

**Agent multiplexer**:
The terminal layer that owns the panes coding agents run in and reports whether each is working, idle or blocked. herdr, on a personal Mac only. Does not queue work or restart agents.
_Avoid_: orchestrator, harness, agent manager

**Bar**:
The strip at the top of every display that replaces the hidden macOS menu bar. Shows workspaces, agent state and machine readouts. SketchyBar.
_Avoid_: menu bar, status bar, top bar

**Theme**:
The one colour scheme and font pair every tracked config uses. Tokyo Night Night, dark only, Monaspace Neon. No switching.
_Avoid_: colorscheme, palette, theme pack

**Area**:
The unit implementation runs in, one at a time: the files owned by a single tool.
_Avoid_: feature, epic, milestone

**Rehearsal**:
`mise bootstrap --dry-run` on a Mac before its first real bootstrap. Prints hook bodies without running them, so everything the pre-packages hook installs and the post-defaults hooks go untried by the rehearsal itself.
_Avoid_: trial, test run

**Smoke test**:
`tests/smoke.sh`, what `mise run check` runs. One probe for each thing it covers: the manifest, every tracked config, and every script. Most scripts run in dry-run mode. The installer and setup-git run for real in a temp HOME, against stubs for the commands that would reach GitHub, GitLab or the keychain. Extended by each area, never split.
_Avoid_: CI, test suite

**Probe**:
One named section of the smoke test, passing or failing on its own line. Asks the tool it covers wherever it can, because a config file containing the right line proves only that someone wrote the line.
_Avoid_: block, check, assertion, case

**Launcher**:
The field on Cmd+Space that opens apps, pastes from clipboard history and answers sums. Vorssaint's Command Bar.
_Avoid_: Spotlight, Raycast, search bar

**Daily browser**:
LibreWolf, the browser on a personal Mac. Holds the personal session and everything that is not work. Its enterprise policies are tracked; the cookie exceptions that survive its shutdown clearing are not.
_Avoid_: main browser, default browser, Zen

**Work browser**:
Chrome, the only browser on the work Mac. Holds the work session and the work password manager.
_Avoid_: second browser, devtools browser, Chromium, Helium
