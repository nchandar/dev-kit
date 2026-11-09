---
name: dev-refactor
description: Use when changing structure without changing behavior: restructure, extract, rename, dedupe or split code.
disable-model-invocation: true
---
# dev-refactor

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason.

Run `bin/ledger` after every step (phase=refactor).

## When to Use
- Structure only: rename, split, extract, dedupe, move, re-layout with no behavior change.
- Not for new behavior (dev-feature), a bug (dev-debug) or a cross-cutting redesign (dev-research).
- A cleanup that reveals a missing feature or a bug: split it out and ship the structure first.

**You own:** a behavior-preserving restructure, with proof the output is unchanged.

**Reads:** always library/principles (step 0), library/simplify, library/verify, library/git-ship, library/state. If the target shape crosses a function boundary: library/deep/sketch and library/explain-html. If an internal API is replaced: library/deep/decision-records. To judge the result: library/deep/reader-load. If a runtime path is touched: library/observability and library/deep/observe-and-test.

## Checklist
- [ ] 0. Skim library/principles; open a deep file only when its trigger matches.
- [ ] 1. State the structural goal and the invariant (what must not change). If the cleanup reveals a missing feature or a bug, split it out (dev-feature, dev-debug) and finish the structure first.
- [ ] 2. Pin behavior: save baseline output of the real artifact; add characterization tests where coverage is thin. Type check and lint are not a pin.
- [ ] 3. Name the target shape (module layout, types, call graph as if built today). It crosses a function boundary? follow library/deep/sketch. Show it on an explain-html page (library/explain-html) unless trivial.
- [ ] 4. Subtract first: delete dead code, one-caller wrappers, redundant validators and orphan references before adding the new shape (library/simplify).
- [ ] 5. Move in small behavior-preserving steps, pin green after each, one commit per step. Internal-only API: migrate every caller and delete the old path in one wave, no shims (library/deep/decision-records).
- [ ] 6. Spot-check every rename against the real files, including strings, docs and back-references.
- [ ] 7. Prove it: output equals the baseline (diff old vs new, or an equivalence script for larger reshapes); follow library/verify.
- [ ] 7a. Runtime path touched? the signals must be identical before and after (library/observability, library/deep/observe-and-test).
- [ ] 8. Keep only what lowers reader load (library/deep/reader-load); revert a change that does not.
- [ ] 9. Review with dev-review; ship via library/git-ship with small ordered commits (subtraction, reshape, follow-on). Closeout: follow library/state. Then run bin/verify, then close the ledger: bin/ledger done "<summary>".

**Hand off to:** dev-review on the full diff. If the cleanup reveals a missing feature or a bug, split it out to dev-feature or dev-debug.

**Reply:** the structure that changed, the pin you held it against, the equivalence proof, the reader-load change, what shipped and what you reverted.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Type check and lint prove it is safe" | They cover types, not behavior; pin the real output. |
| "Keep a shim for callers" | Migrate every caller and delete the old path in the same wave. |
| "Cleanup found a bug, fix it now" | Split it out (dev-debug); finish the structure first. |
| "A grander layout would be nicer" | Name the target shape; revert what does not lower reader load. |

## Red Flags
- Output differs from the baseline with no equivalence proof.
- New indirection or wrappers added before subtracting dead code.
- Rename missed strings, docs or back-references.
- Old and new paths both live; a compatibility shim left behind.
- A speculative cleanup kept though reader load did not drop.

## Verification
- Ledger shows: baseline saved, each step green, equivalence proof, reverts.
- Output equals the baseline: diff old vs new, or an equivalence script.
- Full suite green; the diff holds only structure, no behavior change.
- Run `bin/verify`, then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
