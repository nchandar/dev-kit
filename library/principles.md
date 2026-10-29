# principles
Name the principle behind any non-obvious choice in bin/ledger (phase=principle).

## When to Use
- Step 0 of dev-feature, dev-debug and dev-review: skim, apply what fits. Open a deep file only when its trigger matches.

## Steps
Think
1. Make every requirement checkable before building; unclear means grill, not guess.
2. Weigh two or three designs before committing (library/deep/design-options).
3. Name the premise behind a plan; two fixes failing the same check means test the premise (library/deep/attack-the-premise).
Design
4. Shape the data first; the right model deletes branches (library/deep/model-the-domain).
5. Validate at the edge, trust types inside, keep logic pure and the shell thin (library/deep/boundaries-and-types).
6. Safe to rerun and resume; own your state before adding locks (library/deep/idempotent-resumable, library/deep/shared-mutable-state).
7. Delete before you add; a reader should trace it in 30 seconds (library/deep/reader-load).
Test and prove
8. Red first, for the right reason; test behavior at the public seam, then break the behavior to see the test fail.
9. Verify the real artifact, not a proxy; a cited script is a file in the diff (library/deep/build-the-lever).
10. Name the limiter and noise floor before trusting a number (library/deep/explain-the-number).
11. Done is the task's acceptance criteria plus the standing bar (library/deep/definition-of-done).
Work
12. One change, one check; small units that each end verifiable.
13. Never lower the bar to get green; turn a repeated instruction into a check (library/deep/encode-lessons).
14. Keep bulk output out of your context; log or delegate it (library/deep/context-guard).
15. Review correctness, clarity, architecture, security, performance, starting from the tests (library/deep/five-axis-review).

## Red Flags
- Loading every deep file up front: the list exists so you do not.
- Citing a principle without applying it in the step you are on.

## Verification
- The ledger names the principle behind each non-obvious choice; deep files were opened only when triggered.
