---
name: dev-feature
description: Use when adding or changing behavior: a new feature, a behavior change, or a user-visible improvement.
disable-model-invocation: true
---
# dev-feature

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=feature).

## When to Use
- New behavior or a behavior change. Structure-only change: use dev-refactor.
- Not for a bug (use dev-debug) or a question (use dev-research).

**You own:** a new or changed behavior, from an approved spec to verified, reviewed commits.

**Reads:** always library/principles (step 0), library/spec, library/plan, library/tdd, library/verify, library/git-ship, library/state. If no CONSTRAINTS.md: library/quality-bar. If the spec needs a flow shown: library/explain-html. If an interface or data shape is involved: library/architecture. If ordering, concurrency or a lease is involved: the dev-formal-verification-skill with library/deep/model-check. If code crosses a function boundary: library/deep/sketch. If a runtime path is touched: library/observability and library/deep/observe-and-test. If user-visible: library/ui-browser. If building an app: library/deep/app-verification-recipe, library/deep/typescript for TypeScript, library/deep/experience-first for UI feel. If an external library: library/docs-grounding. If building, deploying or setting up tooling: library/recipes/index.

## Checklist
- [ ] 0. Skim library/principles (about 700 tokens); open a deep file only when its trigger matches. Building, deploying or setting up tooling? Also check library/recipes/index.
- [ ] 1. Recon, options, clarify: fresh research report wins; else follow skills/dev-research/SKILL.md (clarify skipped, checkpoint folds into options). List 2-3 options + recommendation; grill to approved goal, non-goals, check. Unknowns loop back to recon, up to 3 rounds. Refresh state.md (a worker uses `<task>/state.<worker>.md` or skips it; only the main agent writes `state.md`).
  - Fresh report: user-named path, else newest `.devkit/tasks/*/report.md` for this request.
  - dev-research run: code plus the external industry-standard/cutting-edge pass.
- [ ] 2. Spec: follow library/spec; save `<task>/spec.md`. Interface or data shape involved? also library/architecture. Show the flow on an explain-html page (library/explain-html) for the user's confirmation unless trivial; code crossing a function boundary? follow library/deep/sketch first.
- [ ] 3. Quality bar: no `CONSTRAINTS.md`? follow library/quality-bar; run the baseline.
- [ ] 4. Plan: follow library/plan; write slices to `<task>/plan.json`.
- [ ] 5. Per slice, in order: follow library/tdd (red, green), then run the slice check. Ledger red and green. Refresh state.md at each plan checkpoint.
- [ ] 6. Independent slices: run in parallel worktrees via dev-spawn (ship shape); you merge, workers never do.
- [ ] 7. Runtime path touched? follow library/observability: a signal added is asserted in a test (library/deep/observe-and-test).
- [ ] 7a. User-visible? follow library/ui-browser. External library? follow library/docs-grounding. Building an app? also library/deep/app-verification-recipe; TypeScript: library/deep/typescript; UI: library/deep/experience-first.
- [ ] 8. Review: follow skills/dev-review/SKILL.md on the full diff; fix blockers.
- [ ] 9. Verify: follow library/verify against the spec's acceptance criteria; run the real tool live in an isolated scratch copy and ledger it (`bin/ledger live "<tool and scenarios>" "<what you saw>" "<evidence path>" pass` or fail).
- [ ] 10. Ship: follow library/git-ship. Ask before any push. Closeout: follow library/state. Then run `bin/verify`, then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains. A worker runs `tests/run-all.sh` and `bin/verify-scan` and leaves `bin/verify` and `bin/ledger done` to the parent; a new gate test (`tests/verify*.test.sh`) leaves the scan red until the user approves.

**Hand off to:** dev-review on the full diff, then ship. A structure-only change goes to dev-refactor instead.

**Reply:** what changed for users, each acceptance check with its command and real output, open risks, the commits.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Small feature, skip the spec" | Then the spec is 5 lines. Unwritten scope is how features grow. |
| "I'll add tests after" | Tests written after pass whatever the code does. |
| "One big change is faster" | A break found after a batch is buried; one slice at a time. |
| "Review is for big diffs" | Scope creep and spec gaps hide in small ones. |

## Red Flags
- Code before an approved acceptance check; more than about 100 lines before the first test.
- Slices that cannot be verified alone; parallel slices sharing files.
- Lowering the bar (skip, loosen, ignore) to get green.

## Verification
- Every acceptance criterion maps to a ledger row with command and real output.
- Full suite green; `git diff --stat` matches the spec's scope; dev-review blockers resolved or recorded.
- Run `bin/verify`, then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
