# attack-the-premise

## When to Load
- Two or more fixes failed the same gate or test.
- You are about to try a third variation of the same idea.

## Pattern
1. Stop. Write the one sentence every failed fix assumed.
2. Find an observation that differs if that sentence is false, and take it before any new fix.
3. Look at how failures are distributed (which cases, which side always loses), not just how many.
4. Evidence contradicts it: the cause is elsewhere; find what the failures share that the premise did not predict.
5. Evidence confirms it: ask the next why; earlier fixes may have patched a consequence.
6. Prefer removing the condition that causes the failure over adding cleanup for it.
7. Make the check rerunnable.

## Red Flags
- "One more tweak" after two failures.
- No written premise.
- Fixes that compensate instead of removing the cause.

Source: pstack/principle-attack-the-premise
