# shared-mutable-state

## When to Load
- Parallel workers, agents or jobs may write the same file, branch, key or object.
- A design says "add a lock" or "tell them not to touch X".

## Pattern
1. List the shared mutable things: files read and written by both, branches both push, state both update.
2. Ask if they need one canonical object or are publishing independent facts.
3. Default: give each actor its own file, key, branch or dir; merge only when reading or reporting.
4. Two workers each writing their own field into one state.json is still shared; two files is not.
5. Only if one writer is a real invariant, serialize structurally: lockfile, sequential phases, single-writer actor, compare-and-swap.
6. Instructions and conventions are not concurrency control.

## Red Flags
- "Workers must not edit the same file" written as a rule only.
- A lock added as the first answer.
- Intermittent failures that vanish on rerun.

Source: pstack/principle-separate-before-serializing-shared-state
