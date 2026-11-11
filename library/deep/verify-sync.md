# verify-sync

## When to Load
- A check, model, harness or project-local verify skill guards named code, and that code changed since the claim was last confirmed.
- You are writing a verify skill and need the coverage record it must carry.
- A check passes and you are unsure it still describes the code.
- Covered code changed since the sync commit: run the drift pass in dev-maintain-formal-verification-skill against this file.

## Steps
1. Keep a coverage record next to the check: the files and functions it covers, the property it guards, its bounds and assumptions, the command that runs it, the repo that holds the covered code, and the sync commit. Write the machine-readable part as `<task>/model/coverage.env` with `sync=<sha>`, `files=<space separated paths>` and optional `cmd=`; `bin/model-drift` reads only `sync` and `files`; `cmd=` and an optional `functions=` are informational. Point to it from `<task>/state.md`. A check without a record is a draft.
2. The sync commit is the last commit of the repo that holds the covered code where someone confirmed the check still describes it. A green run alone never advances it; when the repo moved but the covered diff is empty and the rerun and the break test pass, advance it (repo moved, nothing covered did).
3. Before trusting a result, diff the covered code from the sync commit to HEAD: `git diff <sync>..HEAD -- <covered files>`. Read the commit messages too, and look for covered code renamed, moved or split, and for new writers of the guarded state.
4. Give each change one outcome:
   - in sync: nothing the check describes changed, and it passes.
   - updated: the code moved, you changed the model or harness to match, and it passes.
   - bug: the check describes the current code and the code breaks the property.
   - blocked: the check could not be updated or run; say exactly why.
5. Change the check to match the code before you rerun, and never reshape it until a failure turns green.
6. Rerun, then show the check can still fail: break the new code the way the property guards against, confirm the failure, drop the break.
7. Advance the sync commit only after the rerun and the break test confirm the check describes HEAD. Record the outcome with `bin/ledger` (phase=verify).
8. A pass on a stale description looks like a proof. Report it as updated or blocked, never as in sync.

## Red Flags
- A green run used as a sync update, with no diff read.
- A model or harness tuned until it passes, shaped by the result rather than the code.
- A property weakened to make a failure go away.
- Covered code moved or renamed and the record left stale.
