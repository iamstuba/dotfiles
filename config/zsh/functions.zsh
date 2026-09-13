# Sourced by .zshrc after compinit, which is what compdef needs.

# Two characters to reach either tree, with <TAB> completing against that
# directory rather than the cwd.
c() { cd "$HOME/Projects/$1" }
_c() { _files -W "$HOME/Projects" -/ }

h() { cd "$HOME/$1" }
_h() { _files -W "$HOME" -/ }

# compdef only exists once compinit has run, and this file is also readable on
# its own.
if (( $+functions[compdef] )); then
  compdef _c c
  compdef _h h
fi

# Bare `g` is the command run most often; anything else is git with arguments.
g() {
  if (( $# > 0 )); then
    git "$@"
  else
    git status
  fi
}

md() { mkdir -p "$1" && cd "$1" }
