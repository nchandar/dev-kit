# Five-Axis Review

## When to Load
- Reviewing a change before merge, especially a bug fix or refactor.
- Assessing generated or unfamiliar code.

## Pattern
1. Read the task and expected behavior, then review tests before implementation.
2. Check that tests exercise behavior, edges, errors, and a regression; mutate a key condition when practical.
3. Review each changed file for correctness, clarity, architecture, security, and performance.
4. For structural findings, propose a concrete move, such as deleting a wrapper or separating orchestration.
5. Order findings by impact and label them Critical, required, optional, or Nit.
6. Verify the claimed checks, inspect the diff for scope and dead code, then record an evidence-backed verdict.

## Red Flags
- Approval based only on passing tests or an unevidenced "LGTM."
- Untested error paths, untrusted inputs, unbounded work, or a hidden N+1 query.
- Complexity relocated into new layers, shared modules, or scattered conditionals.

Source: agent-skills/skills/code-review-and-quality
