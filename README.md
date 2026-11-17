# dotfiles

Configuration and setup for my Macs, reproducible from a fresh install. Heavily
inspired by [nicknisi/dotfiles](https://github.com/nicknisi/dotfiles).

## Bootstrap

1. In Setup Assistant: sign in to the Apple Account, decline Apple Intelligence, choose the Finnish keyboard and nothing else, skip Siri.
2. Open Terminal and run the line below. Stay for the prompts, then leave. They take about two minutes, plus Homebrew's own install on a Mac without Homebrew, because the GitHub login needs brew's gh.

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/iamstuba/dotfiles/main/install.sh)"
   ```

3. Come back and approve the AeroSpace, Karabiner-Elements and Vorssaint dialogs.
4. Restart.

## After the restart

System Settings

- Menu Bar: hide the Siri icon.
- Focus: build one mode that allows only Slack notifications.
- Desktop & Dock: leave "Displays have separate Spaces" on. SketchyBar needs it.
- Never sign in to Game Center.
- Keyboard: in Keyboard Shortcuts > Input Sources, untick both shortcuts. The first takes Ctrl+Space, which accepts a zsh suggestion.
- The native menu bar is hidden under the bar. For its icons and the Wi-Fi name, press Option+Shift+Ö, then B, and hover the top edge. The same two keys bring the bar back.

Vorssaint

- In the first-run picker, skip the ready setups and tick only these features: Command Bar, Clipboard, Clean URL, Cut & paste, Quit & close protection, Smooth scrolling, Invert mouse scrolling, Disable mouse acceleration, Music app blocker, Audio device priority. Leave the rest uninstalled: AeroSpace owns windows, Karabiner owns keys, Homebrew and mise own installs (so not Homebrew, App updates or Uninstaller), and bootstrap already sets the wallpaper and keeps Spaces in a fixed order.

AeroSpace

- To pause tiling for screen sharing, press Option+Shift+Ö then Q. Run `aerospace enable on` to resume.

Mail, on a personal Mac only

- Proton Mail Bridge: log in, turn on start at login.
- Thunderbird: add the Proton account from Bridge's settings, accept the certificate exceptions; add Gmail directly.
- Thunderbird quiet: `user_pref("mail.biff.show_alert", false);` in the profile's `user.js`. After the first alert, turn off "Badge app icon" for Thunderbird in System Settings > Notifications.

LibreWolf, on a personal Mac only

- Set it as the default browser in System Settings > Desktop & Dock. It never asks, and no script can set it without a confirmation dialog.
- Sign in to Proton Pass. Proton Pass and Refined GitHub install themselves on first launch.
- Cookies and site storage clear on every quit. History, downloads and form data stay. Allow each site you want to stay logged in to as you go. The allow list lives in the profile and is not tracked.
- Sites show UTC time and the window opens at 1600x900. That is fingerprinting resistance, on purpose.
- Netflix and Spotify do not play. DRM is off on purpose.

GitLab, on the work Mac only

- The first `git clone` from gitlab.com asks to confirm its host key. Compare it with the [SSH fingerprints GitLab publishes for gitlab.com](https://docs.gitlab.com/user/gitlab_com/#ssh-host-keys-fingerprints) before you answer yes.
- Run `glab auth configure-docker` once, so `docker` pulls from GitLab's container registry through glab. glab writes its credential helper to `~/.local/bin`.

Containers, on the work Mac only

- Run `colima start` before you need Docker and `colima stop` after. Nothing starts the VM at login, and a running VM holds up to 8 GiB of RAM.

Slack

- Preferences > Appearance > Custom theme, paste `#1a1b26,#16161e,#bb9af7,#283457`.

Extra GitHub accounts

- Register `~/.ssh/id_ed25519_github.pub` once per account, as an authentication key and as a signing key.

## Keeping it current

```sh
mise run update:all
```

