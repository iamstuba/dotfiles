# Login shells. Homebrew's brew, or Workbrew's where it exists, installs the
# formulae the Brewfiles list, such as bash, eza and the three zsh plugins.
# Nothing else puts /opt/homebrew/bin ahead of /usr/local/bin and /usr/bin, so
# without this line they are missing or lose to older copies.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
# Under Workbrew, Homebrew's own brew refuses to run, so Workbrew's brew must
# come first. Its directory holds only brew, so it shadows no other command.
# This uses a literal path because `brew shellenv` adds 34 to 45 ms to every
# login shell.
[[ -x /opt/workbrew/bin/brew ]] && path=(/opt/workbrew/bin $path)

# macOS /etc/zprofile runs path_helper before this file, and path_helper
# rebuilds PATH from /etc/paths, appending whatever .zshenv set behind
# /usr/bin. Without re-prepending, a mise-installed tool in ~/.local/bin loses
# to an older copy in /usr/bin, and a login shell disagrees with every other
# shell about which binary wins. `path` is -U, so the duplicates collapse.
path=("$DOTFILES/bin" "$HOME/.local/bin" $path)
