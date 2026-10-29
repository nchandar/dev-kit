---
name: dev-research
description: Investigate a question or spike an idea before building, and deliver evidence-backed findings as a Markdown or HTML report.
---
# dev-research

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/harness/`; run tools by that path.

Copy the checklist verbatim into your task list. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=research). This is the scout shape: it changes no project code.

## When to Use
- Understand a codebase area, compare options, check feasibility, or learn an API before a build.
- Not when the answer is "build it" (use dev-feature).

## Checklist
- [ ] 1. State the question and what a good answer looks like (decision it feeds). Vague? library/grill.
- [ ] 2. List sources: code paths, docs, logs, upstream repos, primary sources first.
- [ ] 3. Bulk reading goes to scouts via dev-spawn; keep only their reports. Ground API claims with library/docs-grounding.
- [ ] 4. Spike only if reading cannot answer: throwaway code in `<task>/spike/`, never in the project tree. Record what it proved.
- [ ] 5. Write findings as claims, each with file:line, URL, or command output as evidence, plus a confidence level.
- [ ] 6. Any claim that drives a decision: run library/doubt on it.
- [ ] 7. Write the report: `<task>/reports/<topic>.md` (or `.html` if the user wants a page). Sections: question, answer in 3 lines, evidence, options with tradeoffs, recommendation, open questions.
- [ ] 8. Confirm `git status` shows no project code changes. Ledger the conclusion.

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
