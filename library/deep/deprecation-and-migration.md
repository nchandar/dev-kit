# deprecation-and-migration

## When to Load
- You are asked to remove, replace or keep an old API, feature, flag, script or skill.
- Code nobody calls, or a second way to do the same thing, has piled up.

## Pattern
1. Decide: deprecate or keep. Compare the upkeep cost (bugs, reading, tests, docs) with the users who still depend on it, counted by search and usage signals, not by memory.
2. Zombie code: no callers, no owner, nobody sure it is safe to delete. Prove zero use by search plus a signal, then delete it; leave no commented-out copy.
3. Hyrum's law: with enough users, every observable behavior is depended on, documented or not. Check what callers actually rely on before changing it.
4. Never deprecate without a working replacement and a named owner for the move.
5. Advisory: warn, keep working, no deadline; fits low-cost code. Compulsory: set a removal date and a check that fails past it; fits code that costs real upkeep or risk.
6. Expand/contract: add the new path, move callers one by one, confirm zero use of the old, then remove it in its own change. Schema drops come last.
7. Internal-only API with every caller found: migrate all callers and delete in one wave (library/deep/decision-records).
8. Record the decision, the count of remaining users and the removal condition with `bin/ledger` (phase=principle).

## Red Flags
- "Might still be used" with no search behind it.
- A replacement that is not ready, or deprecation with no date or owner.
- Old and new paths both kept after the move.

Source: agent-skills/deprecation-and-migration
