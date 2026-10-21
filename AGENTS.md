# dotfiles

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

`.scratch/` is its own git repo, a clone of the private `dotfiles-scratch`, and
this repo ignores it. Commit and push issue and spec changes there with
`git -C .scratch`. Never force-add them here.

### Triage labels

Default vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Public history

Nothing tracked here names a ticket: not a commit message, not a code comment,
not command output. Name the decision, not its number. Naming the tracker as a
mechanism, the way the sections here do, is fine.

Nothing tracked says how the work Mac is run either. Name the apps it uses,
such as Chrome, and leave out how it is managed and what watches it.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
