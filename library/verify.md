# verify
Record each check with bin/ledger (phase=verify, evidence=command + key output line, result=pass|fail|not-run).

## When to Use
- Before saying done, committing or handing off; after any fix, refactor or config change.

## Steps
1. Restate the acceptance check from the spec or task. None exists: derive one and say so. Done also needs the standing bar in library/quality-bar.
2. Run the REAL artifact (CLI, endpoint, script, UI path), not a proxy. Read the actual value, not a cached or derived one. Include one failure or edge case. A change that adds a signal names the test that asserts it (library/observability).
3. Anything with state, side effects or several actors (workers, ledgers, files, branches, hooks, installs): run it END TO END, live, in an isolated scratch copy with the real tools, never stubs. Cover every scenario: the happy path, each refuse or keep case, a failure, a rerun and the cleanup; a safety rule gets one attempt to break it. Keep the commands and output, and ledger it: `bin/ledger live "<tool and scenarios>" "<what you saw>" "<evidence path>" pass` (or fail). Unit tests alone missed a prune that re-opened a closed task and a gate that said clear with a live worker.
4. Prefer a deterministic script that re-runs the same comparison over a one-time eyeball; keep its output. A new script you cite must be a file in the diff so a reviewer can rerun it; existing repo scripts and plain commands are fine.
5. Run the project's tests, lint and typecheck too: necessary, not sufficient. Tier them by cost: T1 on every change (suite, lint, tripwire, a scan that no assertion was weakened); T2 when a CLI, flag or hook is touched (real-CLI contract check: bin/spawn --doctor plus one real run); T3 when a skill or prompt changes (evals/, at least 2 runs against a bar). Unrun tiers are reported not-run.
6. Bug: ledger the repro fail before the fix and the same command's pass after (`bin/ledger repro "<command>" "<what fails>" "<log>" fail`, then `bin/ledger repro "<same command>" "now passes" "<log>" pass`); the original repro now passes AND its regression family is in the suite, red before the fix: the repro, sibling cases of the same fault class, the boundary values, and what must not change. Refactor: output equals the saved baseline.
7. Diff hygiene: see library/git-ship.
8. When a check fails, suspect your observation method before the system, but never soften the result. A "pre-existing failure" claim is a hypothesis: reproduce it on the base first (two such claims were real bugs).
9. Report unrun or inconclusive checks plainly as not-run.
10. After launching any long background job (suite, worker, deploy), read its first output within a minute to confirm it actually started; do not wait for the exit notice. A missing task id or flag fails in seconds and is invisible until then.

## Closing gate
Run `bin/verify` before `bin/ledger done`: done exits 4 unless the newest verify-gate row passed for the current tree id (`git write-tree` of a temporary index, so an edit after the pass is another tree) and its log file exists. Only `bin/verify` writes that row; a hand-written phase is refused. The tree id ignores uncommitted submodule edits.
The base is the task's start commit (its start row `head <sha>`, printed by `bin/verify base-commit`); older tasks fall back to the merge-base with origin/main, main, origin/master or master. Only a tree equal to the base closes with no row.
Tiers: no diff runs nothing; docs-only (README.md, docs/**) runs the light tier; anything else runs the full suite plus scanner. AGENTS.md, skills/, library/, opencode/commands/ are code, not docs.
Exit codes: 0 pass, 1 fail, 2 could not run (recorded not-run, never a pass).
A gated close prints `verified: <tier> <reason> log <evidence>`.
`--waive "<reason of 20+ chars>"` closes anyway, writes a waive row, and every later close prints it.
Flaky and slow are bugs: fix them through dev-debug, never waive them.
Known scanner gap: assertion counts, so a swap to another name in the same file passes.

## Red Flags
- "Tests pass" or "it compiles" offered as proof; "should work".
- Only the happy path ran; evidence is a paraphrase, not output.
- A feature with side effects verified by unit or stub tests only, with no live end-to-end run.
- A bug closed with one test for the exact repro and none for its neighbors.
- Skipped checks not listed as skipped.
- Waiting on a background job whose start was never confirmed.

## Verification
- Each acceptance item has a ledger row with a command and real output; failures and skips are stated.
- A feature with side effects has a ledger row for a live end-to-end run: the row names the real tool and the scenarios; the ledger shows the repro fail before the fix and pass after.
