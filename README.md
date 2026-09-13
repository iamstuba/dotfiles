# dotfiles

Configuration and setup for my Macs, reproducible from a fresh install. Heavily
inspired by [nicknisi/dotfiles](https://github.com/nicknisi/dotfiles).

## Bootstrap

1. In Setup Assistant: sign in to the Apple Account, decline Apple Intelligence, choose the US keyboard and nothing else, skip Siri.
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
- The native menu bar is hidden. Hover the top edge for its icons and the Wi-Fi name.

Vorssaint

- Install the Command Bar, Clipboard history, Smooth scrolling, Scroll direction and Mouse modules. Leave the rest uninstalled.
- Record Cmd+Space for the Command Bar. Spotlight's hotkey is already off.
- Name the folders the Command Bar searches.
- Set scroll speed and direction, and turn mouse acceleration off.

Mail

- Proton Mail Bridge: log in, turn on start at login.
- Thunderbird: add the Proton account from Bridge's settings, accept the certificate exceptions; add Gmail directly.
- Thunderbird quiet: `user_pref("mail.biff.show_alert", false);` in the profile's `user.js`. After the first alert, turn off "Badge app icon" for Thunderbird in System Settings > Notifications.

Slack

- Preferences > Appearance > Custom theme, paste `#1a1b26,#16161e,#bb9af7,#283457`.

Grammarly Desktop

- Open it, sign in, allow Accessibility. Add Ghostty to Settings > Block list.

Handy

- Open it and wait half a minute. If it dies on launch, that is issue 1643 on macOS 26: drop the cask.
- Allow Microphone and Accessibility. Download the Parakeet V3 model, set language to auto.
- Add odd identifiers as custom words. Hold Option+Space and dictate one prompt into a Claude Code pane.

Extra GitHub accounts

- Register `~/.ssh/id_ed25519_github.pub` once per account, as an authentication key and as a signing key.

## Keeping it current

```sh
mise run update:all
```

Runs, in order: `update:dotfiles` (fast-forward this repo when on main), `update:tools`
(mise, every tool, pi extensions), `update:apps` (formulae and casks), `update:plugins`
(Neovim). Run `mise upgrade --dry-run`, `mise bootstrap packages upgrade --dry-run`
and `bin/brew-tap-packages upgrade --dry-run` first on a new machine. The third
covers what the second cannot see; see "Rerunning" below.

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
- `config/mise/config.work.toml`: work-only tools, loaded when `MISE_ENV` includes `work`.
- `config/`: mirrors `~/.config`. `home/`: top-level dotfiles. `bin/`: scripts on PATH.
- `install.sh`, `tests/smoke.sh`, `assets/`.

Planning lives in a private repo cloned at `.scratch/`, ignored here. See
`docs/agents/` for how agents work in this repo and `CONTEXT.md` for the
vocabulary.
