#!/usr/bin/env bash
# Tests for bin/ledger (per-task ledgers). Usage: tests/ledger.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
EVID="$t/evidence.log"; : > "$EVID"
cd "$t" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && mkdir -p sub/deep
unset DEVKIT_DIR DEVKIT_LEDGER DEVKIT_LEDGER_MIRROR DEVKIT_TASK DEVKIT_DEPTH
unset CLAUDE_CODE_SESSION_ID
verify="$here/bin/verify"
export VERIFY_TICK=0.1 # watchdog poll resolution: bounds unchanged, the idle wait after an instant run shrinks
# a verify-gate pass row for the current tree, the shape bin/verify writes (scratch repos cannot run the real gate)
gate_pass() { local d; d=$("$ledger" -t "$1" path) && mkdir -p "$d/runs" && echo gate > "$d/runs/gate.log" \
  && "$ledger" -t "$1" gate-row full "tree $("$verify" tree) 1s" "$d/runs/gate.log" pass; }

A=$(cd sub/deep && "$ledger" start fix-login "first look")
ok "start prints a slugged id"              '[[ $A == fix-login-* ]] && [ -d ".devkit/tasks/$A" ]'
before=$(ls .devkit/tasks | wc -l | tr -d ' ')
DEVKIT_DEPTH=1 "$ledger" start sneaky 2>"$t/guard.err"; rc=$?
ok "a worker (DEVKIT_DEPTH>0) cannot start a task"          '[ $rc -eq 3 ] && grep -q "worker" "$t/guard.err" && [ "$(ls .devkit/tasks | wc -l | tr -d " ")" = "$before" ]'
DEVKIT_DEPTH=abc "$ledger" start sneaky-junk 2>"$t/guard-junk.err"; rc=$?
ok "junk DEVKIT_DEPTH (abc) cannot start a task"   '[ $rc -eq 3 ] && grep -q "worker" "$t/guard-junk.err" && [ "$(ls .devkit/tasks | wc -l | tr -d " ")" = "$before" ]'
B00=$(DEVKIT_DEPTH=00 "$ledger" start double-zero 2>/dev/null); rc=$?
ok "depth 00 (zero-padded main agent) can start a task" '[[ $B00 == double-zero-* ]] && [ $rc -eq 0 ]'
G=$("$ledger" start worker-log 2>/dev/null)
DEVKIT_DEPTH=2 "$ledger" -t "$G" note "from a worker" "still allowed" >/dev/null 2>&1; rc=$?
ok "a worker can still log to its own task"                  '[ $rc -eq 0 ] && grep -q "from a worker" ".devkit/tasks/$G/ledger.tsv"'
B0=$(DEVKIT_DEPTH=0 "$ledger" start main-agent 2>/dev/null)
ok "depth 0 (the main agent) can start a task"               '[[ $B0 == main-agent-* ]]'
ok "start writes header + start row"        '[ "$(wc -l < .devkit/tasks/$A/ledger.tsv)" -eq 2 ] && sed -n 1p .devkit/tasks/$A/ledger.tsv | grep -q "^time	phase	decision	reason	evidence	result$" && sed -n 2p .devkit/tasks/$A/ledger.tsv | awk -F"\t" "\$2==\"start\"{f=1} END{exit !f}"'
B=$("$ledger" start fix-login "second session, same slug")
ok "same slug twice gets distinct ids"      '[ "$A" != "$B" ] && [ -d ".devkit/tasks/$B" ]'

"$ledger" plan "split" "two areas" 2>/dev/null; rc=$?
ok "no task: refuses (exit 2), writes nothing shared" '[ $rc -eq 2 ] && [ ! -e .devkit/ledger.tsv ]'
"$ledger" -t nosuch plan a b 2>/dev/null; rc=$?
ok "unknown task exits 2"                   '[ $rc -eq 2 ]'

"$ledger" -t "$A" plan "split work" "two areas" "plan.json" ok
DEVKIT_TASK=$B "$ledger" plan "other work" "different task"
ok "-t appends to that task only"           'grep -q "split work" .devkit/tasks/$A/ledger.tsv && ! grep -q "split work" .devkit/tasks/$B/ledger.tsv'
ok "DEVKIT_TASK env works, isolated"       'grep -q "other work" .devkit/tasks/$B/ledger.tsv && ! grep -q "other work" .devkit/tasks/$A/ledger.tsv'

(cd sub/deep && "$ledger" -t "$A" plan "from subdir" r)
ok "subdir resolves to repo root"           'grep -q "from subdir" .devkit/tasks/$A/ledger.tsv && [ ! -d sub/deep/.devkit ]'
git worktree add -q "$t/wt1" -b wtb 2>/dev/null
(cd "$t/wt1" && "$ledger" -t "$A" plan "from worktree" r)
ok "linked worktree shares main .devkit"   'grep -q "from worktree" .devkit/tasks/$A/ledger.tsv && [ ! -d "$t/wt1/.devkit" ]'
ok "path prints the task dir"               '[ "$("$ledger" path -t "$A")" = "$t/.devkit/tasks/$A" ]'
ok "base prints the .devkit dir"           '[ "$("$ledger" base)" = "$t/.devkit" ]'

