# verify
Record each check with bin/ledger (phase=verify, evidence=command + key output line, result=pass|fail|not-run).

## When to Use
- Before saying done, committing or handing off; after any fix, refactor or config change.

## Steps
1. Restate the acceptance check from the spec or task. None exists: derive one and say so. Done also needs the standing bar in library/quality-bar.
2. Run the REAL artifact (CLI, endpoint, script, UI path), not a proxy. Read the actual value, not a cached or derived one. Include one failure or edge case.
3. Prefer a deterministic script that re-runs the same comparison over a one-time eyeball; keep its output. A script you cite must be a file in the diff so a reviewer can rerun it.
4. Run the project's tests, lint and typecheck too: necessary, not sufficient.
5. Bug: the original repro now passes. Refactor: output equals the saved baseline.
6. Diff hygiene: see library/git-ship.
7. When a check fails, suspect your observation method before the system, but never soften the result.
8. Report unrun or inconclusive checks plainly as not-run.

## Red Flags
- "Tests pass" or "it compiles" offered as proof; "should work".
- Only the happy path ran; evidence is a paraphrase, not output.
- Skipped checks not listed as skipped.

## Verification
- Each acceptance item has a ledger row with a command and real output; failures and skips are stated.
