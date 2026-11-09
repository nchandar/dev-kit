#!/usr/bin/env bash
# Tests for bin/reconcile. Usage: tests/reconcile.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
here=$(cd "$(dirname "$0")/.." && pwd); rec="$here/bin/reconcile"; ledger="$here/bin/ledger"; verify="$here/bin/verify"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
# a verify-gate pass row for the current tree, the shape bin/verify writes (scratch repos cannot run the real gate)
gate_pass() { local d; d=$("$ledger" -t "$1" path) && mkdir -p "$d/runs" && echo gate > "$d/runs/gate.log" \
  && "$ledger" -t "$1" gate-row full "tree $("$verify" tree) 1s" "$d/runs/gate.log" pass; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
unset DEVKIT_DIR DEVKIT_TASK
export DEVKIT_LEARN_DIR="$t/empty-inbox"  # never read the real inbox

out=$("$rec"); rc=$?
ok "no tasks: friendly message, exit 0"    '[ $rc -eq 0 ] && echo "$out" | grep -qi "no tasks"'

A=$("$ledger" start feat-a "x"); B=$("$ledger" start bug-b "y"); C=$("$ledger" start old-c "z")
"$ledger" -t "$A" plan "split into 3 slices" why
gate_pass "$C"; "$ledger" -t "$C" done "shipped"
out=$("$rec")
ok "lists open tasks only, one line each"  '[ "$(echo "$out" | wc -l)" -eq 2 ] && echo "$out" | grep -q "$A" && echo "$out" | grep -q "$B" && ! echo "$out" | grep -q "$C"'
ok "line shows last phase and decision"   'echo "$out" | grep "$A" | grep -q "plan: split into 3 slices"'
ok "--all includes finished tasks"         '"$rec" --all | grep -q "$C"'
ok "--all marks finished as done"          '"$rec" --all | grep "$C" | grep -q "done"'

"$ledger" -t "$A" next "run slice s2: bin/run tests/s2" "resume point"
D=$(.devkit/../bin/ledger base 2>/dev/null || "$ledger" base)/tasks/$A
mkdir -p "$D/run" "$D/handoffs"
echo "running 999999 100" > "$D/run/dead.status"
echo "running $$ 100" > "$D/run/live.status"
echo "done 0 100" > "$D/run/fin.status"; echo r > "$D/handoffs/fin.md"
out=$("$rec" "$A")
ok "detail shows the next row first"       '[ "$(echo "$out" | sed -n 1,3p | grep -c "run slice s2")" -ge 1 ]'
ok "detail: dead pid reported killed"      'echo "$out" | grep "dead" | grep -q killed'
ok "detail: live pid reported running"     'echo "$out" | grep "live" | grep -q running'
ok "detail: finished worker shows handoff" 'echo "$out" | grep "fin" | grep -q done'
ok "list line counts running/killed"       '"$rec" | grep "$A" | grep -q "1 running" && "$rec" | grep "$A" | grep -q "1 killed"'
"$rec" nosuch >/dev/null 2>&1; rc=$?
ok "unknown task exits 2"                  '[ $rc -eq 2 ]'
# --- state.md and the learning inbox are visible from reconcile
export DEVKIT_LEARN_DIR="$t/inbox"
S="$("$ledger" base)/tasks/$A/state.md"
cat > "$S" <<'S2'
# state
goal: see spec.md

## Findings
- the digest is read first (handoffs/a.md:1)

## Decisions

## Direction
two tier digest, then recipes

## Open questions
- where do recipes live?
- who approves library edits?

## Learnings
- [ ] retry with backoff | scope: general | ref: handoffs/a.md:3
- [~] build flag Y | scope: recipe | ref: runs/001.log
S2
out=$("$rec" "$A")
ok "detail shows the direction"                    'echo "$out" | grep -q "direction: two tier digest, then recipes"'
ok "detail lists open questions"                   'echo "$out" | grep -q "where do recipes live"'
ok "detail counts open and queued learnings"       'echo "$out" | grep -q "learnings: 1 open, 1 queued"'
printf -- '- a bullet with no pointer at all\n' >> "$S"; sed -i.bak 's/^## Decisions$/## Decisions\n- no pointer here/' "$S"; rm "$S.bak"
out=$("$rec" "$A")
ok "detail warns when state.md breaks the rules"   'echo "$out" | grep -q "state: .* issue"'
mkdir -p "$t/inbox"; printf 'time\tproject\ttask\tscope\tlesson\tref\tfrom\nT\tp\tt\tgeneral\tl\tr\tf\n' > "$t/inbox/inbox.tsv"
out=$("$rec")
ok "list footer shows queued learnings"            'echo "$out" | tail -1 | grep -q "learnings queued: 1"'

# --- --gate: outstanding workers for the parent Stop hook
G=$("$ledger" start gate-task "g"); GD=$("$ledger" -t "$G" path); mkdir -p "$GD/run" "$GD/handoffs"
export DEVKIT_TASK=$G
out=$("$rec" --gate); rc=$?
ok "gate: no workers is clear (exit 0)"               '[ $rc -eq 0 ] && [ -z "$out" ]'
echo "running $$ 100" > "$GD/run/w1.status"
out=$("$rec" --gate); rc=$?
ok "gate: a live running worker blocks (exit 1)"      '[ $rc -eq 1 ] && echo "$out" | grep -q "w1 running"'
echo "done 0 100" > "$GD/run/w1.status"; echo r > "$GD/handoffs/w1.md"; "$ledger" -t "$G" spawn "w1 done" cli=fake "" done
out=$("$rec" --gate); rc=$?
ok "gate: finished but unaccepted blocks"             '[ $rc -eq 1 ] && echo "$out" | grep -q "w1 done, unaccepted"'
"$ledger" -t "$G" accept "w1 accepted" "evidence checked" "" pass
out=$("$rec" --gate); rc=$?
ok "gate: an accept row clears the worker"            '[ $rc -eq 0 ] && [ -z "$out" ]'
"$ledger" -t "$G" spawn "w1 done" "respawned" "" done
ok "gate: a respawned id is outstanding again"        '"$rec" --gate | grep -q "w1 done, unaccepted"'
"$ledger" -t "$G" accept "w1 rejected" "no evidence" "" fail
ok "gate: a reject row also clears (parent decided)"  '"$rec" --gate >/dev/null'
echo "killed 143 100" > "$GD/run/w2.status"; "$ledger" -t "$G" spawn "w2 killed" interrupted "" killed
ok "gate: killed worker is outstanding until decided" '"$rec" --gate | grep -q "w2 killed, unaccepted"'
echo "running 999999 100" > "$GD/run/w3.status"; "$ledger" -t "$G" accept "w2 rejected" dead "" fail
out=$("$rec" --gate)
ok "gate: dead pid reads killed, not running"         'echo "$out" | grep -q "w3 killed, unaccepted" && ! echo "$out" | grep -q "w3 running"'
# --session scopes by run/<id>.session across open tasks
rm -f "$GD"/run/*.status; echo "running $$ 100" > "$GD/run/ws.status"; echo sess-A > "$GD/run/ws.session"
unset DEVKIT_TASK
ok "gate: --session matches its own worker"          '"$rec" --gate --session sess-A | grep -q "ws running"'
"$rec" --gate --session sess-B >/dev/null; rc=$?
ok "gate: another session sees nothing"               '[ $rc -eq 0 ]'
"$rec" --gate >/dev/null 2>&1; rc=$?
ok "gate: no task and no session is a usage error"    '[ $rc -eq 2 ]'
rm -f "$GD"/run/*; unset DEVKIT_TASK

# --- regression (PR #8): a closed task's LIVE running worker is still gated under --session
echo "running $$ 100" > "$GD/run/wc.status"; echo sess-A > "$GD/run/wc.session"
ok "gate: live running worker blocks on an open task"  '"$rec" --gate --session sess-A | grep -q "wc running"'
echo "done 0 100" > "$GD/run/wc.status"; "$ledger" -t "$G" spawn "wc done" cli=fake "" done
ok "gate: finished unaccepted blocks on an open task"  '"$rec" --gate --session sess-A | grep -q "wc done, unaccepted"'
gate_pass "$G"; "$ledger" -t "$G" done "shipped"
out=$("$rec" --gate --session sess-A); rc=$?
ok "gate: closed task, finished unaccepted stays clear" '[ $rc -eq 0 ] && [ -z "$out" ]'
echo "running $$ 100" > "$GD/run/wc.status"
out=$("$rec" --gate --session sess-A); rc=$?
ok "gate: closed task, live running worker blocks"     '[ $rc -eq 1 ] && echo "$out" | grep -q "wc running"'
echo "running 999999 100" > "$GD/run/wc.status"
out=$("$rec" --gate --session sess-A); rc=$?
ok "gate: closed task, dead pid reads killed, not gated" '[ $rc -eq 0 ] && [ -z "$out" ]'
rm -f "$GD"/run/*

# --- --wait: block until no worker in scope is running, then report what is unaccepted
export DEVKIT_TASK=$G DEVKIT_GATE_POLL=1
# SECONDS has 1 s granularity: a fast call straddling a boundary reads 1 under load; the hang case is the 100 s cap
SECONDS=0; out=$("$rec" --wait); rc=$?
ok "wait: returns at once when clear"                 '[ $rc -eq 0 ] && [ -z "$out" ] && [ $SECONDS -lt 2 ]'
"$ledger" -t "$G" spawn "w4 done" cli=fake "" done; "$ledger" -t "$G" accept "w4 accepted" ok "" pass
echo "running $$ 100" > "$GD/run/w4.status"
(sleep 2; echo "done 0 100" > "$GD/run/w4.status") & # sleep-ok: flips the status while --wait polls
SECONDS=0; out=$("$rec" --wait); rc=$?; el=$SECONDS
ok "wait: blocks until the running worker finishes"   '[ $rc -eq 0 ] && [ -z "$out" ] && [ $el -ge 1 ]'
"$ledger" -t "$G" spawn "w5 done" cli=fake "" done
echo "running $$ 100" > "$GD/run/w5.status"
(sleep 2; echo "done 0 100" > "$GD/run/w5.status") & # sleep-ok: flips the status while --wait polls
out=$("$rec" --wait); rc=$?
ok "wait: lists a finished but unaccepted worker"     '[ $rc -eq 1 ] && echo "$out" | grep -q "w5 done, unaccepted"'
echo "running $$ 100" > "$GD/run/w5.status"
SECONDS=0; out=$(DEVKIT_WAIT=2 "$rec" --wait 2>&1); rc=$?; el=$SECONDS
ok "wait: times out with exit 1 and says so"          '[ $rc -eq 1 ] && echo "$out" | grep -q "timed out" && echo "$out" | grep -q "w5 running" && [ $el -le 4 ]'
unset DEVKIT_TASK; echo "running $$ 100" > "$GD/run/ws.status"; echo sess-A > "$GD/run/ws.session"
out=$("$rec" --wait --session sess-B); rc=$?
ok "wait: --session scopes like gate"                 '[ $rc -eq 0 ] && [ -z "$out" ]'
"$rec" --wait >/dev/null 2>&1; rc=$?
ok "wait: no task and no session is a usage error"    '[ $rc -eq 2 ]'
rm -f "$GD"/run/*

# --- knob validation, -t scope, --session arguments, half-written status
export DEVKIT_TASK=$G
for kv in DEVKIT_WAIT=5m DEVKIT_GATE_POLL=x; do
  out=$(env "$kv" "$rec" --wait 2>&1); rc=$?
  ok "wait: bad $kv is a usage error (exit 2)"       '[ $rc -eq 2 ] && echo "$out" | grep -q "whole number"'
done
unset DEVKIT_TASK
echo "running $$ 100" > "$GD/run/wt.status"
out=$("$rec" -t "$G" --gate); rc=$?
ok "gate: -t before --gate picks the task"            '[ $rc -eq 1 ] && echo "$out" | grep -q "wt running"'
out=$("$rec" --gate -t "$G"); rc=$?
ok "gate: -t after --gate picks the task"             '[ $rc -eq 1 ] && echo "$out" | grep -q "wt running"'
"$rec" --gate -t nope >/dev/null 2>&1; rc=$?
ok "gate: -t with an unknown task is exit 2"          '[ $rc -eq 2 ]'
"$rec" --gate -t >/dev/null 2>&1; rc=$?
ok "gate: -t without an id is exit 2"                 '[ $rc -eq 2 ]'
echo "done 0 100" > "$GD/run/wt.status"; "$ledger" -t "$G" spawn "wt done" cli=fake "" done
out=$(DEVKIT_GATE_POLL=1 "$rec" --wait -t "$G"); rc=$?
ok "wait: -t picks the task"                          '[ $rc -eq 1 ] && echo "$out" | grep -q "wt done, unaccepted"'
for m in --gate --wait; do
  "$rec" $m --session >/dev/null 2>&1; rc=$?
  ok "$m: --session without an argument is exit 2"    '[ $rc -eq 2 ]'
  "$rec" $m --session "" >/dev/null 2>&1; rc=$?
  ok "$m: --session with an empty argument is exit 2" '[ $rc -eq 2 ]'
done
: > "$GD/run/half.status"; "$ledger" -t "$G" accept "wt accepted" ok "" pass
out=$("$rec" --gate -t "$G"); rc=$?
ok "gate: an empty (half-written) status file is skipped" '[ $rc -eq 0 ] && [ -z "$out" ]'
rm -f "$GD"/run/*

# --- regression: a prune row is post-close housekeeping, never task state
P=$("$ledger" start prune-closed "p"); PD=$("$ledger" -t "$P" path); mkdir -p "$PD/run" "$PD/handoffs"
"$ledger" -t "$P" plan "s1 done" why
echo sess-P > "$PD/run/pw.session"
echo "done 0 100" > "$PD/run/pw.status"; echo r > "$PD/handoffs/pw.md"
"$ledger" -t "$P" spawn "pw done" cli=fake "" done
gate_pass "$P"; "$ledger" -t "$P" done "shipped"
"$ledger" -t "$P" prune "w1 pruned" "worktree and branch removed" "/tmp/w1" pruned
out=$("$rec")
ok "prune: a pruned closed task is not listed as open"  '! echo "$out" | grep -q "$P"'
out=$("$rec" --all)
ok "prune: --all still shows the closed task as done"   'echo "$out" | grep "$P" | grep -q " done "'
out=$("$rec" --gate --session sess-P); rc=$?
ok "prune: closed task, finished unaccepted stays clear" '[ $rc -eq 0 ] && [ -z "$out" ]'
echo "running $$ 100" > "$PD/run/pw.status"
out=$("$rec" --gate --session sess-P); rc=$?
ok "prune: closed task, live running worker still gates" '[ $rc -eq 1 ] && echo "$out" | grep -q "pw running"'
Q=$("$ledger" start prune-open "q")
"$ledger" -t "$Q" plan "s1 open" why
"$ledger" -t "$Q" prune "w2 pruned" "worktree removed" "/tmp/w2" pruned
out=$("$rec")
ok "prune: open task keeps its previous phase as the last one" 'echo "$out" | grep "$Q" | grep -q "plan: s1 open"'

# --- session pointer fallback for --gate task scope (--session is unchanged)
RS=sess-rec; RG=$(CLAUDE_CODE_SESSION_ID=$RS "$ledger" start ptr-gate "x"); RGD=$("$ledger" -t "$RG" path); mkdir -p "$RGD/run"
echo "running $$ 100" > "$RGD/run/rp.status"
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$RS "$rec" --gate); rc=$?
ok "no DEVKIT_TASK: the pointer supplies the task"  '[ $rc -eq 1 ] && echo "$out" | grep -q "rp running"'
EG=$(CLAUDE_CODE_SESSION_ID=$RS "$ledger" start explicit-gate "x"); EGD=$("$ledger" -t "$EG" path); mkdir -p "$EGD/run"
echo "running $$ 100" > "$EGD/run/eg.status"
out=$(DEVKIT_TASK=$EG CLAUDE_CODE_SESSION_ID=$RS "$rec" --gate); rc=$?
ok "DEVKIT_TASK wins over the pointer"             '[ $rc -eq 1 ] && echo "$out" | grep -q "eg running" && ! echo "$out" | grep -q "rp running"'
out=$(CLAUDE_CODE_SESSION_ID=$RS "$rec" -t "$EG" --gate); rc=$?
ok "-t wins over the pointer"                      '[ $rc -eq 1 ] && echo "$out" | grep -q "eg running" && ! echo "$out" | grep -q "rp running"'
env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$rec" --gate >/dev/null 2>"$t/rec-notask.err"; rc=$?
ok "no pointer: the existing gate usage error"     '[ $rc -eq 2 ] && grep -q "reconcile --gate: pass --session S, -t ID or set DEVKIT_TASK" "$t/rec-notask.err"'
gate_pass "$EG"; "$ledger" -t "$EG" done "closed" >/dev/null 2>&1
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$RS "$rec" --gate 2>&1); rc=$?
ok "closed pointer: the clear error names the task" '[ $rc -eq 2 ] && echo "$out" | grep -q "last task $EG is closed (or gone)"'
rm -f "$RGD"/run/* "$EGD"/run/*

# --session S is unchanged by a pointer; plain list ignores it
SS=sess-rec-s; SA=$(CLAUDE_CODE_SESSION_ID=$SS "$ledger" start sess-a "x"); SAD=$("$ledger" -t "$SA" path); mkdir -p "$SAD/run"
echo "running $$ 100" > "$SAD/run/sw.status"; echo "$SS" > "$SAD/run/sw.session"
EO=$(CLAUDE_CODE_SESSION_ID=$SS "$ledger" start sess-other "x"); EOD=$("$ledger" -t "$EO" path); mkdir -p "$EOD/run"
echo "running $$ 100" > "$EOD/run/so.status"; echo "other-session" > "$EOD/run/so.session"
out_with=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SS "$rec" --gate --session "$SS"); rc_with=$?
out_without=$(env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$rec" --gate --session "$SS"); rc_without=$?
ok "--session S: same output and exit with and without a pointer" '[ $rc_with -eq $rc_without ] && [ "$out_with" = "$out_without" ] && echo "$out_with" | grep -q "sw running"'
ok "--session S: the pointer's task does not widen the scope"     '! echo "$out_with" | grep -q "so running"'
out_with=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SS "$rec" --gate --session none-here); rc_with=$?
ok "--session of an unknown session stays clear despite a pointer" '[ $rc_with -eq 0 ] && [ -z "$out_with" ]'
l_with=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SS "$rec"); l_without=$(env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$rec")
ok "plain reconcile (list) is unaffected by a pointer"            '[ "$l_with" = "$l_without" ] && echo "$l_with" | grep -q "$SA"'
rm -f "$SAD"/run/* "$EOD"/run/*

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
