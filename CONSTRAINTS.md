# Constraints (quality bar)
Each line names its check. The bar only moves up; loosening any number or adding a skip needs the user's approval.

| Dimension | Bar | Check |
|---|---|---|
| Tests | every suite passes, none skipped | `tests/run-all.sh` exits 0 |
| Lint | caps on AGENTS.md, skills, library respected | `bin/lint-budget` OK |
| Leaks | no test calls the real herdr | the tripwire line of `tests/run-all.sh` |
| Flakiness | zero: a suite that fails then passes on rerun is a bug | `bin/verify` (flaky = fail) |
| Speed per suite | at most 90 s (slowest suite 58 s serial, about 62 s at cap 4) | `bin/verify` against `bin/verify.budget` |
| Speed total | at most 265 s wall, read from the `wall=` line (serial 200 s, concurrent about 63 s; the first CI run re-baselines it) | `bin/verify` against `bin/verify.budget` |
| Weakened tests | no fewer assertions, no `|| true` or `exit 0` escapes | `bin/verify-scan` |
| Gate files | `bin/verify`, `bin/verify-scan`, `bin/verify.budget`, `bin/ledger` (whole file, not just the gate lines), `bin/run`, `bin/defaults`, `tests/run-all.sh`, `tests/verify*.test.sh`, `tests/fixtures/verify/**` change only with user approval | `bin/verify-scan` |
| Merge | every CI check passed (`gh pr checks`); none, pending or failing means do not merge | `library/git-ship.md` |
| Closing a task | a passing verify row for the current tree, written by `bin/verify` with its per-run token, or a recorded `--waive` | `bin/ledger done` |

Baseline 2026-11-08: 31 suites; 383 s serial before PR 19, about 200 s after.
