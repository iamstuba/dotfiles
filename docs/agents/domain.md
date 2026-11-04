# Domain docs

How the engineering skills read this repo's domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repo root, the glossary.
- The `.scratch/` tickets that own the area you are working in. Decisions
  live in each ticket's Answer and the Comments below it, and an area's
  `spec.md` reconciles them. See `issue-tracker.md`.

This repo has one context and no ADRs. Never create `docs/adr/` or
`CONTEXT-MAP.md`. When `/domain-modeling` settles a decision, record it on
the ticket that owns it. Glossary terms still go in `CONTEXT.md`.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If your output contradicts a ticket's Answer or a comment on it, say so
instead of overriding it silently, and name the decision:

> _Contradicts the decision to mount only `~/projects` into the VM, but worth reopening because…_
