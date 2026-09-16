# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Lifecycle states

A triage label says what a ticket needs from a person. Three more values say
where the ticket is in its life. The wayfinding operations in
`issue-tracker.md` already use all three.

| Value      | Meaning                                         |
| ---------- | ----------------------------------------------- |
| `open`     | Charted, nobody has started                     |
| `claimed`  | A session is working on it right now            |
| `resolved` | Finished; the answer or the work is in the file |

`resolved` is the only word for finished. `done` is not a value.

A spec file carries a `Status:` line of its own. It stays on a triage label
while any ticket under it is open, and becomes `resolved` when the last one
closes.
