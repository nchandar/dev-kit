---
name: dev-eval
description: Use when a skill, prompt or workflow change needs a verdict on whether it helps.
disable-model-invocation: true
---
# dev-eval

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason.

Run `bin/ledger` after every step (phase=eval).

## When to Use
- A skill, prompt or workflow edit and you want to know if it makes the agent better.
- Choosing between two variants of a prompt or skill.
- Not for building the change (use dev-feature) or fixing a bug (use dev-debug).

**You own:** a blind comparison and a promote, drop or rerun verdict.

**Reads:** always library/principles (step 0), library/state.

## Checklist
- [ ] 0. Skim library/principles.
- [ ] 1. Frame: name the variant under test and what counts as success. Write a rubric of 3 to 6 concrete criteria for the judge only; candidates never see it.
- [ ] 2. Set up sanitized environments outside the repo (one directory per candidate, project-shaped names such as app-a and app-b). Words like eval, test, judge, rubric, score, benchmark, candidate must not appear in any directory, file or prompt a candidate sees.
- [ ] 3. Author one organic prompt, what a user would really type. State the goal, never the meta.
- [ ] 4. Run N candidates (N = 3 unless the user sets it) via dev-spawn (scout shape unless they must edit), preferably on different CLIs (one CLI installed: fresh sessions of it, and say so in the report), same prompt, each in its own directory. Respect the worker cap; extras queue.
- [ ] 5. Run one blind judge on a different CLI: it sees outputs by neutral labels and the rubric, never a CLI or model name. Comparing two variants: one judge scores both sets in one pass.
- [ ] 6. Check what each candidate actually did (files opened, commands run) from its log, not from its own claims.
- [ ] 7. Read every candidate output yourself, end to end. A disagreement with the judge means bias or an ambiguous rubric; resolve it.
- [ ] 8. Report: variant, rubric, per-candidate notes, judge verdict, your synthesis, recommendation (promote, drop, rerun). Save it as <task>/report.md. Closeout: follow library/state. Then `bin/ledger done "<summary>"`.

**Hand off to:** dev-learn when a change is promoted; otherwise the calling route if any, else the user.

**Reply:** the variant, the rubric, per-candidate notes, the judge's verdict, your synthesis, and the recommendation.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Run it once and eyeball it" | One run is noise; use N. |
| "Tell the candidate it is being judged" | It changes behavior. |

## Red Flags
- Rubric leaked to candidates.
- Judge sees a model or CLI name.
- No check of what the candidate actually did.
- Eval run from inside the repo (a parent AGENTS.md leaks in), against a copy instead of the installed skill, or with a "use no tools" note that blocks skill loading.
- A cause named from one A/B with no control run.

## Verification
- Candidate dirs and prompts carry no banned meta words; the rubric never reached a candidate.
- The judge saw neutral labels only, never a model or CLI name.
- Every candidate output read end to end; a disagreement with the judge is resolved.
- `<task>/report.md` lists variant, rubric, per-candidate notes, judge verdict, synthesis, recommendation.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
