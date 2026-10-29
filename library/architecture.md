# architecture
Record non-obvious design decisions and why with bin/ledger (phase=design).

## When to Use
- New module or interface, public API or data shape change, or code that is hard to test or change.

## Steps
1. Model the domain first: name the nouns and rules in the project's own words; keep names consistent across code, tests and docs.
2. Prefer deep modules: small interface, substantial behavior behind it. Find the seam where behavior is observable; tests live there.
3. Define the contract: inputs, outputs, errors, invariants, and what must stay stable. Additive changes over breaking ones.
4. Respect boundaries: validate at the edge, trust inside; callers depend on the interface, never internals.
5. Let types carry rules: make illegal states unrepresentable; avoid stringly-typed domain concepts.
6. Make operations idempotent where retries can happen; separate shared state before serializing it.
7. Subtract before adding: delete or reuse before introducing an abstraction. Replacing an API: migrate all callers, then delete the old path.
8. Record a non-obvious decision (what, why, rejected alternative) as one ledger row.

## Red Flags
- Speculative generality (hooks for needs nobody has); a class that only delegates.
- Shotgun edits across many files for one change; one file edited for unrelated reasons.
- Primitives standing in for domain concepts; long a.b().c().d() chains.
- Half-migrated callers.

## Verification
- Interface can be tested without reaching inside; one-line description of each module's job; no new abstraction without two real uses.
