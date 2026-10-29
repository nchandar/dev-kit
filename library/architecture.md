# architecture
Record non-obvious design decisions and why with bin/ledger (phase=design).

## When to Use
- New module or interface, public API or data shape change, or code that is hard to test or change.

## Steps
1. Model the domain first: nouns and rules in the project's own words, consistent across code, tests and docs (library/deep/model-the-domain).
2. Prefer deep modules: small interface, substantial behavior behind it. Find the seam where behavior is observable; tests live there.
3. Define the contract: inputs, outputs, errors, invariants, and what must stay stable. Additive changes over breaking ones.
4. Validate at the edge, trust inside; callers depend on the interface, never internals; let types carry rules (library/deep/boundaries-and-types).
5. Make steps safe to rerun and resume (library/deep/idempotent-resumable); give each actor its own state before adding locks (library/deep/shared-mutable-state).
6. Replacing an API: migrate all callers, then delete the old path. Before adding an abstraction, delete or reuse (library/simplify).
7. Record a non-obvious decision (what, why, rejected alternative) as one ledger row. Weighing real alternatives: library/deep/design-options.

## Red Flags
- Speculative generality (hooks for needs nobody has); a class that only delegates.
- Shotgun edits across many files for one change; one file edited for unrelated reasons.
- Primitives standing in for domain concepts; long a.b().c().d() chains.
- Half-migrated callers.

## Verification
- Interface can be tested without reaching inside; one-line description of each module's job; no new abstraction without two real uses.
