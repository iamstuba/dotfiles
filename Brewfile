# Homebrew packages for every Mac. bin/brew-packages installs this file, then
# Brewfile.<env> for the env that MISE_ENV names.

# brew taps these on its own for the qualified names below. The lines name
# each tap anyway, so every third-party source is listed here.
tap "FelixKratz/formulae"
tap "nikitabobko/tap"

brew "bash"                             # bar plugins need bash 4+
brew "eza"                              # aqua entry is Linux-only
brew "btop"                             # aqua entry is Linux-only
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "fzf-tab"

brew "pnpm"
brew "fzf"
brew "fd"
brew "ripgrep"
brew "zoxide"
brew "bat"
brew "jq"
brew "yq"
brew "yazi"
brew "starship"
brew "glow"
brew "shellcheck"
brew "tuicr"
brew "git-delta"
brew "lazygit"
brew "gh"                               # install.sh installs it first, for the GitHub login
brew "herdr"

# Neovim and its language servers. marksman stays on mise. The npm servers
# pull in Homebrew's node, which mise's node stays ahead of on PATH.
# TypeScript, Oxlint and oxfmt are not here: each repo pins its own, and a
# global one on PATH runs instead wherever the command is typed bare.
brew "neovim"
brew "stylua"
brew "lua-language-server"
brew "vscode-langservers-extracted"
brew "yaml-language-server"
brew "bash-language-server"

# Source builds, no bottles, so these two are the slow part of a fresh Mac.
brew "FelixKratz/formulae/sketchybar"
brew "FelixKratz/formulae/borders"

cask "nikitabobko/tap/aerospace"
cask "ghostty"
cask "karabiner-elements"
cask "vorssaint"
cask "font-monaspace"
cask "font-symbols-only-nerd-font"
cask "font-sketchybar-app-font"
cask "claude-code@latest"                # the channel mise's claude tracked