"$ledger" -t "$A" verify "a | b	tab" "multi
line" "" pass
ok "tabs and newlines flattened, 6 columns" '[ "$(tail -1 .devkit/tasks/$A/ledger.tsv | awk -F"\t" "{print NF}")" -eq 6 ] && tail -1 .devkit/tasks/$A/ledger.tsv | grep -q "a | b tab"'
"$ledger" -t "$A" big "$(head -c 3000 /dev/zero | tr '\0' z)" r
ok "oversized cell truncated (<2000B row)"  '[ "$(tail -1 .devkit/tasks/$A/ledger.tsv | wc -c)" -lt 2000 ]'

C=$("$ledger" start parallel "x")
for w in 1 2 3 4 5 6 7 8; do ( for i in $(seq 1 25); do "$ledger" -t "$C" work "w$w-$i" "concurrent"; done ) & done; wait
ok "8 parallel writers: 200 intact rows"    '[ "$(awk -F"\t" "\$2==\"work\"" .devkit/tasks/$C/ledger.tsv | wc -l)" -eq 200 ] && [ "$(awk -F"\t" "NF!=6" .devkit/tasks/$C/ledger.tsv | wc -l)" -eq 0 ]'

gate_pass "$C"
"$ledger" -t "$C" done "all finished"
ok "done writes phase=done"                 'tail -1 .devkit/tasks/$C/ledger.tsv | awk -F"\t" "\$2==\"done\"{f=1} END{exit !f}"'

# --- slice A: a worker must not close the shared task
WD=$("$ledger" start worker-done "x")
rows=$(wc -l < .devkit/tasks/$WD/ledger.tsv)
DEVKIT_DEPTH=1 "$ledger" -t "$WD" done "nope" 2>"$t/done-worker.err"; rc=$?
ok "a worker (depth 1) cannot close a task"  '[ $rc -eq 3 ] && grep -q "worker" "$t/done-worker.err" && grep -q "handoff" "$t/done-worker.err" && [ "$(wc -l < .devkit/tasks/$WD/ledger.tsv)" = "$rows" ]'
DEVKIT_DEPTH=abc "$ledger" -t "$WD" done "nope" 2>"$t/done-junk.err"; rc=$?
ok "junk DEVKIT_DEPTH (abc) cannot close a task" '[ $rc -eq 3 ] && grep -q "worker" "$t/done-junk.err" && [ "$(wc -l < .devkit/tasks/$WD/ledger.tsv)" = "$rows" ]'
DEVKIT_DEPTH=08 "$ledger" -t "$WD" done "nope" 2>"$t/done-08.err"; rc=$?
ok "depth 08 cannot close a task (no arithmetic error)" '[ $rc -eq 3 ] && grep -q "worker" "$t/done-08.err" && [ "$(wc -l < .devkit/tasks/$WD/ledger.tsv)" = "$rows" ]'
gate_pass "$WD"
DEVKIT_DEPTH=0 "$ledger" -t "$WD" done "main agent" 2>/dev/null; rc=$?
ok "depth 0 can close a task"                '[ $rc -eq 0 ] && tail -1 .devkit/tasks/$WD/ledger.tsv | awk -F"\t" "\$2==\"done\"{f=1} END{exit !f}"'

M="$t/mirror.out"; DEVKIT_LEDGER_MIRROR="echo \"\$1\" >> $M" "$ledger" -t "$A" ph2 dec2 why2
for i in $(seq 1 50); do grep -q ph2 "$M" 2>/dev/null && break; sleep 0.1; done # sleep-ok: bounded poll, mirror is detached
ok "mirror runs with row text as \$1"       'grep -q "ph2" "$M"'
DEVKIT_LEDGER_MIRROR='exit 9' "$ledger" -t "$A" a b c; rc=$?
ok "failing mirror does not fail ledger"    '[ $rc -eq 0 ] && awk -F"\t" "\$2==\"a\" && \$3==\"b\"{f=1} END{exit !f}" .devkit/tasks/$A/ledger.tsv'
"$ledger" -t "$A" onlytwo 2>/dev/null; rc=$?
ok "too few args exits 2"                   '[ $rc -eq 2 ]'
# --- local-only: .devkit never shows up in git status, and state.md starts from a template
G=$(mktemp -d); ( cd "$G" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i )
LA=$(cd "$G" && "$ledger" start local-test "x")
ok "start keeps .devkit out of git status"      '[ -z "$(git -C "$G" status --porcelain)" ]'
ok "exclude holds .devkit/ exactly once"        '[ "$(grep -cxF ".devkit/" "$G/.git/info/exclude")" -eq 1 ]'
( cd "$G" && "$ledger" start again "y" >/dev/null )
ok "a second start adds no duplicate exclude"    '[ "$(grep -cxF ".devkit/" "$G/.git/info/exclude")" -eq 1 ]'
ok "start creates state.md from the template"    'grep -q "^## Findings" "$G/.devkit/tasks/$LA/state.md" && grep -q "^## Learnings" "$G/.devkit/tasks/$LA/state.md" && ! grep -q "^## Next" "$G/.devkit/tasks/$LA/state.md"'
ok "state.md does not copy the ledger start row" '! grep -q "local-test" "$G/.devkit/tasks/$LA/state.md"'
W=$(mktemp -d); ( cd "$G" && git worktree add -q "$W/wt" -b wtb2 2>/dev/null ); ( cd "$W/wt" && "$ledger" start from-wt "z" >/dev/null )
ok "start from a linked worktree is clean too"   '[ -z "$(git -C "$G" status --porcelain)" ] && [ -z "$(git -C "$W/wt" status --porcelain)" ]'
N=$(mktemp -d); ( cd "$N" && "$ledger" start nongit "q" >/dev/null ); rc=$?
ok "outside git: no error, no exclude attempted" '[ $rc -eq 0 ] && [ -d "$N/.devkit/tasks" ]'

