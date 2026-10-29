# tdd
Record each red and green with bin/ledger (phase=tdd, evidence=test output line).

## When to Use
- Any new behavior, any bug fix (the regression test), any behavior change. Skip pure config, docs and static content.

## Steps
1. Discover the stack: README, CONTRIBUTING, CI, Makefile, checked-in wrappers. Use the repo's focused-test and full-suite commands; never assume `npm test`.
2. Agree the seam (see library/architecture): the public interface where behavior is observable. Test only there.
3. RED: write one test for one behavior. Run it; it must fail for the RIGHT reason (not a typo or import error). A test that passes at once proves nothing.
4. GREEN: write the smallest code that passes. No speculative features.
5. Run the focused test, then the full suite. Both green. Then check the test itself: break the behavior on purpose (it must fail), change internals (it must still pass), and undo the break.
6. REFACTOR only while green, in a separate step; rerun after each change.
7. Bugs: reproduce with a failing test first; the fix is whatever turns it green. A test is impractical (UI, timing, external system)? Run the closest executable check and ledger why, with its failing-before output.
8. One test and one implementation per cycle.

## Red Flags
- Tests after code ("I'll add tests later").
- Implementation-coupled tests (mocked internals, private methods, querying the DB directly).
- Tautological assertions that recompute the code's own logic.
- Writing all tests first, then all code (imagined behavior).
- Weakening a test to get green (see quality-bar).

## Verification
- Ledger shows a failing run before each passing run; full suite green.
