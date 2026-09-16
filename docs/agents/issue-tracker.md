# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `.scratch/`.

`.scratch/` is a clone of the private repo `git@github.com:iamstuba/dotfiles-scratch.git`, ignored by this repo. Commit and push there as you go; nothing under it ever enters the public history. On a machine where the directory is missing, clone it first.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file
- Triage state is recorded as a plain `Status:` line near the top of each issue file, never bolded, so `grep "^Status:"` finds every one (see `triage-labels.md` for the values)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `open`/`claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.

## Comments are amendments

A resolved ticket's `## Comments` section holds decisions made after its Answer by later tickets. Anyone acting on a ticket reads the Answer and every comment below it; a comment overrides the Answer where they disagree. Nothing is implemented from an Answer alone.

## From map to implementation

The map ends when no open tickets remain. Implementation then runs per area, never from one combined spec. For each area a session reads the owning tickets (Answers and Comments), writes `.scratch/impl-<area>/spec.md` reconciling them, derives issues under `.scratch/impl-<area>/issues/`, and implements from those. Contradictions between tickets are resolved in the spec, with a comment back on the losing ticket.
