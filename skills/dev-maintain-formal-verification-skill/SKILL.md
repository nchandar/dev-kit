---
name: dev-maintain-formal-verification-skill
description: Use when covered code changed since the sync commit and the existing model must be checked for drift.
disable-model-invocation: true
---
# dev-maintain-formal-verification-skill

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=verify).

## When to Use
- A model and its coverage record guard named code, and that code changed since the sync commit.
- Someone asks whether an existing check still describes HEAD, or a green run looks stale.
- No model or coverage record yet: use dev-create-formal-verification-skill. A bug you already reproduced: use dev-debug.

**You own:** keeping the model in step with the code, the four-outcome verdict, and a sync commit that advances only after confirmation.

**Reads:** always library/deep/verify-sync (coverage record, sync commit, four outcomes), library/deep/model-check (commands, bounds), library/state (closeout).

## Checklist
- [ ] 0. Load the coverage record and sync commit from `<task>/model/`; no record means the check is a draft, so send it back to the create skill.
- [ ] 1. Run `bin/model-drift <task>/model/coverage.env` first: `in-sync` means no covered file changed, `drifted: <files>` names the rest. Diff those files from the sync commit: `git diff <sync>..HEAD -- <covered files>`. Read the commit messages too; look for renamed, moved or split code and for new writers of the guarded state.
- [ ] 2. Give each change one outcome:
  - in sync: nothing the check describes changed, and it passes;
  - updated: the code moved and you changed the model or harness to match, and it passes;
  - bug: the check describes the current code and the code breaks the property;
  - blocked: you could not update or run it; say exactly why.
- [ ] 3. Update from the code, never from the result: reshape the check only after reading the change, and never tune it until a failure turns green.
- [ ] 4. Rerun, then break the new code the way the property guards against, confirm the failure, and drop the break. A rule that cannot fail is not tested.
- [ ] 5. Advance the sync commit only after the rerun and the break test confirm the check describes HEAD; record the outcome with `bin/ledger` (phase=verify).
- [ ] 6. Closeout: follow library/state, then `bin/ledger done "<summary>"` or a `next` row.

**Hand off to:** dev-create-formal-verification-skill when the promise changed or no record exists; dev-debug when the code breaks the property; dev-review when the skill changed.

**Reply:** each change with its outcome, the rerun line, the break that failed, the old and new sync commit, and what the timing exclusions still leave out.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "It still passes, so it is in sync" | A green run on a stale description looks like a proof; diff first. |
| "I tightened the model until it passed" | Then you shaped the check by its result, not by the code. |
| "The code moved, the property must still hold" | Read the change and update the model; renames and new writers break it silently. |
| "Advance the commit, the run was green" | Only the rerun plus the break test confirm the check describes HEAD. |

## Red Flags
- A green run used as a sync update, with no diff read.
- A model or harness tuned until it passes.
- A property weakened to make a failure go away.
- Covered code moved or renamed and the record left stale.
- A sync commit advanced on a green run alone.

## Verification
- Every change in the diff has one outcome, with evidence.
- The rerun and the break test both ran after the update.
- The coverage record and sync commit name HEAD; `<task>/state.md` is current.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
