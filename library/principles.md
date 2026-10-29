# principles
Name the principle behind any non-obvious choice in bin/ledger (phase=principle).

## When to Use
- Step 0 of dev-feature, dev-debug and dev-review. Skim, apply what fits, and open a deep file only when its trigger matches; the list exists so you do not load them all.

## Steps
Think before building
1. Make every requirement checkable before you build. If you cannot say how you would know it works, ask; do not guess (library/deep/spec-driven).
2. Weigh two or three real designs and pick on evidence, not on the first idea (library/deep/design-options).
3. Write down the premise behind a plan. When two fixes fail the same check, the premise is suspect, so test it directly (library/deep/attack-the-premise).

Architecture defaults
4. Shape the data first: the right model deletes branches and invalid states (library/deep/model-the-domain).
5. Deep modules and thin interfaces: a small contract with real behavior behind it; callers never reach inside (library/architecture).
6. Contracts evolve additively, and consumers you cannot see are real (library/deep/api-contracts).
7. Validate at the edge, trust the types inside, keep logic pure and the shell thin (library/deep/boundaries-and-types).
8. Make steps safe to rerun and resume, and give each actor its own state before reaching for a lock (library/deep/idempotent-resumable, library/deep/shared-mutable-state).
9. Delete before you add. A reader should be able to trace the code in 30 seconds (library/simplify, library/deep/reader-load).
10. Record the decision that is hard to reverse: what, why, and what you rejected (library/deep/decision-records).

Test and prove
11. Red first, for the right reason. Test behavior at the public seam, then break the behavior on purpose and watch the test fail (library/tdd, library/deep/test-strategy).
12. Verify the real artifact, never a proxy. A script you cite is a file in the diff (library/verify, library/deep/build-the-lever).
13. Before trusting a number, name its limiter and its noise floor (library/deep/explain-the-number).
14. Done is the task's acceptance criteria plus the standing bar (library/deep/definition-of-done).

Work with discipline
15. One change, one check: small units that each end verifiable (library/plan).
16. Never lower the bar to get green. An instruction you keep repeating becomes a check (library/deep/encode-lessons).
17. Keep bulk output out of your context; log it or delegate it (library/deep/context-guard).
18. Review correctness, clarity, architecture, security and performance, starting from the tests (library/deep/five-axis-review).

## Red Flags
- Loading every deep file up front instead of on a matching trigger.
- Citing a principle without applying it in the step you are on.
- A new rule added here that a deep file or an existing library file already states.

## Verification
- The ledger names the principle behind each non-obvious choice; deep files were opened only when triggered.
