---
name: dev-formal-verification-skill
description: Use when ordering, concurrency, lease, slot, retry or idempotent-rerun logic needs a check stronger than tests.
disable-model-invocation: true
---
# dev-formal-verification-skill

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=verify).

## When to Use
- A change touches ordering, concurrency, leases, slots, retries or idempotent reruns, and a test would only cover the orders someone wrote.
- You need a chart a reader can argue with, or a check that a change did not stale a proof.
- Not for a single actor, a UI flow or plain logic (use tests), and not for a bug you already reproduced (use dev-debug).

**You own:** the route into formal verification: triage to a build or a maintenance pass, and a target the chosen skill can start from.

**Reads:** always library/principles (step 0), library/deep/model-check (tool choice, commands, budgets), library/state (closeout).

## Checklist
- [ ] 0. Skim library/principles.
- [ ] 1. Triage by what exists:
  - no model for the promise: hand the build to dev-create-formal-verification-skill;
  - a model exists but covered code changed since its sync commit: hand to dev-maintain-formal-verification-skill;
  - a chart or explanation only: run the TLC and statechart commands in library/deep/model-check and stop.
- [ ] 2. Name the promise in one sentence and the harm if it breaks, so the chosen skill starts from a target, not a tour.
- [ ] 3. Closeout: follow library/state, then `bin/ledger done "<summary>"` or a `next` row.

**Hand off to:** dev-create-formal-verification-skill when no model exists; dev-maintain-formal-verification-skill when a model drifted; dev-debug when a replay shows a real bug.

**Reply:** which path you took and why, the promise in one sentence, and one line on what is not covered.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Tests cover the race" | Tests cover the orders someone wrote; a model covers the rest within the bound. |
| "It passed, so we're done" | A pass proves the model, not the code, and not the timing it omits. |
| "Just draw the chart" | A chart without a checked spec is decoration; run TLC first. |
| "The model drifted but still passes" | A stale pass looks like a proof; a maintenance pass is owed. |

## Red Flags
- A model or a chart asked for with no named promise.
- A model trusted after covered code moved, or after a timer or expiry appeared.
- A build and a maintenance pass in one go, with no coverage record between them.

## Verification
- The chosen path matches what exists: no model, a drifted model, or a chart only.
- The reply names the promise and its timing exclusions.
- library/deep/model-check was followed as written; differences fixed in the file.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
