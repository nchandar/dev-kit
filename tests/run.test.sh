#!/usr/bin/env bash
# Tests for bin/run. Usage: tests/run.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
here=$(cd "$(dirname "$0")/.." && pwd); run="$here/bin/run"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q -b main && unset DEVKIT_DIR
export DEVKIT_TASK=$("$ledger" start run-test x); TD=".devkit/tasks/$DEVKIT_TASK"

out=$("$run" true); rc=$?
ok "passing command: exit 0, one summary line" '[ $rc -eq 0 ] && [ "$(echo "$out" | wc -l)" -le 3 ] && echo "$out" | head -1 | grep -q "^exit=0 "'
ok "summary names the log file"            'log=$(echo "$out" | head -1 | sed "s/.*log=//"); [ -f "$log" ]'
ok "pass is ledgered"                      'awk -F"\t" "\$2==\"run\" && \$6==\"pass\"{f=1} END{exit !f}" $TD/ledger.tsv'

out=$("$run" sh -c 'for i in $(seq 1 100); do echo "line $i"; [ $i = 10 ] && echo "FAIL test_a: boom"; [ $i = 50 ] && echo "Error: bad thing"; done; exit 3'); rc=$?
ok "failing command: propagates exit code" '[ $rc -eq 3 ]'
ok "failure output is short (<=45 lines)"  '[ "$(echo "$out" | wc -l)" -le 45 ]'
ok "failure output keeps the failing lines" 'echo "$out" | grep -q "FAIL test_a: boom" && echo "$out" | grep -q "Error: bad thing"'
ok "failure output keeps the tail"         'echo "$out" | grep -q "line 100"'
ok "full output is in the log"             'log=$(echo "$out" | head -1 | sed "s/.*log=//"); [ "$(grep -c "^line " "$log")" -eq 100 ]'
ok "fail is ledgered"                      'awk -F"\t" "\$2==\"run\" && \$6==\"fail\"{f=1} END{exit !f}" $TD/ledger.tsv'

out=$("$run" sh -c 'seq 1 20000; exit 1'); rc=$?
ok "huge output stays small"               '[ "$(echo "$out" | wc -l)" -le 45 ] && [ $rc -eq 1 ]'

out=$("$run" -n 3 sh -c 'seq 1 50; exit 1')
ok "-n sets the tail length"               'echo "$out" | grep -q "^50$" && ! echo "$out" | grep -q "^40$"'

out=$("$run" sh -c 'cat | wc -c')
ok "stdin is closed"                       'log=$(echo "$out" | head -1 | sed "s/.*log=//"); grep -q "^ *0$" "$log"'
out=$("$run" sh -c 'echo "$1"' _ "a b")
ok "arguments with spaces survive"         'log=$(echo "$out" | head -1 | sed "s/.*log=//"); grep -q "^a b$" "$log"'
ok "logs are numbered per task"            '[ "$(ls $TD/runs | wc -l)" -ge 5 ] && ls $TD/runs | head -1 | grep -q "^001"'

env -u DEVKIT_TASK "$run" true >/dev/null 2>&1; rc=$?
ok "no task: exit 2"                       '[ $rc -eq 2 ]'
"$run" >/dev/null 2>&1; rc=$?
ok "no command: exit 2"                    '[ $rc -eq 2 ]'
for i in 1 2 3 4 5 6; do "$run" sh -c "echo par$i" >/dev/null & done; wait
ok "parallel runs keep separate logs" '[ "$(cat $TD/runs/*.log | grep -c "^par")" -eq 6 ]'
n0=$(ls $TD/runs | wc -l); "$run" true >/dev/null
ok "a new run gets a new log" '[ "$(ls $TD/runs | wc -l)" -gt "$n0" ]'

# --- session pointer fallback: $DEVKIT_TASK, then `ledger current` (no -t in run)
PS=sess-run; PT=$(CLAUDE_CODE_SESSION_ID=$PS "$ledger" start ptr-run "x"); PTD=".devkit/tasks/$PT"
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$PS "$run" echo via-pointer); rc=$?
ok "no DEVKIT_TASK: the session pointer supplies the task" '[ $rc -eq 0 ] && [ -d "$PTD/runs" ]'
ok "the pointer run is ledgered in that task"              'awk -F"\t" "\$2==\"run\"" "$PTD/ledger.tsv" | grep -q .'
out=$(DEVKIT_TASK=${TD##*/} CLAUDE_CODE_SESSION_ID=$PS "$run" echo explicit-wins); rc=$?
ok "DEVKIT_TASK wins over the pointer"                     '[ $rc -eq 0 ] && grep -q "explicit-wins" $TD/runs/*.log && ! grep -q "explicit-wins" "$PTD"/runs/*.log 2>/dev/null'
env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$run" true >/dev/null 2>"$t/run-notask.err"; rc=$?
ok "no pointer: the existing no-task error"                '[ $rc -eq 2 ] && grep -q "run: no task. Run: ledger start <slug>" "$t/run-notask.err"'
"$ledger" -t "$PT" done "closed" >/dev/null 2>&1
env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$PS "$run" true >/dev/null 2>"$t/run-closed.err"; rc=$?
ok "closed pointer: the clear error names the task"        '[ $rc -eq 2 ] && grep -q "last task $PT is closed (or gone)" "$t/run-closed.err"'

git -c user.name=t -c user.email=t@t commit -q --allow-empty -m wt-base; mkdir -p "$t/sub/deep"
WS=sess-run-dir; WT=$(CLAUDE_CODE_SESSION_ID=$WS "$ledger" start ptr-dir "x"); WTD="$t/.devkit/tasks/$WT"
git worktree add -q "$t/wt-run" -b wt-run-b
( cd "$t/sub/deep" && env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$WS "$run" echo from-subdir >/dev/null ); rc=$?
ok "run resolves the pointer from a subdirectory of the repo"      '[ $rc -eq 0 ] && grep -q "from-subdir" "$WTD"/runs/*.log'
( cd "$t/wt-run" && env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$WS "$run" echo from-worktree >/dev/null ); rc=$?
ok "run resolves the pointer from a git worktree of the repo"      '[ $rc -eq 0 ] && grep -q "from-worktree" "$WTD"/runs/*.log'

# --- security: no argv in the ledger, private files, no control characters on screen
secret="sk-$(printf 'c%.0s' $(seq 1 24))"
out=$("$run" echo "$secret" --token="$secret"); rc=$?
ok "a secret argument does not reach the ledger"                   '[ $rc -eq 0 ] && ! grep -q "$secret" $TD/ledger.tsv'
ok "the run row records argv[0] and the argument count"            'awk -F"\t" "\$2==\"run\" && \$3==\"echo (3 args)\"" $TD/ledger.tsv | grep -q .'
ok "the runs dir is private"                                       '[ "$(ls -ld "$TD/runs" | cut -c1-10)" = "drwx------" ]'
ok "log files are private"                                         '! ls -l $TD/runs/*.log | cut -c1-10 | grep -qvx -- -rw-------'
esc=$(printf '\033'); tab=$(printf '\t')
out=$("$run" sh -c 'printf "error: \033[2K\033[1Aall tests passed\n"; exit 1'); rc=$?
ok "printed lines drop control characters"                         '[ $rc -eq 1 ] && ! printf "%s\n" "$out" | grep -q "$esc" && printf "%s\n" "$out" | grep -q "all tests passed"'
out=$("$run" sh -c 'printf "FAIL\ta\tb\n"; exit 1')
ok "tabs survive the strip"                                        'printf "%s\n" "$out" | grep -q "$tab"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
