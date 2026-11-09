# Constraints (quality bar)
Each line names its check. The bar only moves up; loosening any number or adding a skip needs the user's approval.

| Dimension | Bar | Check |
|---|---|---|
| Tests | every suite passes, none skipped | `tests/run-all.sh` exits 0 |
| Lint | caps on AGENTS.md, skills, library respected | `bin/lint-budget` OK |
| Leaks | no test calls the real herdr | the tripwire line of `tests/run-all.sh` |
| Flakiness | zero: a suite that fails then passes on rerun is a bug | `bin/verify` (flaky = fail) |
| Speed per suite | at most 215 s (baseline slowest 141 s) | `bin/verify` against `bin/verify.budget` |
| Speed total | at most 420 s (baseline 320 s) | `bin/verify` against `bin/verify.budget` |
| Weakened tests | no fewer assertions, no `|| true` or `exit 0` escapes | `bin/verify-scan` |
| Gate files | `bin/verify`, `bin/verify-scan`, `bin/verify.budget`, the done gate in `bin/ledger`, `tests/verify*.test.sh`, `tests/fixtures/verify/**` change only with user approval | `bin/verify-scan` |
| Merge | every CI check passed (`gh pr checks`); none, pending or failing means do not merge | `library/git-ship.md` |
| Closing a task | a passing verify row for the current tree, or a recorded `--waive` | `bin/ledger done` |

Baseline 2026-11-08: 27 suites, 320 s total; spawn-interactive 141 s and spawn 112 s are slow-test bugs to fix, then ratchet the numbers down.