# --- truncation is visible, not silent
err=$("$ledger" -t "$A" big "$(head -c 500 /dev/zero | tr '\0' z)" r 2>&1 >/dev/null)
ok "a field over 400 chars warns on stderr"        'echo "$err" | grep -qi "truncated"'
err=$("$ledger" -t "$A" small "short" r 2>&1 >/dev/null)
ok "a short field stays silent"                    '[ -z "$err" ]'

# --- hardening fixes (scHard 3, 4, 10)
ro=$(mktemp -d); chmod 555 "$ro"
( DEVKIT_DIR="$ro/newdir" DEVKIT_DEPTH=0 "$ledger" start ro-test >/dev/null 2>"$t/ro.err" ) & rop=$!
p=0; while kill -0 $rop 2>/dev/null && [ $p -lt 40 ]; do sleep 0.1; p=$((p+1)); done # sleep-ok: bounded poll, the 4s cap is the fail-fast budget under test
if kill -0 $rop 2>/dev/null; then kill -9 $rop 2>/dev/null; wait $rop 2>/dev/null; rorc=124; else wait $rop; rorc=$?; fi
ok "unwritable base: start fails fast instead of hanging" '[ $rorc -ne 124 ] && [ $rorc -ne 0 ] && grep -qi "cannot create" "$t/ro.err"'
chmod 755 "$ro"; rm -rf "$ro"
D000=$(DEVKIT_DEPTH=000 "$ledger" start triple-zero 2>/dev/null); rc=$?
ok "depth 000 (zero-padded main agent) can start a task" '[[ $D000 == triple-zero-* ]] && [ $rc -eq 0 ]'
DEVKIT_DEPTH=08 "$ledger" start octal-eight 2>"$t/depth08.err"; rc=$?
ok "depth 08 is a worker (exit 3), not an arithmetic error" '[ $rc -eq 3 ] && grep -q "worker" "$t/depth08.err"'
mkdir -p .devkit/x
"$ledger" -t "../x" plan a b 2>/dev/null; rc=$?
ok "traversal id rejected even when the target exists" '[ $rc -eq 2 ] && [ ! -e .devkit/x/ledger.tsv ]'
rm -rf .devkit/x
"$ledger" -t "a/b" plan a b 2>/dev/null; rc=$?
ok "id containing slash rejected" '[ $rc -eq 2 ]'
err=$("$ledger" -t "$A" 2>&1); rc=$?
ok "usage notes reserved phases" '[ $rc -eq 2 ] && echo "$err" | grep -qi "reserved"'

W=$("$ledger" start wr-fail 2>/dev/null); chmod 444 ".devkit/tasks/$W/ledger.tsv"
"$ledger" -t "$W" p d r >/dev/null 2>&1; rc=$?
ok "failed append exits non-zero" '[ $rc -ne 0 ] || [ "$(id -u)" = 0 ]'
chmod 644 ".devkit/tasks/$W/ledger.tsv"
for bad in . ..; do "$ledger" -t "$bad" p d r >/dev/null 2>&1; rc=$?
  ok "task id '$bad' rejected" '[ $rc -eq 2 ] && [ ! -e .devkit/ledger.tsv ]'; done
S=$(date +%s); DEVKIT_LEDGER_MIRROR='sleep 8' "$ledger" -t "$W" p mirror hang >/dev/null 2>&1; e=$(date +%s) # sleep-ok: simulates a hung mirror
ok "a hung mirror does not hang the ledger call" '[ $((e-S)) -lt 5 ] && grep -q "mirror" ".devkit/tasks/$W/ledger.tsv"' # sleep-ok: simulates a hung mirror

# --- done warns when this task's worker worktrees are left behind
P=$(mktemp -d); ( cd "$P" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i )
PW=$(cd "$P" && "$ledger" start prune-warn "x")
err=$( cd "$P" && "$ledger" -t "$PW" done "no worktrees" 2>&1 >/dev/null ); rc=$?
ok "done with no worker worktrees is silent"        '[ $rc -eq 0 ] && [ -z "$err" ]'
( cd "$P" && git worktree add -q "$P/wt" -b "devkit/$PW-x" 2>/dev/null )
( cd "$P" && gate_pass "$PW" >/dev/null 2>&1 ) # the leftover worktree is a gitlink in the tree: give the gate its row
err=$( cd "$P" && "$ledger" -t "$PW" done "leftovers" 2>&1 >/dev/null ); rc=$?
ok "done warns about 1 leftover worker worktree"    '[ $rc -eq 0 ] && echo "$err" | grep -q "1 worker worktree" && echo "$err" | grep -q "^ledger: .*run: /.*/spawn --prune -t $PW --yes" && sp=$(echo "$err" | sed -n "s/^.*run: //;s/ --prune.*//p") && [ -x "$sp" ]'
ok "done row is still written when it warns"        'tail -1 "$P/.devkit/tasks/$PW/ledger.tsv" | awk -F"\t" "\$2==\"done\" && \$3==\"leftovers\"{f=1} END{exit !f}"'
NG=$(mktemp -d); NGID=$(cd "$NG" && "$ledger" start nongit-warn "x")
err=$( cd "$NG" && "$ledger" -t "$NGID" done "no git" 2>&1 >/dev/null ); rc=$?
ok "done outside a git repo is silent, exit 0"      '[ $rc -eq 0 ] && [ -z "$err" ]'

