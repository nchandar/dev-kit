# pitfalls

Bug classes that already bit this repo. Every bug fix (dev-debug step 5)
adds a row here naming its guard, or states why no rule is possible.
Read this file at recon (dev-debug step 1); check it with tests/pitfalls.test.sh.

| id | symptom | guard (rule id or repo path) | date |
|---|---|---|---|
| pg-01 | tests leaked real herdr tabs | tripwire + spawn-isolation | 2026-11-02 |
| pg-02 | DEVKIT_DEPTH=abc passed a numeric check | tests/ledger.test.sh | 2026-11-02 |
| pg-03 | seq countdown differs on BSD | seq-args + tests/spawn.test.sh | 2026-11-02 |
| pg-04 | BSD vs GNU stat/date/sed/readlink flags | portable-cmd | 2026-11-02 |
| pg-05 | ps lstart output shifts with TZ/LANG | lstart-tz + tests/spawn.test.sh | 2026-11-02 |
| pg-06 | empty slot start file misread as stale | tests/spawn.test.sh | 2026-11-02 |
| pg-07 | unbounded until retry loop (sleep or break is not a bound) | bounded-retry | 2026-11-02 |
| pg-08 | 08 read as octal in $(( )) or [[ ]] (not [ ]) | decimal-arith + tests/ledger.test.sh | 2026-11-02 |
| pg-09 | fixed-sleep timing flakes | sleep-ok | 2026-11-02 |
| pg-10 | source-grep test proves nothing | src-grep | 2026-11-02 |
| pg-11 | stale docs after a skill change | tests/lint-budget.test.sh + bin/lint-budget | 2026-11-02 |
| pg-12 | timeout or interrupt left grandchildren running (pkill -P is one level) | tests/spawn.test.sh | 2026-11-02 |
| pg-13 | scout commit or repeat edit passed a porcelain-only check | tests/spawn.test.sh | 2026-11-02 |
| pg-14 | parallel bin/run calls clobbered one log name | tests/run.test.sh | 2026-11-02 |
| pg-15 | ledger exited 0 when the append failed | tests/ledger.test.sh | 2026-11-02 |
| pg-16 | task id `..` or `.` escaped the tasks dir | tests/ledger.test.sh | 2026-11-02 |
| pg-17 | header-only ledger made state check swallow state.md | tests/state.test.sh | 2026-11-02 |
| pg-18 | slot claim lost its slot under a stall | tests/spawn.test.sh | 2026-11-02 |
| pg-19 | repo scan passed a dir to a per-file grep and flagged nothing | bounded-retry | 2026-11-02 |
| pg-20 | stat fallback printed filesystem info on Linux when the lock vanished; set -u arithmetic killed the spawner | tests/spawn.test.sh | 2026-11-05 |
| pg-21 | eval scored opencode stderr tool traces (repo files hold sample `route:` lines) instead of the model answer | tests/route-eval.test.sh | 2026-11-05 |
