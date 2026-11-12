---
name: dev-debug
description: Use when something is broken: a bug, failing test, regression, crash or error in logs.
disable-model-invocation: true
---
# dev-debug

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=debug).

## When to Use
- A failing test, broken build, wrong behavior, regression, or error in logs.
- Not for new behavior (use dev-feature).

**You own:** one bug, from a command-line repro to a closed regression test and a verified fix.

**Reads:** always library/principles (step 0), library/debug-method, library/doubt, library/tdd, library/verify, library/git-ship, library/state. If the cause took a deep dig: library/observability and library/deep/observe-and-test. If the bug crosses components: library/explain-html. If building, deploying or setting up tooling: library/recipes/index.

## Checklist
- [ ] 0. Skim library/principles (about 700 tokens); open a deep file only when its trigger matches. Building, deploying or setting up tooling? Also check library/recipes/index.
- [ ] 1. Recon, hypotheses, clarify: restate bug (expected vs actual, two lines). Fresh research report wins; else follow skills/dev-research/SKILL.md (clarify skipped, checkpoint folds into options). List 2-3 hypotheses + recommendation; grill. Unknowns loop back to recon, up to 3 rounds.
  - dev-research covers failing code, tests, logs, recent changes plus the external industry-standard/cutting-edge pass.
- [ ] 2. Reproduce with a command, via library/debug-method (stop-the-line, preserve evidence); ledger it before any fix: `bin/ledger repro "<command>" "<what fails>" "<log or output>" fail`. No repro, no fix.
- [ ] 3. Localize and find the root cause at file:line (library/debug-method). Check the same fault elsewhere. Crosses components? show the failure path on an explain-html page (library/explain-html).
- [ ] 4. Doubt: run library/doubt on the root-cause claim with a fresh scout; settle every objection (brief forbids sub-workers: write the self-doubt with per-objection dispositions instead). Refresh `<task>/state.md` (library/state).
- [ ] 5. Regression test first: follow library/tdd; see it fail for the right reason, then add neighbor tests (sibling cases of the same fault class, boundary values, what must not change): several tests per bug, not one. A bug is closed only with those regression tests plus a docs/pitfalls.md row (or a new pitfalls rule); read docs/pitfalls.md at recon.
- [ ] 6. List 2-3 fix options with a recommendation and ask the user's pick (brief already picks it: record that and skip the ask); then the smallest fix, no drive-by edits. Test green, then the full suite.
- [ ] 7. Verify: follow library/verify; re-run the original repro and ledger its pass (`bin/ledger repro "<same command>" "now passes" "<log>" pass`), plus one adjacent case. Then run the real tool live in an isolated scratch copy and ledger it (`bin/ledger live "<tool and scenarios>" "<what you saw>" "<evidence path>" pass` or fail). Then follow skills/dev-review/SKILL.md on the diff and fix blockers.
- [ ] 7a. Signal check: read existing signals before adding any (library/debug-method); the cause took a deep dig? add the missing signal and assert it in a test (library/observability, library/deep/observe-and-test).
- [ ] 8. Commit via library/git-ship with the root cause in the message. Closeout: follow library/state. Then run `bin/verify`, then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

Stuck after 3 failed hypotheses: write the state as a ledger row (phase=next) and stop or escalate.

**Hand off to:** dev-review on the fix diff. After 3 failed hypotheses, dev-research.

**Reply:** what was broken, the root cause at file:line, the fix, and the failing-then-passing repro output pasted verbatim.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "I see the bug, skip the repro" | Without a repro you cannot prove the fix. |
| "A try/catch fixes it" | That hides the evidence and moves the fault. |
| "Doubt is overkill for a bug" | Confident wrong root causes cause the second bug. |
| "Test already exists" | If it did not fail, it did not catch this bug. |

## Red Flags
- Fixing where the symptom surfaced; a workaround needing a long comment.
- Changing tests to match the bug; "flaky" with no evidence.
- Fix commit with no failing-then-passing test.

## Verification
- Ledger shows: repro fail, root cause line, doubt dispositions, test red then green, repro pass.
- Full suite green; the diff contains only the fix and its test.
- Run `bin/verify`, then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
