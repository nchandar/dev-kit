#!/usr/bin/env bash
# Tests for bin/stop-gate (Claude Code Stop hook adapter). Usage: tests/stop-gate.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
unset DEVKIT_STOP_GATE_FORMAT  # assert the default format unless a case asks for exit2
here=$(cd "$(dirname "$0")/.." && pwd); gate="$here/bin/stop-gate"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
unset DEVKIT_DIR DEVKIT_TASK
hook() { printf '{"session_id":"%s","stop_hook_active":false}' "$1" | "$gate"; } # session id -> runs the hook
HERR=$t/h.err
runhook() { HOUT=$(printf '{"session_id":"%s","stop_hook_active":false}' "$1" | "$gate" 2>"$HERR"); HRC=$?; }
runhook_exit2() { HOUT=$(printf '{"session_id":"%s","stop_hook_active":false}' "$1" | DEVKIT_STOP_GATE_FORMAT=exit2 "$gate" 2>"$HERR"); HRC=$?; }
text() { # stdin: hook JSON -> additionalContext
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'
  else jq -r '.hookSpecificOutput.additionalContext'; fi; }
validjson() { # stdin: one JSON object carrying hookEventName Stop and a non-empty additionalContext
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; h=json.load(sys.stdin)["hookSpecificOutput"]; raise SystemExit(0 if h["hookEventName"]=="Stop" and isinstance(h["additionalContext"],str) and h["additionalContext"] else 1)'
  else jq -e '.hookSpecificOutput.hookEventName=="Stop" and ((.hookSpecificOutput.additionalContext|length)>0)' >/dev/null; fi; }
alarm() { grep -Eqi '(^|[^[:alnum:]_])(error|failed)([^[:alnum:]_]|$)'; } # calm text: no error/failed word

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

runhook sess-A
ok "outstanding worker keeps the turn with exit 0" '[ $HRC -eq 0 ]'
ok "status goes to stdout, stderr stays empty"     '[ -n "$HOUT" ] && [ ! -s "$HERR" ]'
ok "stdout is one JSON object, hookEventName Stop" 'printf "%s" "$HOUT" | validjson'
TXT=$(printf '%s' "$HOUT" | text 2>/dev/null); trc=$?
ok "additionalContext decodes"                     '[ $trc -eq 0 ] && [ -n "$TXT" ]'
ok "headline first, then the next step on line two" '[ "$(printf %s "$TXT" | sed -n 2p | cut -c1-6)" = "Next: " ] && printf %s "$TXT" | sed -n 1p | grep -q "^Waiting on .* to report back\."'
ok "next step names the wait command"              'echo "$TXT" | grep -q "bin/reconcile --wait --session sess-A" && echo "$TXT" | grep -q "capped" && echo "$TXT" | grep -q "accept"'
ok "status lists each pending worker with its task" 'echo "$TXT" | grep -q "w1: working" && echo "$TXT" | grep -q "task=gate-task" && echo "$TXT" | grep -q "w9: working" && echo "$TXT" | grep -q "task=gate-task-2"'
ok "count reads as a check, not a score"           'echo "$TXT" | grep -q "check 1 of 3" && ! echo "$TXT" | grep -q "1/3"'
ok "status text has no error or failed"            '! echo "$TXT" | alarm'
ok "block counter is 1"                            '[ "$(cat "$CNT")" = 1 ]'
runhook sess-A; runhook sess-A
ok "third check still keeps the turn going"        '[ $HRC -eq 0 ] && [ "$(cat "$CNT")" = 3 ]'
ok "third check still carries the status JSON"     'printf "%s" "$HOUT" | validjson'
runhook sess-A
ok "fourth stop lets the turn end (exit 0) with a calm note" '[ $HRC -eq 0 ] && grep -q "Letting the turn end after 3 checks" "$HERR"'
ok "fail-open prints no status JSON"               '[ -z "$HOUT" ]'
ok "fail-open warning has no error or failed"      '! alarm < "$HERR"'
ok "fail-open writes a gate row to the task"       'cut -f2,3 "$GD/ledger.tsv" | grep -qx "gate[[:space:]]fail-open"'
ok "fail-open writes a gate row to every task with outstanding workers" 'cut -f2,3 "$GD2/ledger.tsv" | grep -qx "gate[[:space:]]fail-open"'
rm -rf "$GD2/run"
ok "fail-open resets the counter"                  '[ ! -f "$CNT" ] || [ "$(cat "$CNT")" = 0 ]'
runhook_exit2 sess-A
ok "escape hatch: exit 2 keeps the old block"      '[ $HRC -eq 2 ] && [ "$(cat "$CNT")" = 1 ]'
ok "escape hatch: text goes to stderr, not stdout" '[ -z "$HOUT" ] && [ -s "$HERR" ]'
out=$(cat "$HERR")
ok "escape hatch: message names the worker and the wait command" 'echo "$out" | grep -q "w1: working" && echo "$out" | grep -q "capped" && echo "$out" | grep -q "reconcile --wait --session sess-A" && echo "$out" | grep -q "accept"'

