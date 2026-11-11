# Overnight Unattended Run

## When to Load
- A long task the user will not watch: overnight, or many iterations.
- Work that must stop on its own with no person present.

## Pattern
1. Write the contract first: the goal, a finish condition that is a checkable predicate (never a duration), permissions (local commits only, never push), and an escape hatch.
2. Pass the trust gate: the task was done by hand once, the agent has the signals, and every stage can stop the line.
3. Each iteration: check the predicate, make the smallest change, verify the real artifact, keep or revert, and write one bin/ledger row.
4. Set an iteration cap and stop at it.
5. Never relax the predicate; a plateau means pivot the approach.
6. Wake by the host (a loop or scheduler) or a shell loop that carries the cap (for example the host's /loop).
7. Pause as a WIP commit plus a bin/ledger next row; resume reads that row first.
8. Close with the ketchup-style answer and an Attention section for anything unverified.

## Red Flags
- "Run for 8 hours" as the finish condition.
- Pushing or merging unattended.
- A loop with no cap.
