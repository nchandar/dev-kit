---
name: dev-model-check
description: Use when ordering, concurrency, lease, slot, retry or idempotent-rerun logic needs a check stronger than tests.
disable-model-invocation: true
---
# dev-model-check

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=verify).

## When to Use
- A change touches ordering, concurrency, leases, slots, retries or idempotent reruns: a bad interleaving tests would only hit by luck.
- You need a chart a reader can argue with, or a check that a change did not stale a proof.
- Not for a single actor, a UI flow or plain logic (use tests), and not for a bug you already reproduced (use dev-debug).

**You own:** one promise checked over every interleaving within a bound, proven able to fail, replayed on the real code, plus its coverage record and sync commit.

**Reads:** always library/deep/model-check (tool choice, commands, budgets), library/deep/verify-sync (coverage record, sync commit, four outcomes), library/state (closeout). Pick the target with library/deep/blast-radius when unsure.

## Checklist
- [ ] 0. Skim library/principles.
- [ ] 1. Pick the target: the promise whose break harms most and that tests rarely reach (a lease held twice, two writers, a rerun that double-charges). Write one plain sentence and one INVARIANT per rule; if the model has no variable for a rule, add it.
- [ ] 2. Point each model step at code a reviewer can open (file:line). One code step stays one model step. Name actions in the repo's words.
- [ ] 3. Choose the tool: TLC on a small TLA+ design by default; stateful property tests when the real code is cheap to drive; Quint and Apalache only if the user names them. Ledger the choice and why.
- [ ] 4. Check at 3 workers (or the narrowest bound that shows the race); chart at 2 workers. Keep the constants small and say what the bound excludes.
- [ ] 5. Keep the spec in a scratch folder outside the repo, run plain TLC, and record the exact line it prints. No error means the model holds, not the code.
- [ ] 6. Prove every rule can fail: remove a check or reorder a step in a copy, watch TLC name that rule, drop the break. A rule never seen failing is untested; never weaken a rule or raise a bound to get a pass.
- [ ] 7. When Bun and pstack's statechart are present, draw the chart from the same spec and config; otherwise draw the Mermaid from the TLC trace and say it is hand-drawn.
- [ ] 8. Replay each counterexample on the real code, one action per step, as a test or a live repro. A finding with no failing replay is a hypothesis, not a bug.
- [ ] 9. Record the coverage (files and functions, property, bounds, command) and the sync commit where the model matched the code. A check without a record is a draft.
- [ ] 10. On later work, run the drift loop first: diff covered code from the sync commit to HEAD, give each change one outcome (in sync, updated, bug, blocked), update from the code, rerun, break-test, then advance the sync commit.
- [ ] 11. Closeout: follow library/state, then `bin/ledger done "<summary>"` or a `next` row.

**Hand off to:** dev-feature or dev-debug when a finding is a real bug; dev-review when the model or this skill changed.

**Reply:** the promise and its plain sentence, tool and bound, the exact TLC line or counterexample, the broken variant that proved the rule can fail, the replay result, the files and sync commit, and what is not covered.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Tests cover the race" | Tests cover the orders someone wrote; a model covers the rest within the bound. |
| "It passed, so the design is right" | A pass proves the model, not the code; replay the trace. |
| "The rule was too strict, I relaxed it" | Then the finding was real. Report it; never weaken a rule to get green. |
| "The model drifted, but it still passes" | A stale pass looks like a proof; run the sync diff. |

## Red Flags
- Model steps that merge two code steps.
- A rule never seen failing, or constants shrunk until the bug disappears.
- A counterexample reported without a replay on the real code.
- A sync commit advanced on a green run alone.
- A hand-drawn chart presented as exhaustive, or a report shown as a proof.
- Adding Node or a verifier install the user did not ask for.

## Verification
- Every rule has a broken variant that failed and a clean rerun that passed.
- Each finding has a replay on the real code, or is labeled a hypothesis.
- library/deep/model-check and library/deep/verify-sync were followed as written; differences fixed in the files.
- The coverage record names files, functions, property, bounds, command and sync commit; `<task>/state.md` is current.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