hook sess-A >/dev/null 2>&1; echo "done 0 100" > "$GD/run/w1.status"; "$ledger" -t "$G" spawn "w1 done" cli=fake "" done
"$ledger" -t "$G" accept "w1 accepted" "checked" "" pass
out=$(hook sess-A 2>&1); rc=$?
ok "accepted worker clears the gate (exit 0)"      '[ $rc -eq 0 ] && [ -z "$out" ]'
ok "clearing resets the block counter"             '[ ! -f "$CNT" ] || [ "$(cat "$CNT")" = 0 ]'

# a worker whose exit state is "failed" still reads calmly ("ended"), never "failed"
echo "failed $$ 100" > "$GD/run/w1.status"; "$ledger" -t "$G" spawn "w1 ended" cli=fake "" failed
runhook sess-A
TXT=$(printf '%s' "$HOUT" | text 2>/dev/null)
ok "a failed worker reads as ended"                '[ $HRC -eq 0 ] && echo "$TXT" | grep -q "w1: stopped, awaiting your review" && ! echo "$TXT" | alarm'
ok "the ended-worker hold still emits valid JSON"  'printf "%s" "$HOUT" | validjson'
"$ledger" -t "$G" accept "w1 accepted" "checked" "" pass
runhook sess-A
ok "accept after the ended state clears the gate"  '[ $HRC -eq 0 ] && [ -z "$HOUT" ] && [ ! -s "$HERR" ]'

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
ok "no executable ledger beside the script fails open" '[ $rc -eq 0 ] && echo "$out" | grep -q "letting the turn end"'
ok "no-ledger fail-open wording is calm"            '! echo "$out" | alarm'
mkdir -p "$t/linked"; ln -s "$gate" "$t/linked/stop-gate"
out=$(echo '{"session_id":"sess-A"}' | "$t/linked/stop-gate" 2>&1); rc=$?
ok "a symlinked script fails open, not an endless block" '[ $rc -eq 0 ] && echo "$out" | grep -q "letting the turn end"'
printf '#!/bin/sh\n[ "$1" = base ] && echo "%s" && exit 0\nexit 0\n' "$t/fakebase" > "$fake/ledger"; chmod +x "$fake/ledger"
printf '#!/bin/sh\necho boom >&2\nexit 2\n' > "$fake/reconcile"; chmod +x "$fake/reconcile"
out=$(echo '{"session_id":"sess-A"}' | "$fake/stop-gate" 2>&1); rc=$?
ok "reconcile failing (exit 2) fails open with the reason" '[ $rc -eq 0 ] && echo "$out" | grep -q "letting the turn end" && echo "$out" | grep -q "boom"'
ok "reconcile-failure wording is calm"              '! echo "$out" | alarm'
ok "reconcile failure leaves no block counter"     '[ ! -e "$t/fakebase/run/gate-sess-A.count" ]'

# quotes, backslashes and control bytes in reconcile output must still make valid JSON
cat > "$fake/reconcile" <<'R'
#!/bin/sh
printf 'w1 running  task=odd"name\\with\\slash\001end\n'
exit 1
R
chmod +x "$fake/reconcile"
out=$(printf '{"session_id":"sess-A"}' | "$fake/stop-gate" 2>"$t/esc.err"); rc=$?
ok "odd task-name bytes still make valid JSON"      '[ $rc -eq 0 ] && [ ! -s "$t/esc.err" ] && printf "%s" "$out" | validjson'
ok "odd task-name bytes survive JSON intact"        'printf "%s" "$out" | text | grep -qF "task=odd\"name\\with\\slashend"'


# calm wording: the status says what is happening, never "stop-gate:", "unaccepted" or "accepted yet"
echo "done $$ 100" > "$GD/run/w1.status"; "$ledger" -t "$G" spawn "w1 done" cli=fake "" done
runhook sess-A
TXT=$(printf %s "$HOUT" | text 2>/dev/null)
ok "all done: headline says ready for your review"  'printf %s "$TXT" | sed -n 1p | grep -q "^1 worker finished and is ready for your review\.$"'
ok "worker line reads finished, awaiting your review" 'echo "$TXT" | grep -q "  w1: finished, awaiting your review  task="'
ok "no stop-gate prefix, no unaccepted, no accepted yet" '! echo "$TXT" | grep -Eqi "stop-gate:|unaccepted|accepted yet"'
ok "check count is a quiet tail line"               'printf %s "$TXT" | tail -1 | grep -q "^(check [0-9] of 3; the turn can end after 3)$"'
"$ledger" -t "$G" accept "w1 accepted" "checked" "" pass
runhook sess-A

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
