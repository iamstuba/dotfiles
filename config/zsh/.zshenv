# A zsh started from another zsh inherits ZDOTDIR, so it reads this file
# instead of ~/.zshenv. Without it, that shell loses `typeset -U path`, and
# .zprofile adds its PATH entries a second time.
[[ -r $HOME/.zshenv ]] && source "$HOME/.zshenv"
