# verify
Record each check with bin/ledger (phase=verify, evidence=command + key output line, result=pass|fail|not-run).

## When to Use
- Before saying done, committing or handing off; after any fix, refactor or config change.

## Steps
1. Restate the acceptance check from the spec or task. None exists: derive one and say so. Done also needs the standing bar in library/quality-bar.
2. Run the REAL artifact (CLI, endpoint, script, UI path), not a proxy. Read the actual value, not a cached or derived one. Include one failure or edge case.
3. Anything with state, side effects or several actors (workers, ledgers, files, branches, hooks, installs): run it END TO END, live, in an isolated scratch copy with the real tools, never stubs. Cover every scenario: the happy path, each refuse or keep case, a failure, a rerun and the cleanup; a safety rule gets one attempt to break it. Keep the commands and output. Unit tests alone missed a prune that re-opened a closed task, a suite green alone but red under run-all, and a gate that said clear with a live worker.
4. Prefer a deterministic script that re-runs the same comparison over a one-time eyeball; keep its output. A new script you cite must be a file in the diff so a reviewer can rerun it; existing repo scripts and plain commands are fine.
5. Run the project's tests, lint and typecheck too: necessary, not sufficient. Tier them by cost: T1 on every change (suite, lint, tripwire, a scan that no assertion was weakened); T2 when a CLI, flag or hook is touched (real-CLI contract check: bin/spawn --doctor plus one real run); T3 when a skill or prompt changes (evals/, at least 2 runs against a bar). Unrun tiers are reported not-run.
6. Bug: the original repro now passes AND its regression family is in the suite, red before the fix: the repro, sibling cases of the same fault class, the boundary values, and what must not change. Refactor: output equals the saved baseline.
7. Diff hygiene: see library/git-ship.
8. When a check fails, suspect your observation method before the system, but never soften the result. A "pre-existing failure" claim is a hypothesis: reproduce it on the base first (two such claims were real bugs).
9. Report unrun or inconclusive checks plainly as not-run.

## Red Flags
- "Tests pass" or "it compiles" offered as proof; "should work".
- Only the happy path ran; evidence is a paraphrase, not output.
- A feature with side effects verified by unit or stub tests only, with no live end-to-end run.
- A bug closed with one test for the exact repro and none for its neighbors.
- Skipped checks not listed as skipped.

## Verification
- Each acceptance item has a ledger row with a command and real output; failures and skips are stated.
- A feature with side effects has a ledger row for a live end-to-end run that names each scenario covered.