# --- slice 1: the session pointer and `ledger current`
S1=sess-one; A1=$(CLAUDE_CODE_SESSION_ID=$S1 "$ledger" start ptr-a "x")
ok "start writes this session's pointer with the exact task id" '[ -f ".devkit/run/session-$S1.task" ] && [ "$(cat ".devkit/run/session-$S1.task")" = "$A1" ]'
ok "the pointer is exactly one line and no temp is left"      '[ "$(wc -l < ".devkit/run/session-$S1.task" | tr -d " ")" -eq 1 ] && [ -z "$(ls -1 .devkit/run/*.tmp.* 2>/dev/null)" ]'
out=$(CLAUDE_CODE_SESSION_ID=$S1 "$ledger" current); rc=$?
ok "current prints the open task id and exits 0"              '[ $rc -eq 0 ] && [ "$out" = "$A1" ]'

before=$(ls -1 .devkit/run 2>/dev/null | wc -l | tr -d " ")
N0=$("$ledger" start ptr-none "x")
ok "start without a session id writes no pointer"             '[ -n "$N0" ] && [ "$(ls -1 .devkit/run 2>/dev/null | wc -l | tr -d " ")" = "$before" ]'

n0=$(ls -1 .devkit/run 2>/dev/null | wc -l | tr -d " ")
CLAUDE_CODE_SESSION_ID='../x' "$ledger" start ptr-bad1 >/dev/null 2>&1
CLAUDE_CODE_SESSION_ID='a b' "$ledger" start ptr-bad2 >/dev/null 2>&1
CLAUDE_CODE_SESSION_ID='a/b' "$ledger" start ptr-bad3 >/dev/null 2>&1
CLAUDE_CODE_SESSION_ID='' "$ledger" start ptr-bad4 >/dev/null 2>&1
ok "unsafe session ids (../x, space, slash, empty) write no pointer" '[ "$(ls -1 .devkit/run 2>/dev/null | wc -l | tr -d " ")" = "$n0" ]'
ok "nothing is written outside .devkit/run"                   '[ -z "$(find . -name "session-*.task" ! -path "./.devkit/run/*" -print -quit 2>/dev/null)" ]'
ok "the pointer dir is under .devkit/run and git-ignored"     'case "$t/.devkit/run/session-$S1.task" in "$t"/.devkit/run/*) true;; *) false;; esac && [ -z "$(git status --porcelain -- .devkit)" ]'

out=$(env -u CLAUDE_CODE_SESSION_ID "$ledger" current); rc=$?
ok "current: no session id exits 1 with empty stdout"         '[ $rc -eq 1 ] && [ -z "$out" ]'
out=$(CLAUDE_CODE_SESSION_ID=sess-noptr "$ledger" current); rc=$?
ok "current: no pointer exits 1 with empty stdout"            '[ $rc -eq 1 ] && [ -z "$out" ]'
: > .devkit/run/session-sess-empty.task
out=$(CLAUDE_CODE_SESSION_ID=sess-empty "$ledger" current); rc=$?
ok "current: empty pointer exits 1 with empty stdout"         '[ $rc -eq 1 ] && [ -z "$out" ]'
printf 'no-such-task\n' > .devkit/run/session-sess-garbage.task
out=$(CLAUDE_CODE_SESSION_ID=sess-garbage "$ledger" current); rc=$?
ok "current: garbage pointer exits 1 with empty stdout"       '[ $rc -eq 1 ] && [ -z "$out" ]'
printf '../x\n' > .devkit/run/session-sess-badid.task
out=$(CLAUDE_CODE_SESSION_ID=sess-badid "$ledger" current); rc=$?
ok "current: pointer holding a bad id exits 1"                '[ $rc -eq 1 ] && [ -z "$out" ]'
printf 'a/b\n' > .devkit/run/session-sess-badid2.task
out=$(CLAUDE_CODE_SESSION_ID=sess-badid2 "$ledger" current); rc=$?
ok "current: pointer holding a slash id exits 1"              '[ $rc -eq 1 ] && [ -z "$out" ]'

