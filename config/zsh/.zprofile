# Login shells. mise pours brew bottles itself and installs no brew program, so
# there is no `brew shellenv` to run and mise writes no /etc/paths.d file.
# Without this the formulae the manifest installs (bash, eza, the three zsh
# plugins) are not on PATH.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

# macOS /etc/zprofile runs path_helper before this file, and path_helper
# rebuilds PATH from /etc/paths, appending whatever .zshenv set behind
# /usr/bin. Without re-prepending, a mise-installed tool in ~/.local/bin loses
# to an older copy in /usr/bin, and a login shell disagrees with every other
# shell about which binary wins. `path` is -U, so the duplicates collapse.
path=("$DOTFILES/bin" "$HOME/.local/bin" $path)
