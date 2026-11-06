---
name: dev-research
description: Use when you need an answer before building: how something works, an option comparison, feasibility, or a spike.
disable-model-invocation: true
---
# dev-research

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=research). This is the scout shape: it changes no project code.

## When to Use
- Understand a codebase area, compare options, check feasibility, or learn an API before a build.
- Not when the answer is "build it" (use dev-feature).

**You own:** a cited answer or a build-ready report; it changes no project code.

**Reads:** always library/principles (step 0), library/grill, library/docs-grounding, library/doubt, library/explain-html, library/state. For long unattended work: library/deep/overnight.

## Checklist
- [ ] 0. Skim library/principles (about 700 tokens); open a deep file only when its trigger matches.
- [ ] 1. Clarify: follow library/grill, one question at a time with your recommendation, until the question and the decision it feeds are clear. Skip only if already stated, and say so.
- [ ] 2. List sources: code paths, docs, logs, upstream repos, primary sources first. Always include an external industry-standard/cutting-edge pass for the problem, from primary sources (official docs, upstream repos, recent releases), grounded with library/docs-grounding; bulk web reading goes to scouts.
- [ ] 3. Bulk reading goes to scouts via dev-spawn; keep only their reports.
- [ ] 4. Spike only if reading cannot answer: throwaway code in `<task>/spike/`, never in the project tree. Record what it proved.
- [ ] 5. Write findings as claims, each with file:line, URL, or command output as evidence, plus a confidence level.
- [ ] 6. Any claim that drives a decision: run library/doubt on it.
- [ ] 7. Checkpoint: share the findings and your recommendation in a few lines and ask where I agree or disagree. A disagreement or new unknown means grill again, research more, and checkpoint again (up to 3 rounds, then carry the open points into the report). Skip only if I said no questions. Refresh `<task>/state.md` each round (library/state).
- [ ] 8. Write `<task>/report.md`: question, answer in 3 lines, evidence, options with tradeoffs (label each option standard, cutting-edge, or local), recommendation, open questions, and a closing `## Build handoff` (scope, non-goals, acceptance check, first slice) that dev-feature can start from.
- [ ] 9. Write `<task>/report.html` with library/explain-html: animated flow, a short why per step, small tables; open it. Skip with a reason only if the task is trivial.
- [ ] 10. Confirm `git status` shows no project code changes. Ledger the conclusion, and offer the next step: grill me on the open questions, then dev-feature from the report. Closeout: follow library/state. Then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

**Hand off to:** dev-feature when the report ends with a Build handoff and the user agrees.

**Reply:** the answer in 3 lines, evidence with confidence, options with tradeoffs, the recommendation, open questions.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "I know this library" | Memory goes stale; read the version in use. |
| "Just build a quick prototype" | Prototype in the spike dir, then discard it. |
| "Summaries are enough" | A claim without a source cannot be checked. |

## Red Flags
- Claims with no source; a recommendation with no alternatives considered.
- Spike code leaking into the repo; raw dumps pasted into the report.

## Verification
- Every claim has evidence; the decision-driving ones passed doubt; report path is in the ledger; no code diff.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
