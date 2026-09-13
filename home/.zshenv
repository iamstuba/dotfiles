# Read by every zsh, interactive or not, login or not, so it holds only exports
# and PATH. Nothing here prints or assumes a tty. History and the interactive
# options live in .zshrc; MISE_ENV lives in ~/.config/mise/miserc.toml, which
# the installer writes and the manifest keeps out of tracked files.

export XDG_CONFIG_HOME="$HOME/.config"
# Moves .zshrc into config/zsh, and is what makes lazygit and glow read
# ~/.config on macOS instead of inventing their own paths.
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# ${(%):-%N} is the path of the file being sourced, which is the ~/.zshenv
# symlink. Resolving it and stepping up out of home/ finds the clone wherever
# it sits, so nothing here names ~/Projects.
export DOTFILES="$(dirname "$(dirname "$(readlink -f "${(%):-%N}")")")"

export EDITOR='nvim'
export GIT_EDITOR='nvim'

export RIPGREP_CONFIG_PATH="$XDG_CONFIG_HOME/ripgrep/config"
# Without this eza reads ~/Library/Application Support/eza on macOS and the
# tracked theme never loads.
export EZA_CONFIG_DIR="$XDG_CONFIG_HOME/eza"
# Named here rather than in a ~/.config/bat/config, because the symlink map
# tracks bat's theme file and no bat config file. delta reads the same name.
export BAT_THEME='tokyonight_night'

# -U collapses duplicates, so re-sourcing this file cannot grow PATH.
typeset -aU path
# ~/.local/bin is on before anything calls mise, which installs itself there.
path=("$DOTFILES/bin" "$HOME/.local/bin" $path)