SC=sess-closed; TC=$(CLAUDE_CODE_SESSION_ID=$SC "$ledger" start ptr-closed)
gate_pass "$TC"
CLAUDE_CODE_SESSION_ID=$SC "$ledger" done "closed" >/dev/null 2>&1
out=$(CLAUDE_CODE_SESSION_ID=$SC "$ledger" current); rc=$?
ok "current: closed task exits 1 with empty stdout"           '[ $rc -eq 1 ] && [ -z "$out" ]'
SD=sess-deleted; TD=$(CLAUDE_CODE_SESSION_ID=$SD "$ledger" start ptr-deleted)
rm -rf ".devkit/tasks/$TD"
out=$(CLAUDE_CODE_SESSION_ID=$SD "$ledger" current); rc=$?
ok "current: deleted task dir exits 1 with empty stdout"      '[ $rc -eq 1 ] && [ -z "$out" ]'
out=$(CLAUDE_CODE_SESSION_ID=$S1 DEVKIT_DEPTH=1 "$ledger" current); rc=$?
ok "current: worker depth 1 exits 1 with empty stdout"        '[ $rc -eq 1 ] && [ -z "$out" ]'
out=$(CLAUDE_CODE_SESSION_ID=$S1 DEVKIT_DEPTH=08 "$ledger" current); rc=$?
ok "current: worker depth 08 exits 1 with empty stdout"       '[ $rc -eq 1 ] && [ -z "$out" ]'
out=$(CLAUDE_CODE_SESSION_ID=$S1 DEVKIT_DEPTH=0 "$ledger" current); rc=$?
ok "current: depth 0 (main agent) still resolves"             '[ $rc -eq 0 ] && [ "$out" = "$A1" ]'

SA=sess-a; SB=sess-b
TA=$(CLAUDE_CODE_SESSION_ID=$SA "$ledger" start ptr-a1)
TB=$(CLAUDE_CODE_SESSION_ID=$SB "$ledger" start ptr-b1)
ok "two sessions keep independent pointers"                   '[ "$(cat ".devkit/run/session-$SA.task")" = "$TA" ] && [ "$(cat ".devkit/run/session-$SB.task")" = "$TB" ]'
TA2=$(CLAUDE_CODE_SESSION_ID=$SA "$ledger" start ptr-a2)
ok "a second start moves only its own pointer"                '[ "$(cat ".devkit/run/session-$SA.task")" = "$TA2" ] && [ "$(cat ".devkit/run/session-$SB.task")" = "$TB" ]'

CLAUDE_CODE_SESSION_ID=$SA "$ledger" -t "$A1" probe-twins "-t" "explicit"
ok "-t wins over the pointer"                                 'grep -q "probe-twins" ".devkit/tasks/$A1/ledger.tsv" && ! grep -q "probe-twins" ".devkit/tasks/$TA2/ledger.tsv"'
CLAUDE_CODE_SESSION_ID=$SA DEVKIT_TASK=$A1 "$ledger" probe-envwins "env" "x"
ok "DEVKIT_TASK wins over the pointer"                        'grep -q "probe-envwins" ".devkit/tasks/$A1/ledger.tsv" && ! grep -q "probe-envwins" ".devkit/tasks/$TA2/ledger.tsv"'
CLAUDE_CODE_SESSION_ID=$SA "$ledger" probe-pointed why "x"
ok "a row with no task lands in the pointed task"             'grep -q "probe-pointed" ".devkit/tasks/$TA2/ledger.tsv" && ! grep -q "probe-pointed" ".devkit/tasks/$A1/ledger.tsv"'
out=$(CLAUDE_CODE_SESSION_ID=$SA "$ledger" path); rc=$?
ok "path resolves from the pointer"                           '[ $rc -eq 0 ] && [ "$out" = "$t/.devkit/tasks/$TA2" ]'
CLAUDE_CODE_SESSION_ID=$SA "$ledger" accept w1 "ok"
ok "accept resolves from the pointer"                         'grep -q "accept" ".devkit/tasks/$TA2/ledger.tsv"'
gate_pass "$TA2"
CLAUDE_CODE_SESSION_ID=$SA "$ledger" done "via pointer"; rc=$?
ok "done resolves from the pointer"                           '[ $rc -eq 0 ] && tail -1 ".devkit/tasks/$TA2/ledger.tsv" | awk -F"\t" "\$2==\"done\"{f=1} END{exit !f}"'
out=$(CLAUDE_CODE_SESSION_ID=$SA "$ledger" current); rc=$?
ok "after done the pointer stops resolving"                   '[ $rc -eq 1 ] && [ -z "$out" ]'
err=$(CLAUDE_CODE_SESSION_ID=$SA "$ledger" probe-x y z 2>&1 >/dev/null); rc=$?
ok "closed pointer gives the clear error"                     '[ $rc -eq 2 ] && printf "%s" "$err" | grep -q "last task $TA2 is closed (or gone)" && printf "%s" "$err" | grep -q "ledger start <slug>" && printf "%s" "$err" | grep -q "pass -t <id>"'
ok "the other session is unaffected by that close"            '[ "$(CLAUDE_CODE_SESSION_ID=$SB "$ledger" current)" = "$TB" ]'

SG=sess-gone; TG=$(CLAUDE_CODE_SESSION_ID=$SG "$ledger" start ptr-gone)
rm -rf ".devkit/tasks/$TG"
err=$(CLAUDE_CODE_SESSION_ID=$SG "$ledger" probe-y y z 2>&1 >/dev/null); rc=$?
ok "gone pointer task gives the clear error"                  '[ $rc -eq 2 ] && printf "%s" "$err" | grep -q "last task $TG is closed (or gone)"'
err=$(CLAUDE_CODE_SESSION_ID=sess-noptr "$ledger" probe-z y z 2>&1 >/dev/null); rc=$?
ok "no pointer keeps the no-task error and mentions start"    '[ $rc -eq 2 ] && printf "%s" "$err" | grep -q "no task. Run: ledger start <slug>" && printf "%s" "$err" | grep -q "or just run ledger start"'

