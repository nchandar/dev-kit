#!/usr/bin/env bash
# Tests for bin/run. Usage: tests/run.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); run="$here/bin/run"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && unset DEVKIT_DIR
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
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
