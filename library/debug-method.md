# debug-method
Record repro, root cause and guard with bin/ledger (phase=debug).

## When to Use
- Failing test, broken build, behavior differs from expectation, "worked yesterday".

## Steps
1. STOP adding features. Preserve evidence: error text, logs, repro command. Do not push past a red build.
2. Reproduce reliably with a command. No repro: gather logs and environment, bisect (`git bisect`) when it worked before; do not guess a fix.
3. Localize: narrow by layer (input, logic, data, environment), then to file:line. Read the actual error and the actual state; when stuck, instrument.
4. Ask "why" until the answer is a wrong decision in the code, not a consequence of an earlier one. Is the state that triggered the symptom legitimate? If the system may be in that state, handling it is the fix.
5. Restart-only failures: suspect persisted state first (config, caches, locks).
6. Write the root cause as one sentence with file:line in the ledger. Check for the same fault elsewhere and fix all instances.
7. Guard: a regression test (see library/tdd), then the fix, then resume.

## Red Flags
- Fixing where the symptom surfaced, or wrapping it in a try/catch.
- A workaround that needs a paragraph of comment to justify.
- Three failed hypotheses in a row: stop, write the state to the ledger, and ask or escalate.
- "Flaky" used without evidence.

## Verification
- Original repro now passes; the new test failed before and passes after; root cause names a line; adjacent cases checked.