Runs, in order: `update:dotfiles` (fast-forward this repo when on main), `update:tools`
(mise and every tool mise installs, a list of outdated herdr integrations, and on a
personal Mac pi's extensions), `update:apps` (every Homebrew package), `update:plugins` (Neovim). Run `mise upgrade --dry-run`
and `bin/brew-packages upgrade --dry-run` first on a new machine.

A tool set to `latest` stays on the version it first installed. Bootstrap and
`mise install` keep that version, even one a repo's pin installed, and only
`update:tools` moves it.

On the work Mac, `update:tools` ends with `ca:refresh`, which re-exports the
System keychain's CAs and imports them into every mise JDK, so
`mise run ca:refresh` alone is enough after a CA rotation.

The Colima VM needs `colima restart` when `ca:refresh` prints it as the next
step. A change to the tracked Colima template reaches an existing VM only
after `colima delete` and a fresh `colima start`.

On a personal Mac, LibreWolf quits during `update:apps` and reopens after it.
The first run asks to let the terminal control LibreWolf; allow it.

What no task can do:

- Karabiner-Elements, Ghostty and Vorssaint update through their own updaters. `update:apps` skips them because it doesn't pass `--greedy`.
- AeroSpace is replaced while running and may lose its Accessibility grant. Re-grant and relaunch after an update.

## Rerunning

`mise bootstrap` reapplies everything and skips what is in place. If Apple
Account sign-in was skipped in Setup Assistant, sign in and rerun it so the
Apple Intelligence key gets written.

Every Homebrew package this repo installs is in a Brewfile: `Brewfile` on
every Mac, plus `Brewfile.work` or `Brewfile.personal`. `bin/brew-packages` installs them from
the pre-packages hook and upgrades them from `update:apps`, through Workbrew's
brew where it exists and Homebrew's otherwise. A failed install prints a
warning, and the rest of bootstrap still runs. SketchyBar and Borders build
from source, which is the slow part of a fresh Mac.

On a Mac set up by hand, move `~/.gitconfig` aside first. Git reads
`~/.config/git/config`, where this repo's git config is linked, only while that
file does not exist, and `mise run check` warns when it finds one.

`mise run check` parses the manifest and runs every script, dry or, for the installer and setup-git, for real in a temp HOME against stub forge CLIs.

## Layout

- `mise.toml`: symlink map, macOS defaults, hooks, repo-bound tasks.
- `Brewfile`: every Homebrew package for every Mac. `Brewfile.work` and `Brewfile.personal` add the packages only that kind of Mac gets. `bin/brew-packages` installs and upgrades them.
- `config/mise/config.toml`: tools, settings, update tasks. Symlinked to `~/.config/mise/`.
- `config/mise/config.work.toml`: loaded when `MISE_ENV` includes `work`. It holds java and rust, the work env and settings, the JDK CA postinstall and `ca:refresh`. glab, the container tools, kubectl, k6, protoc and vault are in `Brewfile.work`.
- `config/mise/config.personal.toml`: pi and its tasks, loaded when `MISE_ENV` includes `personal`. herdr runs on both Macs, so its setup task is in `config/mise/config.toml`.
- `mise.work.toml`: the work-only links such as the Colima template, the task that merges the work Claude Code settings, and `setup-docker`, which bootstrap runs to link brew's compose and buildx into `~/.docker/cli-plugins`. `mise.personal.toml`: the dotfiles, pi's among them, the bundled app removal and the LibreWolf policies a work Mac must not get. Each links its own global overlay. The installer sets `MISE_ENV` to exactly one of `work` and `personal`.
- `config/`: mirrors `~/.config`. `home/`: mirrors `$HOME` for everything outside `~/.config`. `bin/`: scripts on PATH.
- `install.sh`, `tests/smoke.sh`, `assets/`.

Planning lives in a private repo cloned at `.scratch/`, ignored here. See
`docs/agents/` for how agents work in this repo and `CONTEXT.md` for the
vocabulary.
