# dotfiles

Configuration and setup for my Macs, reproducible from a fresh install. Heavily
inspired by [nicknisi/dotfiles](https://github.com/nicknisi/dotfiles).

## Bootstrap

1. In Setup Assistant: sign in to the Apple Account, decline Apple Intelligence, choose the Finnish keyboard and nothing else, skip Siri.
2. Open Terminal and run the line below. Stay for the prompts, about two minutes, then leave.

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
- The native menu bar is hidden. Hover the top edge for its icons and the Wi-Fi name.

Vorssaint

- In the first-run picker, skip the ready setups and tick only these features: Command Bar, Clipboard, Clean URL, Cut & paste, Quit & close protection, Smooth scrolling, Invert mouse scrolling, Disable mouse acceleration, Music app blocker, Mute microphone, Audio device priority. Leave the rest uninstalled: AeroSpace owns windows, Karabiner owns keys, mise owns installs and updates (so not Homebrew, App updates or Uninstaller), and bootstrap already sets the wallpaper and keeps Spaces in a fixed order.
- Record Cmd+Space for the Command Bar. Spotlight's hotkey is already off.
- Name the folders the Command Bar searches.
- Set the scroll speed.

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

Slack

- Preferences > Appearance > Custom theme, paste `#1a1b26,#16161e,#bb9af7,#283457`.

Extra GitHub accounts

- Register `~/.ssh/id_ed25519_github.pub` once per account, as an authentication key and as a signing key.

## Keeping it current

```sh
mise run update:all
```

Runs, in order: `update:dotfiles` (fast-forward this repo when on main), `update:tools`
(mise, every tool, pi extensions on a personal Mac), `update:apps` (formulae and
casks), `update:plugins` (Neovim). Run `mise upgrade --dry-run`, `mise bootstrap packages upgrade --dry-run`
and `bin/brew-tap-packages upgrade --dry-run` first on a new machine. The third
covers what the second cannot see; see "Rerunning" below.

On a personal Mac, LibreWolf quits during `update:apps` and reopens after it.
The first run asks to let the terminal control LibreWolf; allow it.

What no task can do:

- Karabiner-Elements updates itself. mise never touches it.
- AeroSpace is replaced while running and may lose its Accessibility grant. Re-grant and relaunch after an update.
- Ghostty updates only through its own "check for updates".

## Rerunning

`mise bootstrap` reapplies everything and skips what is in place. If Apple
Account sign-in was skipped in Setup Assistant, sign in and rerun it so the
Apple Intelligence key gets written.

SketchyBar, Borders and AeroSpace come from Homebrew, not from the packages
phase. They live in third-party taps that publish no API metadata, and mise's
fallback for that wants Ruby 3 or newer where macOS ships 2.6, so it cannot
resolve them at all. `bin/brew-tap-packages` names them and does the brew work;
the pre-packages hook calls it to install and `update:apps` to upgrade.
SketchyBar and Borders build from source, which is the slow part of a fresh
Mac.

On a Mac set up by hand, move `~/.gitconfig` aside first. Git reads
`~/.config/git/config`, where this repo's git config is linked, only while that
file does not exist, and `mise run check` warns when it finds one.

`mise run check` parses the manifest and runs every script dry.

## Layout

- `mise.toml`: packages, symlink map, macOS defaults, hooks, repo-bound tasks.
- `config/mise/config.toml`: tools, settings, update tasks. Symlinked to `~/.config/mise/`.
- `config/mise/config.work.toml`: work-only tools and packages, none today, loaded when `MISE_ENV` includes `work`.
- `config/mise/config.personal.toml`: pi and its tasks, loaded when `MISE_ENV` includes `personal`.
- `mise.work.toml`: packages turned off at work. `mise.personal.toml`: the dotfiles, pi's among them, the bundled app removal and the LibreWolf policies a work Mac must not get. Each links its own global overlay. The installer sets `MISE_ENV` to exactly one of `work` and `personal`.
- `config/`: mirrors `~/.config`. `home/`: top-level dotfiles. `bin/`: scripts on PATH.
- `install.sh`, `tests/smoke.sh`, `assets/`.

Planning lives in a private repo cloned at `.scratch/`, ignored here. See
`docs/agents/` for how agents work in this repo and `CONTEXT.md` for the
vocabulary.
