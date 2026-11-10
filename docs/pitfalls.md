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
| pg-22 | opencode session delete had no timeout; route lines: indent was rejected after grep matched it, and a fenced or unusable example hid the real line | tests/spawn.test.sh, tests/spawn-interactive.test.sh | 2026-11-07 |
| pg-23 | `SECONDS -lt 1` timing check failed under load (1 s granularity); bound it below the real hang, not at one tick | tests/reconcile.test.sh | 2026-11-07 |
| pg-24 | stop_session polled `kill -0` (true for an unwaited exited child, so every exit paid 1 s) and a signal during its wait lost the delete pid, leaving a TERM-ignoring delete running | tests/spawn-interactive.test.sh | 2026-11-07 |
| pg-25 | main session never opened the playbook checklist: TaskCreate is deferred in Claude Code and only the worker prompt said to ToolSearch it | tests/todo-hint.test.sh | 2026-11-07 |
| pg-26 | todo rule said "whichever exists" and named no Codex tool, so main sessions still skipped the list; now a first-action rule naming each CLI tool | tests/todo-hint.test.sh | 2026-11-07 |
| pg-27 | a worker cut a test-asserted term ("sharpen") from the word-capped dev-mode skill to fit the cap and never ran the neighbor test; before cutting words from a capped, asserted file, run the full suite or grep every test that names it | tests/pstack-adoption.test.sh, tests/dev-mode.test.sh | 2026-11-07 |
| pg-28 | bin/spawn accepted any worker id (vlA) and failed late with a misleading "claude not ready"; herdr agent names need a lowercase start, [a-z0-9_-], 1-32 chars; validate untrusted names against the downstream rule before the first side effect | tests/spawn.test.sh | 2026-11-08 |
| pg-29 | test asserted on the difference of two whole wall-clock runs while the code under test polls at 1 s; each run is a 1 s step function, so the difference jumped ~1 s on macOS CI. Time the unit directly (stub stamps start/end ms), never difference quantized runs | tests/spawn-interactive.test.sh | 2026-11-08 |
| pg-30 | a gate opened when its own checker was neutered, a signal left the run alive with no row, and a test touched another session's process; fail closed, run checks from the base copy, and match only your own marker | bin/verify + tests/verify.test.sh + tests/verify-scan.test.sh | 2026-11-08 |
| pg-31 | the gate derived the repo from the ledger's location: a worktree task checked the main checkout, and a DEVKIT_DIR outside a repo skipped the gate; derive it from the caller's cwd | tests/verify-gate.test.sh | 2026-11-08 |
| pg-32 | a fixture closed its task with `ledger done` on a dirty scratch tree and the start-commit gate exited 4, so the task stayed open; a suite that must close a task records a gate row or a labelled waive. An INT test also inherited SIGINT ignored from bin/verify's background launch and only failed at the 400s watchdog; reset the disposition with a perl exec before the nested run | tests/reconcile.test.sh, tests/spawn.test.sh, tests/verify.test.sh | 2026-11-08 |
| pg-33 | the scanner read an assertion name ("exit 0", "skip here") as code, so a legitimate test name was a test-escape; the new verify suites also idled 27s of 41s on the fixed 1s watchdog tick | tests/verify-scan.test.sh + tests/verify.test.sh + tests/verify-gate.test.sh | 2026-11-08 |
| pg-34 | slow suites hid under a loose time budget (spawn-interactive 143s, spawn 114s of 383s): the spawn suite left its own artifacts untracked so bin/spawn hashed one file per artifact per run, and tests waited out whole-second stub and timeout windows the test itself owned; gitignore a suite scratch repo, poll a log line instead of a fixed sleep, shrink only test-owned durations, and ratchet bin/verify.budget down after each speedup | bin/verify.budget + tests/spawn.test.sh | 2026-11-08 |
| pg-35 | parallel suite sections wrote a count file at the end; a section that died left none, `read` failed quietly, stale p/f carried over and the suite exited 0 with a false "0 failed"; a missing section result is a failure and must be named | tests/parallel-sections.test.sh | 2026-11-08 |
| pg-36 | a suite wrote crash copies into the repo tree, so a concurrent `bin/lint-budget` scan failed on their fixtures | repo-tree-write + tests/parallel-sections.test.sh | 2026-11-08 |
| pg-37 | the reclaim lock expired by mtime, so a stalled but live reclaimer's lock was stolen and its pending `rm -rf` freed the next claim's live slot; locks name their owner and are stolen only when that owner is dead or its pid was reused | tests/spawn.test.sh | 2026-11-09 |
