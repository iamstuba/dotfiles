# Interactive shells. Every source and every eval is guarded, because bootstrap
# opens a shell before the formulae land and the smoke test runs on a machine
# with none of these tools. A guard that fires must print nothing at all.

# ---------------------------------------------------------------- history --
# ZDOTDIR is a directory symlink into the repo, so anything zsh writes under it
# dirties the working tree. History and the completion dump go to $HOME.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000              # years of history costs a few MB and nothing else
SAVEHIST=100000

setopt EXTENDED_HISTORY      # timestamp and duration per entry, so Ctrl-R can say when
setopt SHARE_HISTORY         # a command typed in one Ghostty tab reaches the next
setopt HIST_IGNORE_ALL_DUPS  # drop the older copy, so Ctrl-R shows each command once
setopt HIST_IGNORE_SPACE     # a leading space keeps a secret out of the file
setopt HIST_REDUCE_BLANKS
# No INC_APPEND_HISTORY: zshoptions says to turn it off when SHARE_HISTORY is
# on, which already appends. It is the fallback if live cross-tab import annoys.

# ---------------------------------------------------------------- options --
setopt interactive_comments  # pasted commands carrying # comments do not error
setopt extended_glob         # **/ recursion, ^negation, and the compinit glob below
setopt NO_LIST_BEEP          # an ambiguous completion is not worth a beep
REPORTTIME=10                # print timings for anything that runs over 10 seconds

# ------------------------------------------------------------- completion --
# The dump sits in $HOME for the same reason HISTFILE does. The glob matches
# only when the dump is over 24 hours old; the fpath security scan is worth
# paying for once a day, and -C skips it every other time.
autoload -Uz compinit
if [[ -f $HOME/.zcompdump && -z $HOME/.zcompdump(#qN.mh+24) ]]; then
  compinit -C -d "$HOME/.zcompdump"
else
  compinit -d "$HOME/.zcompdump"
fi

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # doc<TAB> finds Documents, and back
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' insert-tab pending                  # pasting a tab stops triggering completion
# fzf-tab's README asks for `menu no`, so it can capture the unambiguous
# prefix itself. This overrides the `menu select` set above.
zstyle ':completion:*' menu no
zstyle ':completion:*' verbose yes
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'

# ---------------------------------------------------------------- plugins --
# Sourced by path, no plugin manager. Nothing sets HOMEBREW_PREFIX here,
# because .zprofile exports a literal PATH instead of running `brew shellenv`,
# so the default below stands in for it. The order below is what the
# plugins themselves require. fzf-tab has to come after compinit and before
# anything that wraps widgets, and syntax highlighting stops colouring unless
# it is dead last.
_brew_share="${HOMEBREW_PREFIX:-/opt/homebrew}/share"
# The formula installs fzf-tab.zsh; upstream's README names fzf-tab.plugin.zsh,
# which does not exist here.
[ -r "$_brew_share/fzf-tab/fzf-tab.zsh" ] && source "$_brew_share/fzf-tab/fzf-tab.zsh"
[ -r "$_brew_share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$_brew_share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[ -r "$_brew_share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && source "$_brew_share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
unset _brew_share

# ------------------------------------------------------------------ tools --
# mise replaces fnm. .nvmrc and .node-version still switch Node per directory.
command -v mise >/dev/null && eval "$(mise activate zsh)"

if command -v fzf >/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f'
  # Tokyo Night Night, from folke/tokyonight.nvim at extras/fzf. Upstream
  # builds this value by appending to itself over two lines; one assignment
  # holding the string is easier to read than the sequence that produces it.
  export FZF_DEFAULT_OPTS="--highlight-line --info=inline-right --ansi --layout=reverse --border=none \
--color=bg+:#283457 --color=bg:#16161e --color=border:#27a1b9 --color=fg:#c0caf5 \
--color=gutter:#16161e --color=header:#ff9e64 --color=hl+:#2ac3de --color=hl:#2ac3de \
--color=info:#545c7e --color=marker:#ff007c --color=pointer:#ff007c --color=prompt:#2ac3de \
--color=query:#c0caf5:regular --color=scrollbar:#27a1b9 --color=separator:#ff9e64 \
--color=spinner:#ff007c"
  source <(fzf --zsh)
fi

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
command -v starship >/dev/null && eval "$(starship init zsh)"

# ------------------------------------------------------------------- keys --
# emacs, not vi. The vi question reopens after a month of Neovim, not now.
bindkey -e

autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^g' edit-command-line   # Ctrl-G opens the current line in $EDITOR

bindkey '^ ' autosuggest-accept  # Ctrl-Space, so the hand stays off the arrow keys

bindkey '^[[1;5C' forward-word   # Ctrl-right
bindkey '^[[1;5D' backward-word  # Ctrl-left

# Delete sends kdch1 under Ghostty; the literal sequence covers terminals whose
# terminfo entry does not carry it.
zmodload -i zsh/terminfo
if [ -n "${terminfo[kdch1]}" ]; then
  bindkey "${terminfo[kdch1]}" delete-char
else
  bindkey '^[[3~' delete-char
fi

# ------------------------------------------------------- colored man pages --
# Literal escapes rather than tput, which writes to stderr when the shell has
# no tty and would fail the smoke test's empty-stderr assertion.
export MANROFFOPT='-c'
export LESS_TERMCAP_mb=$'\e[1;32m'     # start blink, which groff uses for bold
export LESS_TERMCAP_md=$'\e[1;36m'     # headings and command names
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;44m'  # the status line at the bottom
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;37m'   # options and arguments
export LESS_TERMCAP_ue=$'\e[0m'

# ---------------------------------------------------------------- sources --
[ -r "$ZDOTDIR/aliases.zsh" ] && source "$ZDOTDIR/aliases.zsh"
[ -r "$ZDOTDIR/functions.zsh" ] && source "$ZDOTDIR/functions.zsh"

# Last line, so it wins over anything above it. Anything tied to an employer
# lives here and never in a tracked file: work aliases, work-only paths and
# the agent environment variables that go with them.
[ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
