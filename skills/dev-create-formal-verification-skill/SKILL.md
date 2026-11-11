---
name: dev-create-formal-verification-skill
description: Use when a promise about ordering, concurrency or a lease has no model yet and needs one built, checked and replayed.
disable-model-invocation: true
---
# dev-create-formal-verification-skill

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=verify).

## When to Use
- No model exists yet for a promise about ordering, concurrency, a lease, a slot, a retry or an idempotent rerun.
- You need the model plus its coverage record and sync commit, not just a picture.
- A model already exists: use dev-maintain-formal-verification-skill. Single actor, UI flow or plain logic: tests are cheaper.

**You own:** one promise checked over every interleaving within a bound, proven able to fail, replayed on the real code, plus its coverage record and sync commit.

**Reads:** always library/principles (step 0), library/deep/model-check (tool choice, commands, budgets), library/deep/verify-sync (coverage record, sync commit), library/state (closeout). Pick the target with library/deep/blast-radius when unsure.

## Checklist
- [ ] 0. Skim library/principles.
- [ ] 1. Pick the target: the promise whose break harms most and that tests rarely reach (a lease held twice, two writers, a rerun that double-charges). Write one plain sentence and one INVARIANT per rule; if the model has no variable for a rule, add it.
- [ ] 2. Point each model step at code a reviewer can open (file:line). One code step stays one model step. Name actions in the repo's words.
- [ ] 3. Choose the tool: TLC on a small TLA+ design by default; a stateful property test against a small reference model (library/deep/property-check) for sequential or crash-free logic the code can drive; Quint and Apalache only if the user names them. Ledger the choice and why.
- [ ] 4. Check at 3 actors (or the narrowest bound that shows the race); chart at 2 actors. Keep the constants small and list what the model excludes: timers, lock or lease expiry, stalls, non-atomic commands.
- [ ] 5. Keep the spec in `<task>/model/`, run plain TLC, and record the exact line it prints. No error means the model holds, not the code, and not under any timing the model omits; when a timeout is the only guard, also check an untimed variant (library/deep/model-check step 5).
- [ ] 6. Prove every rule can fail: remove a check or reorder a step in a copy, watch TLC name that rule, drop the break. A rule never seen failing is untested; never weaken a rule or raise a bound to get a pass.
- [ ] 7. When Bun and `tlachart` are present, draw the chart from the same spec and config; without `tlachart`, report the chart blocked and ask; do not install unasked. The TLC result still stands.
- [ ] 8. Replay each counterexample on the real code, one action per step, as a test or a live repro, and once more with a stall injected past each expiry (shadow one command to inject it, library/deep/model-check step 10). A finding with no failing replay is a hypothesis, not a bug.
- [ ] 9. Record the coverage (files and functions, property, bounds, exclusions, command, repo) and the sync commit where the model matched the code in `<task>/model/coverage.env` as `sync=<sha>`, `files=<space separated paths>` and optional `cmd=`, pointed to from `<task>/state.md`. A check without a record is a draft.
- [ ] 10. Closeout: follow library/state, then `bin/ledger done "<summary>"` or a `next` row.

**Hand off to:** dev-maintain-formal-verification-skill for later drift; dev-debug when a replay shows a real bug; dev-review when the skill changed.

**Reply:** the promise and its plain sentence, tool and bound, the exact TLC line or counterexample, the broken variant that proved the rule can fail, the replay result, the files and sync commit, and every timing the model omits.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Tests cover the race" | Tests cover the orders someone wrote; a model covers the rest within the bound. |
| "It passed, so the design is right" | A pass proves the model, not the code; replay the trace. |
| "The rule was too strict, I relaxed it" | Then the finding was real. Report it; never weaken a rule to get green. |
| "Skip the broken variant, it already passed" | A rule never seen failing is untested; break it and watch TLC name it. |

## Red Flags
- Model steps that merge two code steps.
- A rule never seen failing, or constants shrunk until the bug disappears.
- A safe verdict for a lock or lease whose expiry or stall the model leaves out.
- A counterexample reported without a replay on the real code.
- Adding Node or a verifier install the user did not ask for.

## Verification
- Every rule has a broken variant that failed and a clean rerun that passed.
- Each finding has a replay on the real code, or is labeled a hypothesis.
- The coverage record names files, functions, property, bounds, command and sync commit; `<task>/state.md` is current.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
