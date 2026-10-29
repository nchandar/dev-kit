---
name: dev-feature
description: Build a feature or refactor end to end: clarify, spec, thin slices, test-first per slice, review, verify, ship.
---
# dev-feature

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Copy the checklist verbatim into your task list. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=feature).

## When to Use
- New behavior, a behavior change, or a refactor (see Refactor variant).
- Not for a bug (use dev-debug) or a question (use dev-research).

## Checklist
- [ ] 0. Skim library/principles (about 700 tokens); open a deep file only when its trigger matches. Building, deploying or setting up tooling? Also check library/recipes/index.
- [ ] 1. Clarify: first read any research report (the path the user names, else the newest `report.md` under `.devkit/tasks/*/` that matches this request) and grill only on what it leaves open. No report is fine: go straight to library/grill until goal, non-goals and acceptance check are approved. Then refresh `<task>/state.md` (library/state).
- [ ] 2. Spec: follow library/spec; save `<task>/spec.md`. Interface or data shape involved? also library/architecture.
- [ ] 3. Quality bar: no `CONSTRAINTS.md`? follow library/quality-bar; run the baseline.
- [ ] 4. Plan: follow library/plan; write slices to `<task>/plan.json`.
- [ ] 5. Per slice, in order: follow library/tdd (red, green), then run the slice check. Ledger red and green. Refresh state.md at each plan checkpoint.
- [ ] 6. Independent slices: run in parallel worktrees via dev-spawn (ship shape); you merge, workers never do.
- [ ] 7. Runtime path touched? follow library/observability. User-visible? follow library/ui-browser. External library? follow library/docs-grounding.
- [ ] 8. Review: run dev-review on the full diff; fix blockers.
- [ ] 9. Verify: follow library/verify against the spec's acceptance criteria.
- [ ] 10. Ship: follow library/git-ship. Ask before any push. Closeout: follow library/state. Then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

## Refactor variant
Replace steps 1 to 2 with: state the structural goal and the invariant. Save baseline output of the real artifact first. Characterization tests where coverage is thin. Small steps, tests green after each, one commit per step. Migrate all callers, then delete the old path. At step 9 the output must equal the baseline (also library/simplify).

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
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
