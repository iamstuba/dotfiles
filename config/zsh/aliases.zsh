# Sourced by .zshrc. Nothing here names an employer. The work aliases, the two
# work branch checkouts and the four brew aliases all moved to ~/.zshrc.local,
# which .zshrc sources last. The smoke test fails on any alias that appears
# here without being in this file.

# -------------------------------------------------------------------- git --
# Plain git invocations are shell aliases; pipelines are gitconfig aliases.
alias ga='git add'
alias gaa='git add --all'
alias gap='git add --patch'
alias gbd='git branch -D'
alias gc='git commit'
alias gcam='git commit --amend --no-edit'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gcom='git checkout main'
alias gcp='git cherry-pick'
alias gfp='git fetch --all --tags --force && git pull --rebase'
alias gl='git log'
alias gll="git log --graph --pretty=format:'%Cred%h%Creset %C(bold blue)%an%C(reset) - %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias gm='git merge'
alias gma='git merge --abort'
alias gmc='git merge --continue'
alias gmm='git merge main'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gr='git rebase'
alias gra='git rebase --abort'
alias grc='git rebase --continue'
alias grh='git reset --hard'
alias grm='git rebase main'
alias grs='git reset --soft'
alias gs='git status'
alias gss='git status -s'
alias gwip='git add -A; git rm $(git ls-files --deleted) 2> /dev/null; git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"'
# grep reads a leading -- as an option bundle, so the unfixed pattern made this
# alias fail silently and leave the wip commit in place. -e says it is a pattern.
alias gunwip='git rev-list --max-count=1 --format="%s" HEAD | grep -qe "--wip--" && git reset HEAD~1'

# Reviewing agent commits is the day job, so lazygit gets two keystrokes.
alias lg='lazygit'

# ----------------------------------------------------------------- listing --
alias ll='eza --icons --git --long'
alias l='eza --icons --git --all --long'

# ------------------------------------------------------------------- shell --
alias ..='cd ..'
alias ...='cd ../..'
alias vim='nvim'
alias reload!='source $ZDOTDIR/.zshrc'

alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h -c'
# PATH is unreadable as one colon-joined line once it passes about six entries.
alias lpath='echo $PATH | tr ":" "\n"'
alias rmf='rm -rf'
alias cleanup="find . -name '*.DS_Store' -type f -ls -delete"
