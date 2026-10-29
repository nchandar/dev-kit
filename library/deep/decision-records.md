# decision-records

## When to Load
- A choice is costly to reverse: dependency, schema, public API, auth, architecture.
- You are retiring, replacing, or migrating a system, API, or column.
- A future reader would ask "why on earth did we do it this way?"

## Pattern
1. Size it. Small, easily reversed call: one ledger row (decision, reason, evidence). Large or hard to reverse: a record file in the repo, linked from the ledger row. The repo outlives the task, and the code only shows what, never why.
2. Check for an existing convention first (docs/adr, numbering, headings) and match it. Only if none exists, use docs/decisions/NNNN-title.md.
3. Keep it to one page: Context (the forces and constraints now), Options (2 to 3 real ones), Choice, Why, Rejected (each with the reason it lost), Consequences (including the downsides we accept), Revisit when (a concrete trigger, such as "if volume passes 10k/day").
4. Write it when deciding, not afterward; reasons fade fast. Rejected options matter most: they stop the next person from reopening a settled question.
5. Never edit history. If the decision changes, write a new record that supersedes the old one and mark the old one superseded.
6. Deprecation is a decision too. Record: why the old thing no longer earns its upkeep, the replacement (never deprecate without a working one), consumer count, advisory or compulsory, and the removal condition.
7. Migrate in steps that can be reversed: build the replacement, announce, move consumers one by one (adapter, strangler, or flag), confirm zero usage by metrics, then remove. The owner of the old system carries the migration work.
8. Schema changes: expand, backfill, switch reads, contract. Additive first; the drop is its own later deploy, because data cannot be rolled back.

## Red Flags
- A record that lists only the winner.
- No revisit trigger, so it never gets challenged.
- Deprecation announced with no replacement or owner.
- Rename or drop shipped in the same deploy as the code change.
- Records for trivial choices; they bury the real ones.

Source: agent-skills/documentation-and-adrs, deprecation-and-migration
