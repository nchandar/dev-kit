---
name: dev-learn
description: Turn queued learnings into library improvements: dedupe, generalize, draft on a branch, and merge only after your approval.
---
# dev-learn

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/harness/`; run tools by that path.

Task: no `HARNESS_TASK` set? Run `~/.agents/harness/bin/ledger start <slug>` first (it prints your id) and prefix harness commands with `HARNESS_TASK=<id>`. `<task>` below is `.harness/tasks/<id>` at the repo root; never write run files anywhere else.

Copy the checklist verbatim into your task list. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=learn). The harness repo is the live library, so nothing is edited there until the user approves.

## When to Use
- `bin/learn count` is above 0 (`reconcile` says "learnings queued"), a task just closed, or the user says "learn from this".
- Not for project-specific facts: those stay in `.harness/memory.md`.

## Checklist
- [ ] 1. List: `~/.agents/harness/bin/learn list`. Nothing queued: stop and say so.
- [ ] 2. Dedupe: search the library (`principles.md`, `deep/`, `recipes/`, core files) for each lesson. Already covered: `learn done <id> dropped`, naming the covering file in the ledger row.
- [ ] 3. Classify each: a principle or discipline (a line in `library/principles.md` or a new or edited `library/deep/` file), a procedure with commands (a recipe in `library/recipes/` plus its index line), or project-specific (drop).
- [ ] 4. Generalize and scrub: remove project and org names, paths, emails, tokens, hostnames; keep commands, flags, versions and the reason. A lesson that cannot be generalized is dropped.
- [ ] 5. Draft on a branch in a separate worktree, so the live library is untouched: `W=$(mktemp -d)/learn; git -C ~/.agents/harness worktree add -b learn/<slug> "$W"`. Stay within the caps (recipe at most 45 lines with When to Load, Steps, Gotchas, Verified; one digest line at most). Prefer extending an existing file to adding a new one.
- [ ] 6. Check in `$W`: `bin/lint-budget` and `tests/run-all.sh` pass.
- [ ] 7. Commit on the branch (conventional message, no AI trailer). Show the user `git -C ~/.agents/harness diff main..learn/<slug>` and ask before applying. They may edit or reject.
- [ ] 8. Approved: `git -C ~/.agents/harness merge --ff-only learn/<slug>`, remove the worktree and branch, then `learn done <id> promoted` per lesson. Rejected: remove the worktree and branch, `learn done <id> dropped`. Ask before any push. Then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "It helped me, so it helps everyone" | Test it: would a different project want it? If not, it is memory, not library. |
| "Just add it, tidy later" | The library has caps and one home per rule; dedupe first. |
| "Tiny change, skip the approval" | The library is shared and public; every edit is approved. |

## Red Flags
- Editing the live library before approval, or drafting outside a worktree.
- Project names, paths or emails surviving into a draft.
- A new file where extending an existing one would do; a lesson that restates a principle already there.

## Verification
- Lint and suites pass on the branch; the diff was shown and approved; `bin/learn count` dropped by the number handled; the ledger records each outcome.
