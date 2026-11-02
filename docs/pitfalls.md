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
| pg-07 | unbounded until retry loop | bounded-retry | 2026-11-02 |
| pg-08 | 08 read as octal in test/arithmetic | decimal-arith + tests/ledger.test.sh | 2026-11-02 |
| pg-09 | fixed-sleep timing flakes | sleep-ok | 2026-11-02 |
| pg-10 | source-grep test proves nothing | src-grep | 2026-11-02 |
| pg-11 | stale docs after a skill change | tests/lint-budget.test.sh + bin/lint-budget | 2026-11-02 |