SP=sess-prune; TP=$(CLAUDE_CODE_SESSION_ID=$SP "$ledger" start ptr-prune)
gate_pass "$TP"
CLAUDE_CODE_SESSION_ID=$SP "$ledger" -t "$TP" done "x" >/dev/null 2>&1
CLAUDE_CODE_SESSION_ID=$SP "$ledger" -t "$TP" prune "post-close" "x" >/dev/null 2>&1
out=$(CLAUDE_CODE_SESSION_ID=$SP "$ledger" current); rc=$?
ok "a prune row after done keeps the task closed"             '[ $rc -eq 1 ] && [ -z "$out" ]'
SN=sess-prune-open; TN=$(CLAUDE_CODE_SESSION_ID=$SN "$ledger" start ptr-prune-open)
CLAUDE_CODE_SESSION_ID=$SN "$ledger" -t "$TN" prune "housekeeping" "x" >/dev/null 2>&1
out=$(CLAUDE_CODE_SESSION_ID=$SN "$ledger" current); rc=$?
ok "a prune row does not close an open task"                  '[ $rc -eq 0 ] && [ "$out" = "$TN" ]'

SE=sess-sub; TE=$(CLAUDE_CODE_SESSION_ID=$SE "$ledger" start ptr-sub)
out=$(cd sub/deep && CLAUDE_CODE_SESSION_ID=$SE "$ledger" current); rc=$?
ok "current resolves from a subdirectory"                     '[ $rc -eq 0 ] && [ "$out" = "$TE" ]'
(cd sub/deep && CLAUDE_CODE_SESSION_ID=$SE "$ledger" probe-subdir y z)
ok "a row from a subdirectory lands in the pointed task"      'grep -q "probe-subdir" ".devkit/tasks/$TE/ledger.tsv" && [ ! -d sub/deep/.devkit ]'
out=$(cd wt1 && CLAUDE_CODE_SESSION_ID=$SE "$ledger" current); rc=$?
ok "current resolves from a linked worktree"                  '[ $rc -eq 0 ] && [ "$out" = "$TE" ]'
(cd wt1 && CLAUDE_CODE_SESSION_ID=$SE "$ledger" probe-wt y z)
ok "a row from a worktree lands in the pointed task"          'grep -q "probe-wt" ".devkit/tasks/$TE/ledger.tsv" && [ ! -d wt1/.devkit ]'

DD=$(mktemp -d)
AD=$(cd "$t" && CLAUDE_CODE_SESSION_ID=sess-dd DEVKIT_DIR="$DD/.devkit" "$ledger" start ptr-dd)
ok "start writes the pointer under DEVKIT_DIR"                '[ "$(cat "$DD/.devkit/run/session-sess-dd.task")" = "$AD" ]'
out=$(cd "$t" && CLAUDE_CODE_SESSION_ID=sess-dd DEVKIT_DIR="$DD/.devkit" "$ledger" current); rc=$?
ok "current respects DEVKIT_DIR"                              '[ $rc -eq 0 ] && [ "$out" = "$AD" ]'
(cd "$t" && CLAUDE_CODE_SESSION_ID=sess-dd DEVKIT_DIR="$DD/.devkit" "$ledger" probe-dd y z)
ok "rows resolve under DEVKIT_DIR from the pointer"           'grep -q "probe-dd" "$DD/.devkit/tasks/$AD/ledger.tsv"'

PF=$(mktemp -d); ( cd "$PF" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i )
mkdir -p "$PF/.devkit" && : > "$PF/.devkit/run"
out=$(cd "$PF" && CLAUDE_CODE_SESSION_ID=sess-fail "$ledger" start ptr-fail 2>"$t/ptr-fail.err"); rc=$?
ok "a failing pointer write does not fail start"              '[ $rc -eq 0 ] && [[ $out == ptr-fail-* ]] && [ -f "$PF/.devkit/run" ] && [ ! -s "$PF/.devkit/run" ]'
ok "a failing pointer write stays silent"                     '[ ! -s "$t/ptr-fail.err" ]'

# --- s3: done needs a passing verify-gate row for the current tree (or a waive)
# scratch repo with a fake suite left uncommitted, so the working tree differs from the base
mkgate() { local d; d=$(mktemp -d "$t/g.XXXXXX"); cd "$d" || exit 2
  git init -q -b main . && git config user.email t@t && git config user.name t
  mkdir -p tests; echo x > README.md; git add -A; git commit -qm base
  printf '#!/usr/bin/env bash\necho "g.test.sh   1 passed, 0 failed   1s"\n' > tests/run-all.sh; chmod +x tests/run-all.sh
  export VERIFY_BUDGET="$t/gbudget"; printf 'suite_file_s=100\nsuite_total_s=200\n' > "$VERIFY_BUDGET"
  GT=$("$ledger" start gtest x 2>/dev/null); }
grows() { awk -F'\t' '$2=="verify-gate"' ".devkit/tasks/$GT/ledger.tsv" | wc -l | tr -d ' '; }

mkgate; "$ledger" -t "$GT" plan p d >/dev/null; n0=$(wc -l < ".devkit/tasks/$GT/ledger.tsv")
"$ledger" -t "$GT" done "no gate" 2>"$t/gate-a2.err"; rc=$?
ok "A2: no verify-gate row exits 4"            '[ $rc -eq 4 ] && grep -q "no verify-gate" "$t/gate-a2.err"'
ok "A2: the refusal writes nothing"            '[ "$(wc -l < ".devkit/tasks/$GT/ledger.tsv")" = "$n0" ]'
ok "A2: the message points at verify and waive" 'grep -q "bin/verify" "$t/gate-a2.err" && grep -q -- "--waive" "$t/gate-a2.err"'

