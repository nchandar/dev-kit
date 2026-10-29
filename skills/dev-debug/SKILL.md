---
name: dev-debug
description: Fix a bug or failing test: reproduce, find the root cause, have it challenged, add a regression test, fix, verify.
---
# dev-debug

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/harness/`; run tools by that path.

Task: no `HARNESS_TASK` set? Run `~/.agents/harness/bin/ledger start <slug>` first (it prints your id) and prefix harness commands with `HARNESS_TASK=<id>`. `<task>` below is `.harness/tasks/<id>` at the repo root; never write run files anywhere else.

Copy the checklist verbatim into your task list. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=debug).

## When to Use
- A failing test, broken build, wrong behavior, regression, or error in logs.
- Not for new behavior (use dev-feature).

## Checklist
- [ ] 1. Restate the bug: expected vs actual, two lines. Unclear? library/grill.
- [ ] 2. Reproduce with a command, via library/debug-method (stop-the-line, preserve evidence). No repro, no fix.
- [ ] 3. Localize and find the root cause at file:line (library/debug-method). Check the same fault elsewhere.
- [ ] 4. Doubt: run library/doubt on the root-cause claim with a fresh scout; settle every objection.
- [ ] 5. Regression test first: follow library/tdd; see it fail for the right reason.
- [ ] 6. Smallest fix, no drive-by edits. Test green, then the full suite.
- [ ] 7. Verify: follow library/verify; the original repro passes, plus one adjacent case.
- [ ] 8. Observability gap? (the cause took a deep dig) library/observability. Then commit via library/git-ship with the root cause in the message. Then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

Stuck after 3 failed hypotheses: write the state as a ledger row (phase=next) and stop or escalate.

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
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
