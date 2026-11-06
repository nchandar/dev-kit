#!/usr/bin/env bash
# Tests for bin/stop-gate (Claude Code Stop hook adapter). Usage: tests/stop-gate.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
here=$(cd "$(dirname "$0")/.." && pwd); gate="$here/bin/stop-gate"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
unset DEVKIT_DIR DEVKIT_TASK
hook() { printf '{"session_id":"%s","stop_hook_active":false}' "$1" | "$gate"; } # session id -> runs the hook

G=$("$ledger" start gate-task "g"); GD=$("$ledger" -t "$G" path); mkdir -p "$GD/run" "$GD/handoffs"
CNT=$("$ledger" base)/run/gate-sess-A.count
echo "running $$ 100" > "$GD/run/w1.status"; echo sess-A > "$GD/run/w1.session"
G2=$("$ledger" start gate-task-2 "g2"); GD2=$("$ledger" -t "$G2" path); mkdir -p "$GD2/run"
echo "running $$ 100" > "$GD2/run/w9.status"; echo sess-A > "$GD2/run/w9.session"

DEVKIT_DEPTH=1 hook sess-A 2>/dev/null; rc=$?
ok "worker (DEVKIT_DEPTH set) is a silent no-op"   '[ $rc -eq 0 ] && [ ! -f "$CNT" ]'
out=$(hook "" 2>&1); rc=$?
ok "empty session_id is a silent no-op"            '[ $rc -eq 0 ] && [ -z "$out" ]'
out=$(hook sess-B 2>&1); rc=$?
ok "another session is unaffected"                 '[ $rc -eq 0 ] && [ -z "$out" ] && [ ! -f "$("$ledger" base)/run/gate-sess-B.count" ]'

out=$(hook sess-A 2>&1 >/dev/null); rc=$?
ok "outstanding worker blocks with exit 2"         '[ $rc -eq 2 ]'
ok "message names the worker and the wait command" 'echo "$out" | grep -q "w1 running" && echo "$out" | grep -q "capped" && echo "$out" | grep -q "reconcile --wait --session sess-A" && echo "$out" | grep -q "accept"'
ok "block counter is 1"                            '[ "$(cat "$CNT")" = 1 ]'
hook sess-A >/dev/null 2>&1; hook sess-A >/dev/null 2>&1; rc=$?
ok "third block still exits 2"                     '[ $rc -eq 2 ] && [ "$(cat "$CNT")" = 3 ]'
out=$(hook sess-A 2>&1 >/dev/null); rc=$?
ok "fourth stop fails open (exit 0) with a warning" '[ $rc -eq 0 ] && echo "$out" | grep -qi "fail-open"'
ok "fail-open writes a gate row to the task"       'cut -f2,3 "$GD/ledger.tsv" | grep -qx "gate[[:space:]]fail-open"'
ok "fail-open writes a gate row to every task with outstanding workers" 'cut -f2,3 "$GD2/ledger.tsv" | grep -qx "gate[[:space:]]fail-open"'
rm -rf "$GD2/run"
ok "fail-open resets the counter"                  '[ ! -f "$CNT" ] || [ "$(cat "$CNT")" = 0 ]'

hook sess-A >/dev/null 2>&1; echo "done 0 100" > "$GD/run/w1.status"; "$ledger" -t "$G" spawn "w1 done" cli=fake "" done
"$ledger" -t "$G" accept "w1 accepted" "checked" "" pass
out=$(hook sess-A 2>&1); rc=$?
ok "accepted worker clears the gate (exit 0)"      '[ $rc -eq 0 ] && [ -z "$out" ]'
ok "clearing resets the block counter"             '[ ! -f "$CNT" ] || [ "$(cat "$CNT")" = 0 ]'

# input and environment problems fail open (exit 0), never block
out=$(echo 'not json' | "$gate" 2>&1); rc=$?
ok "malformed input is a silent no-op"             '[ $rc -eq 0 ] && [ -z "$out" ]'
out=$(echo '{"session_id":"sess-A' | "$gate" 2>&1); rc=$?
ok "truncated JSON is a silent no-op"              '[ $rc -eq 0 ] && [ -z "$out" ]'
echo "running $$ 100" > "$GD/run/w1.status"
out=$(hook '../../x' 2>&1); rc=$?
ok "session_id with odd characters is a no-op"     '[ $rc -eq 0 ] && [ -z "$out" ] && [ ! -e "$t/x.count" ]'
fake="$t/fake"; mkdir -p "$fake"; cp "$gate" "$fake/stop-gate"
out=$(echo '{"session_id":"sess-A"}' | "$fake/stop-gate" 2>&1); rc=$?
ok "no executable ledger beside the script fails open" '[ $rc -eq 0 ] && echo "$out" | grep -qi "fail-open"'
mkdir -p "$t/linked"; ln -s "$gate" "$t/linked/stop-gate"
out=$(echo '{"session_id":"sess-A"}' | "$t/linked/stop-gate" 2>&1); rc=$?
ok "a symlinked script fails open, not an endless block" '[ $rc -eq 0 ] && echo "$out" | grep -qi "fail-open"'
printf '#!/bin/sh\n[ "$1" = base ] && echo "%s" && exit 0\nexit 0\n' "$t/fakebase" > "$fake/ledger"; chmod +x "$fake/ledger"
printf '#!/bin/sh\necho boom >&2\nexit 2\n' > "$fake/reconcile"; chmod +x "$fake/reconcile"
out=$(echo '{"session_id":"sess-A"}' | "$fake/stop-gate" 2>&1); rc=$?
ok "reconcile failing (exit 2) fails open with the reason" '[ $rc -eq 0 ] && echo "$out" | grep -qi "fail-open" && echo "$out" | grep -q "boom"'
ok "reconcile failure leaves no block counter"     '[ ! -e "$t/fakebase/run/gate-sess-A.count" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