mkgate; DEVKIT_TASK=$GT "$verify" >/dev/null 2>&1
out=$("$ledger" -t "$GT" done "after a pass" 2>/dev/null); rc=$?
ok "a pass for the current tree closes"        '[ $rc -eq 0 ]'
ok "a gated close prints one verified line"    '[ "$(printf "%s\n" "$out" | grep -c "^verified: ")" -eq 1 ] && printf "%s\n" "$out" | grep -qE "^verified: full tree [0-9a-f]{40} [0-9]+s; base start log /"'
mkgate; DEVKIT_TASK=$GT "$verify" >/dev/null 2>&1; echo more >> README.md
"$ledger" -t "$GT" done "edited" 2>"$t/gate-a3.err"; rc=$?
ok "A3: an edit after the pass exits 4"        '[ $rc -eq 4 ] && grep -q "another tree" "$t/gate-a3.err"'

# s5a: the gate row cannot be written by hand, and it needs its log file
mkgate; echo more >> README.md; n0=$(wc -l < ".devkit/tasks/$GT/ledger.tsv")
"$ledger" -t "$GT" verify-gate full "tree $("$verify" tree) 1s" "$EVID" pass 2>"$t/gate-forge.err"; rc=$?
ok "a hand-written verify-gate phase is refused" '[ $rc -eq 2 ] && [ "$(wc -l < ".devkit/tasks/$GT/ledger.tsv")" = "$n0" ] && grep -q "reserved" "$t/gate-forge.err"'
mkgate; echo more >> README.md
"$ledger" -t "$GT" gate-row full "tree $("$verify" tree) 1s" "$t/no-such.log" pass
"$ledger" -t "$GT" done "no log" 2>"$t/gate-nolog.err"; rc=$?
ok "a gate row without its log file does not satisfy" '[ $rc -eq 4 ] && grep -q "no log file" "$t/gate-nolog.err"'

mkgate; echo more >> README.md; printf 'log\n' > "$t/elsewhere.log"
"$ledger" -t "$GT" gate-row full "tree $("$verify" tree) 1s" "$t/elsewhere.log" pass
"$ledger" -t "$GT" done "outside runs" 2>"$t/gate-outside.err"; rc=$?
ok "m1: a log outside the task's runs does not satisfy" '[ $rc -eq 4 ] && grep -q "runs" "$t/gate-outside.err" && [ ! "$(tail -1 ".devkit/tasks/$GT/ledger.tsv" | cut -f2)" = done ]'
mkgate; echo more >> README.md; ER=$("$ledger" -t "$GT" path)/runs/empty.log; mkdir -p "$(dirname "$ER")"; : > "$ER"
"$ledger" -t "$GT" gate-row full "tree $("$verify" tree) 1s" "$ER" pass
"$ledger" -t "$GT" done "empty log" 2>"$t/gate-empty.err"; rc=$?
ok "m1: an empty log under runs does not satisfy" '[ $rc -eq 4 ] && grep -q "runs" "$t/gate-empty.err" && [ ! "$(tail -1 ".devkit/tasks/$GT/ledger.tsv" | cut -f2)" = done ]'

mkgate; printf '#!/usr/bin/env bash\necho garbage\n' > tests/run-all.sh
DEVKIT_TASK=$GT "$verify" >/dev/null 2>&1
"$ledger" -t "$GT" done "not-run row" 2>"$t/gate-a4.err"; rc=$?
ok "A4: a not-run result never closes"         '[ $rc -eq 4 ] && grep -q "not-run" "$t/gate-a4.err"'

mkgate; printf '#!/usr/bin/env bash\necho "g.test.sh   0 passed, 1 failed   1s"; exit 1\n' > tests/run-all.sh
DEVKIT_TASK=$GT "$verify" >/dev/null 2>&1
"$ledger" -t "$GT" done "fail row" 2>"$t/gate-fail.err"; rc=$?
ok "a fail row never closes"                   '[ $rc -eq 4 ] && grep -q "fail" "$t/gate-fail.err"'

mkgate; "$ledger" -t "$GT" waive "an earlier reason that is long enough" waived >/dev/null
out=$("$ledger" -t "$GT" done --waive "verified by hand, suite cannot run here" "w" 2>/dev/null); rc=$?
ok "A8: --waive closes"                        '[ $rc -eq 0 ]'
ok "A8: the waive row is written"              '[ "$(awk -F"\t" "\$2==\"waive\"" ".devkit/tasks/$GT/ledger.tsv" | wc -l | tr -d " ")" -eq 2 ]'
ok "A8: every waive prints, one per line"      '[ "$(printf "%s\n" "$out" | grep -c "^waived: ")" -eq 2 ] && printf "%s\n" "$out" | grep -qF "waived: verified by hand, suite cannot run here"'
ok "A8: the task is closed"                    '[ "$(tail -1 ".devkit/tasks/$GT/ledger.tsv" | cut -f2)" = done ]'

