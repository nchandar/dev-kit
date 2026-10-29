---
name: dev-review
description: Review a diff on two independent axes, Standards and Spec, with parallel scout reviewers and a blast-radius check.
---
# dev-review

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/harness/`; run tools by that path.

Copy the checklist verbatim into your task list. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=review).

## When to Use
- Before merging or committing a non-trivial diff, after a ship worker returns, or when reviewing a branch or PR.
- Tiny diff: self-review with the same axes and ledger that you did.

## Checklist
- [ ] 1. Pin the fixed point: `git merge-base HEAD <base>`; confirm the diff is non-empty before spawning.
- [ ] 2. Find the spec (issue, `<task>/spec.md`, docs) and the standards (CONTRIBUTING, lint config, AGENTS.md).
- [ ] 3. Brief two scouts, each with the diff command and only its own sources:
  - Standards: repo conventions, then smells (duplication, mystery names, speculative generality, feature envy, shotgun changes). Repo rules override smells. Skip what tooling enforces. Also library/simplify, and library/security or library/performance when the diff touches those.
  - Spec: per requirement, met / partly / missing / extra, with file:line.
- [ ] 4. Run both via dev-spawn (scout shape) in parallel and wait for both reports.
- [ ] 5. Blast radius: for each changed contract, find callers and dependents beyond the diff; prove one "safe because" fact by running code.
- [ ] 6. Merge: dedupe, order by severity (bug, regression, standards, nit), drop anything without file:line.
- [ ] 7. Risky change? library/doubt on your merged conclusion.
- [ ] 8. Each blocker is fixed or accepted with a recorded reason. Re-check the diff after fixes. Then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "One reviewer is cheaper" | Mixed axes hide spec gaps behind style notes. |
| "Tests passed" | Tests do not catch scope creep or missing requirements. |
| "Nits are noise" | Label them nit and do not block on them. |

## Red Flags
- Findings with no file:line; style opinions presented as bugs.
- Reviewer saw the author's reasoning and agrees with it.
- Reviewing an empty or wrong diff; reviewing only the changed lines, not callers.

## Verification
- Both scout reports exist and cite file:line; every finding has a disposition in the ledger.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
