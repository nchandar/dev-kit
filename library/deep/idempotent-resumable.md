# idempotent-resumable

## When to Load
- Commands, lifecycle steps or loops that run amid crashes, restarts and retries.
- Anything leaving locks, temp files, claimed jobs or half-written records.

## Pattern
1. For each mutating step ask: what if it runs twice, and what if the last run died at any point?
2. Derive work from current state: read it, compare to the goal, apply only the difference.
3. Make leftovers recognizable as stale from evidence true at every stop point, not just the common one.
4. Write to a temp path, then rename into place. Compare artifacts by content, not creation order.
5. If an answer is "depends on leftover state", add a reconcile step that runs first.
6. Test it: run twice, and kill it at each step, then rerun.

## Red Flags
- A step that assumes the previous run finished or started clean.
- A lock or marker with no way to judge it stale.
- Crash recovery that means manual cleanup.

Source: pstack/principle-make-operations-idempotent
