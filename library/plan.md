# plan
Record the plan and each slice's completion with bin/ledger (phase=plan).

## When to Use
- Work spans more than one file or session, or feels too large to start. Skip for single-file changes with obvious scope.

## Steps
1. Read-only first: spec, relevant code, existing patterns, risks. No code during planning.
2. Map the dependency graph; build the foundation before what depends on it.
3. Cut into thin VERTICAL slices (UI + logic + data for one behavior), not horizontal layers. Each slice: one behavior, touches few files, ends in a state you can check, has its own acceptance check.
4. Write slices as one JSON object per line in `<task>/plan.json` inside an array: `{"id":"s1","goal":"...","check":"cmd","depends":[]}`.
5. Mark independent slices; they can run in parallel worktrees via dev-spawn. Dependent ones run in order.
6. Order for risk: hardest unknown first. Checkpoint after every 2 to 3 slices (full suite green).
7. Do not advance until the current slice is green; commit per slice.

## Red Flags
- A slice that cannot be verified alone, or is bigger than about 100 lines before its first test.
- Layers instead of behaviors ("all models first").
- Parallelizing slices that share files or state.

## Verification
- Every slice has a check command; dependencies are acyclic; the plan matches the spec's requirements one to one.