mkgate; n0=$(wc -l < ".devkit/tasks/$GT/ledger.tsv")
"$ledger" -t "$GT" done --waive "too short" 2>"$t/gate-short.err"; rc=$?
ok "a short waive reason exits 2, nothing written" '[ $rc -eq 2 ] && [ "$(wc -l < ".devkit/tasks/$GT/ledger.tsv")" = "$n0" ] && grep -q "20" "$t/gate-short.err"'

mkgate; git add -A; git commit -qm tools
NT=$("$ledger" start clean-tree x 2>/dev/null)
"$ledger" -t "$NT" done "clean tree" 2>"$t/gate-nodiff.err"; rc=$?
ok "no diff closes without any row"            '[ $rc -eq 0 ] && [ "$(awk -F"\t" "\$2==\"verify-gate\"" ".devkit/tasks/$NT/ledger.tsv" | wc -l | tr -d " ")" -eq 0 ] && [ ! -s "$t/gate-nodiff.err" ]'

mkgate; git checkout -q -b nobase
awk -F'\t' -v OFS='\t' '$2=="start"{$5=""} {print}' ".devkit/tasks/$GT/ledger.tsv" > "$t/legacy.tsv" && mv "$t/legacy.tsv" ".devkit/tasks/$GT/ledger.tsv"
git branch -D main -q; git update-ref -d refs/remotes/origin/main 2>/dev/null
err=$("$ledger" -t "$GT" done "no base" 2>&1 >/dev/null); rc=$?
ok "no base ref closes with a one-line note"   '[ $rc -eq 0 ] && [ "$(printf "%s\n" "$err" | grep -c .)" -eq 1 ] && printf "%s\n" "$err" | grep -qi "base"'

# s5a: the base is the task's start commit, so work committed on main after the start is not nodiff
mkgate; git add -A; git commit -qm work-after-start
G0=$(awk -F'\t' '$2=="start"{print $5}' ".devkit/tasks/$GT/ledger.tsv")
ok "start records head <sha> in its evidence cell" 'echo "$G0" | grep -qE "^head [0-9a-f]{40}$"'
"$ledger" -t "$GT" done "committed after start" 2>"$t/gate-startbase.err"; rc=$?
ok "committed after start is not nodiff: exit 4" '[ $rc -eq 4 ] && grep -q "no verify-gate" "$t/gate-startbase.err"'

mkgate; DEVKIT_DEPTH=1 "$ledger" -t "$GT" done "worker" 2>"$t/gate-worker.err"; rc=$?
ok "a worker still exits 3 before the gate"    '[ $rc -eq 3 ] && grep -q worker "$t/gate-worker.err" && [ "$(grows)" -eq 0 ]'
DEVKIT_DEPTH=1 "$ledger" -t "$GT" done --waive "a reason long enough for the check" 2>/dev/null; rc=$?
ok "a worker cannot waive either"              '[ $rc -eq 3 ]'

mkgate; "$ledger" -t "$GT" verify pass "hand written" >/dev/null
"$ledger" -t "$GT" done "hand row" 2>"$t/gate-hw.err"; rc=$?
ok "a hand-written verify row does not satisfy the gate" '[ $rc -eq 4 ] && grep -q "no verify-gate" "$t/gate-hw.err"'

# --- s5a: inside a git repo a missing or broken bin/verify fails closed (exit 4, no done row)
mkgate; echo more >> README.md; TDIR=$(mktemp -d "$t/tool.XXXXXX"); mkdir -p "$TDIR/bin"
cp "$here/bin/ledger" "$TDIR/bin/ledger"; chmod +x "$TDIR/bin/ledger"
n0=$(wc -l < ".devkit/tasks/$GT/ledger.tsv")
err=$(DEVKIT_DEPTH=0 "$TDIR/bin/ledger" -t "$GT" done "no verify tool" 2>&1 >/dev/null); rc=$?
ok "missing bin/verify: exit 4, no done row" '[ $rc -eq 4 ] && [ "$(wc -l < ".devkit/tasks/$GT/ledger.tsv")" = "$n0" ] && printf "%s\n" "$err" | grep -q "bin/verify"'
mkgate; echo more >> README.md; cp "$here/bin/verify" "$TDIR/bin/verify"; chmod -x "$TDIR/bin/verify"
n0=$(wc -l < ".devkit/tasks/$GT/ledger.tsv")
err=$(DEVKIT_DEPTH=0 "$TDIR/bin/ledger" -t "$GT" done "no exec" 2>&1 >/dev/null); rc=$?
ok "non-executable bin/verify: exit 4, no done row" '[ $rc -eq 4 ] && [ "$(wc -l < ".devkit/tasks/$GT/ledger.tsv")" = "$n0" ] && printf "%s\n" "$err" | grep -q "bin/verify"'
mkgate; echo more >> README.md; printf '#!/usr/bin/env bash\nexit 0\n' > "$TDIR/bin/verify"; chmod +x "$TDIR/bin/verify"
n0=$(wc -l < ".devkit/tasks/$GT/ledger.tsv")
err=$(DEVKIT_DEPTH=0 "$TDIR/bin/ledger" -t "$GT" done "empty tree" 2>&1 >/dev/null); rc=$?
ok "verify tree prints nothing: exit 4, no done row" '[ $rc -eq 4 ] && [ "$(wc -l < ".devkit/tasks/$GT/ledger.tsv")" = "$n0" ] && printf "%s\n" "$err" | grep -q "tree"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
