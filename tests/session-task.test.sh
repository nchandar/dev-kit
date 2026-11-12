#!/usr/bin/env bash
# Cross-tool integration: a session's own task drives every consumer. Usage: tests/session-task.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
unset DEVKIT_TASK DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT GIT_CONFIG_COUNT
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
export DEVKIT_MODE=headless DEVKIT_VIEW=off
here=$(cd "$(dirname "$0")/.." && pwd)
run="$here/bin/run"; state="$here/bin/state"; learn="$here/bin/learn"; ledger="$here/bin/ledger"
rec="$here/bin/reconcile"; spawn="$here/bin/spawn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
verify="$here/bin/verify"
# a verify-gate pass row for the current tree, the shape bin/verify writes (scratch repos cannot run the real gate);
# bin/verify hands gate-row a per-run token, so the fixture plays verify's part with the same contract
gate_pass() { local d f; d=$("$ledger" -t "$1" path) && f=$(mktemp) && printf 'test-token\n' > "$f" \
  && mkdir -p "$d/runs" && echo gate > "$d/runs/gate.log" \
  && DEVKIT_GATE_TOKEN_FILE="$f" DEVKIT_GATE_TOKEN=test-token "$ledger" -t "$1" gate-row full "tree $("$verify" tree) 1s" "$d/runs/gate.log" pass; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
export DEVKIT_DIR="$t/.devkit" DEVKIT_LEARN_DIR="$t/learn"
# --close-views calls herdr tab close: a stub first on PATH keeps the real herdr (and run-all's tripwire) out of it
hs="$t/hstub"; mkdir -p "$hs"; printf '#!/bin/sh\necho "$*" >> "%s/herdr.log"\nexit 0\n' "$t" > "$hs/herdr"; chmod +x "$hs/herdr"; export PATH="$hs:$PATH"
unset DEVKIT_TASK

S1=sess-int-a; S2=sess-int-b
T=$(CLAUDE_CODE_SESSION_ID=$S1 "$ledger" start shared "one session, every tool"); TD="$DEVKIT_DIR/tasks/$T"

ok "started task is the session's current task"          '[ "$(CLAUDE_CODE_SESSION_ID=$S1 "$ledger" current)" = "$T" ]'
out=$(CLAUDE_CODE_SESSION_ID=$S2 "$ledger" current 2>/dev/null); rc=$?
ok "a second session sees no current task"               '[ $rc -eq 1 ] && [ -z "$out" ]'

out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$run" echo hello); rc=$?
ok "run: acts on the pointed task"                       '[ $rc -eq 0 ] && [ -d "$TD/runs" ] && [ "$(ls "$TD/runs" | wc -l | tr -d " ")" -ge 1 ]'
ok "run: its ledger row lands in the pointed task"       'awk -F"\t" "\$2==\"run\"" "$TD/ledger.tsv" | grep -q "hello"'

out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$state" check 2>&1); rc=$?
ok "state: acts on the pointed task"                     '[ $rc -eq 0 ] && echo "$out" | grep -q "^OK"'

cat >> "$TD/state.md" <<'S'
- [ ] integration lesson | scope: general | ref: tests/session-task.test.sh:1
S
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$learn" queue); rc=$?
ok "learn: acts on the pointed task"                     '[ $rc -eq 0 ] && echo "$out" | grep -q "queued 1"'
ok "learn: the inbox row names the pointed task"         'tail -1 "$t/learn/inbox.tsv" | awk -F"\t" -v t="$T" "\$3==t{f=1} END{exit !f}"'

env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$ledger" note "from the pointer" x; rc=$?
ok "ledger: a row with no task lands in the pointed task" '[ $rc -eq 0 ] && grep -q "from the pointer" "$TD/ledger.tsv"'
ok "ledger: path resolves from the pointer"              '[ "$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$ledger" path)" = "$TD" ]'

mkdir -p "$TD/run" "$TD/handoffs"
echo "running $$ 100" > "$TD/run/g1.status"
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$rec" --gate); rc=$?
ok "reconcile --gate: acts on the pointed task"          '[ $rc -eq 1 ] && echo "$out" | grep -q "g1 running"'
rm -f "$TD/run/g1.status"

mkdir -p "$TD/wt"
git worktree add -q "$TD/wt/w1" -b "devkit/$T-w1"
echo "done 0 100" > "$TD/run/w1.status"
"$ledger" -t "$T" accept "w1 accepted" "checked" "" pass 2>/dev/null
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$spawn" --prune 2>&1); rc=$?
ok "spawn --prune: acts on the pointed task (dry run)"    '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "^w1  remove"'

for tool in run state learn ledger reconcile spawn; do
  case $tool in
    run)       env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S2 "$run" true >/dev/null 2>&1;;
    state)     env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S2 "$state" check >/dev/null 2>&1;;
    learn)     env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S2 "$learn" queue >/dev/null 2>&1;;
    ledger)    env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S2 "$ledger" path >/dev/null 2>&1;;
    reconcile) env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S2 "$rec" --gate >/dev/null 2>&1;;
    spawn)     env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S2 "$spawn" --prune >/dev/null 2>&1;;
  esac
  rc=$?
  ok "second session: $tool has no task (exit 2)"         '[ $rc -eq 2 ]'
done

gate_pass "$T"
CLAUDE_CODE_SESSION_ID=$S1 "$ledger" done "closed" >/dev/null 2>&1
out=$(CLAUDE_CODE_SESSION_ID=$S1 "$ledger" current 2>/dev/null); rc=$?
ok "after done the pointer stops resolving"              '[ $rc -eq 1 ] && [ -z "$out" ]'

for tool in run state learn ledger reconcile spawn; do
  case $tool in
    run)       env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$run" true 2>"$t/e" >/dev/null;;
    state)     env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$state" check 2>"$t/e" >/dev/null;;
    learn)     env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$learn" queue 2>"$t/e" >/dev/null;;
    ledger)    env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$ledger" path 2>"$t/e" >/dev/null;;
    reconcile) env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$rec" --gate 2>"$t/e" >/dev/null;;
    spawn)     env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$spawn" --prune 2>"$t/e" >/dev/null;;
  esac
  rc=$?
  ok "closed task: $tool errors clearly"                  '[ $rc -eq 2 ] && grep -q "last task $T is closed (or gone)" "$t/e"'
done

# --- close-views also errors on the closed pointer
env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$S1 "$spawn" --close-views 2>"$t/e" >/dev/null; rc=$?
ok "closed task: spawn --close-views errors clearly"       '[ $rc -eq 2 ] && grep -q "last task $T is closed (or gone)" "$t/e"'

# --- helpers: one call per tool, args: session-or-empty, then the tool name; extra env via the caller
call() { # sid tool -> runs the tool with DEVKIT_TASK unset unless the caller exported it inline
  local sid=$1 tool=$2
  case $tool in
    run)       CLAUDE_CODE_SESSION_ID=$sid "$run" echo "via-$tool";;
    state)     CLAUDE_CODE_SESSION_ID=$sid "$state" check;;
    learn)     CLAUDE_CODE_SESSION_ID=$sid "$learn" queue;;
    ledger)    CLAUDE_CODE_SESSION_ID=$sid "$ledger" note "via-$tool" x;;
    reconcile) CLAUDE_CODE_SESSION_ID=$sid "$rec" --gate;;
    prune)     CLAUDE_CODE_SESSION_ID=$sid "$spawn" --prune;;
    views)     CLAUDE_CODE_SESSION_ID=$sid "$spawn" --close-views;;
  esac; }
TOOLS="run state learn ledger reconcile prune views"
mk() { # session slug -> task id, with a worktree worker, a tab file and a worker status for the tools to see
  local id d; id=$(CLAUDE_CODE_SESSION_ID=$1 "$ledger" start "$2" x); d="$DEVKIT_DIR/tasks/$id"
  mkdir -p "$d/run" "$d/wt"; git worktree add -q "$d/wt/w-$2" -b "devkit/$id-w-$2"
  echo "done 0 100" > "$d/run/w-$2.status"; "$ledger" -t "$id" accept "w-$2 accepted" "checked" "" pass 2>/dev/null
  echo "tab-$2" > "$d/run/v-$2.tab"; echo "running $$ 100" > "$d/run/g-$2.status"
  printf -- '- [ ] lesson %s | scope: general | ref: tests/session-task.test.sh:1\n' "$2" >> "$d/state.md"
  echo "$id"; }

# --- two sessions, two tasks, interleaved: each tool acts on its OWN task only
SA=sess-two-a; SB=sess-two-b
TA=$(mk $SA aa); TB=$(mk $SB bb); DA="$DEVKIT_DIR/tasks/$TA"; DB="$DEVKIT_DIR/tasks/$TB"
for n in 1 2; do
  for pair in "$SA:aa:$TA" "$SB:bb:$TB"; do
    sid=${pair%%:*}; rest=${pair#*:}; slug=${rest%%:*}; id=${rest#*:}
    out=$(call "$sid" run 2>&1); r1=$?
    ok "round $n: $slug run lands in its own task"            '[ $r1 -eq 0 ] && grep -q "via-run" "$DEVKIT_DIR/tasks/$id"/runs/*.log'
    out=$(call "$sid" state 2>&1); r2=$?
    ok "round $n: $slug state check passes on its own task"   '[ $r2 -eq 0 ] && echo "$out" | grep -q "^OK"'
    call "$sid" ledger >/dev/null 2>&1; r3=$?
    ok "round $n: $slug ledger row lands in its own task"     '[ $r3 -eq 0 ] && [ "$(grep -c "via-ledger" "$DEVKIT_DIR/tasks/$id/ledger.tsv")" -eq $n ]'
    out=$(call "$sid" reconcile 2>&1); r4=$?
    ok "round $n: $slug gate sees only its own worker"        '[ $r4 -eq 1 ] && echo "$out" | grep -q "g-$slug running" && ! echo "$out" | grep -q "g-$([ $slug = aa ] && echo bb || echo aa) "'
    out=$(call "$sid" prune 2>&1); r5=$?
    ok "round $n: $slug prune lists only its own worker"      '[ $r5 -eq 0 ] && echo "$out" | grep -q "^w-$slug  remove" && ! echo "$out" | grep -q "^w-$([ $slug = aa ] && echo bb || echo aa)"'
  done
done
call $SA learn >/dev/null 2>&1; call $SB learn >/dev/null 2>&1
ok "learn: each session queued only its own lesson"           'grep -q "^- \[~\] lesson aa" "$DA/state.md" && grep -q "^- \[~\] lesson bb" "$DB/state.md" && [ "$(grep -c "lesson aa" "$t/learn/inbox.tsv")" -eq 1 ] && [ "$(grep -c "lesson bb" "$t/learn/inbox.tsv")" -eq 1 ]'
call $SA views >/dev/null 2>&1; rc=$?
ok "close-views: a session closes only its own task's tab"    '[ $rc -eq 0 ] && [ ! -e "$DA/run/v-aa.tab" ] && [ -e "$DB/run/v-bb.tab" ]'
ok "close-views: only its own tab id reached herdr"           'grep -q "tab close tab-aa" "$t/herdr.log" && ! grep -q "tab-bb" "$t/herdr.log"'
call $SB views >/dev/null 2>&1
ok "close-views: the other session closes its own tab"        '[ ! -e "$DB/run/v-bb.tab" ]'
ok "close-views: the other session's tab id reached herdr"     'grep -q "tab close tab-bb" "$t/herdr.log"'

# --- DEVKIT_TASK wins over the pointer in every tool (session A, explicit task B)
TE=$(mk $SA ee); DE="$DEVKIT_DIR/tasks/$TE"   # session A now points at the new task ee; B is the explicit one
echo "tab-bb2" > "$DB/run/v-bb.tab"
for tool in $TOOLS; do
  out=$(DEVKIT_TASK=$TB call $SA $tool 2>&1)
  case $tool in
    run)       ok "explicit wins: run acts on the explicit task"       'grep -q "via-run" "$DB"/runs/*.log && ! grep -q "via-run" "$DE"/runs/*.log 2>/dev/null';;
    state)     ok "explicit wins: state checks the explicit task"      'DEVKIT_TASK=$TB "$state" check -t "$TB" >/dev/null 2>&1; echo "$out" | grep -q "^OK"';;
    learn)     ok "explicit wins: learn queues nothing from the pointer" '! grep -q "^- \[~\] lesson ee" "$DE/state.md"';;
    ledger)    ok "explicit wins: ledger row lands in the explicit task" 'grep -q "via-ledger" "$DB/ledger.tsv" && ! grep -q "via-ledger" "$DE/ledger.tsv"';;
    reconcile) ok "explicit wins: gate reports the explicit task"      'echo "$out" | grep -q "g-bb running" && ! echo "$out" | grep -q "g-ee"';;
    prune)     ok "explicit wins: prune lists the explicit task"       'echo "$out" | grep -q "^w-bb" && ! echo "$out" | grep -q "^w-ee"';;
    views)     ok "explicit wins: close-views closes the explicit tab" '[ ! -e "$DB/run/v-bb.tab" ] && [ -e "$DE/run/v-ee.tab" ]';;
  esac
done

# --- an unsafe session id is "no session" in every tool, even with a lookalike pointer on disk
mkdir -p "$DEVKIT_DIR/run/session-.."; echo "$TE" > "$DEVKIT_DIR/run/session-../x.task"; echo "$TE" > "$DEVKIT_DIR/run/session-a b.task"
for sid in "../x" "a b"; do
  for tool in $TOOLS; do
    out=$(call "$sid" $tool 2>&1); rc=$?
    ok "session '$sid': $tool sees no task (exit 2, no pointer message)" '[ $rc -eq 2 ] && ! echo "$out" | grep -q "last task" && ! echo "$out" | grep -q "$TE"'
  done
done

# --- a worker (DEVKIT_DEPTH=1, no DEVKIT_TASK) never uses the pointer
for tool in run state learn ledger; do
  out=$(DEVKIT_DEPTH=1 call $SA $tool 2>&1); rc=$?
  ok "worker environment: $tool ignores the pointer (exit 2)" '[ $rc -eq 2 ] && ! echo "$out" | grep -q "last task"'
done

# --- regression: the leftover-worktree warning names the task, so the command it prints works after done
SW=sess-warn-left
TW=$(CLAUDE_CODE_SESSION_ID=$SW "$ledger" start warnleft x); DW="$DEVKIT_DIR/tasks/$TW"
mkdir -p "$DW/wt"
git worktree add -q "$DW/wt/left" -b "devkit/$TW-left"
"$ledger" -t "$TW" accept "left accepted" "checked" "" pass >/dev/null 2>&1
gate_pass "$TW"
werr=$(CLAUDE_CODE_SESSION_ID=$SW "$ledger" done "leftover" 2>&1 >/dev/null); rc=$?
ok "done warns the count and names the task"      '[ $rc -eq 0 ] && printf "%s\n" "$werr" | grep -q "1 worker worktree" && printf "%s\n" "$werr" | grep -q "/spawn --prune -t $TW --yes"' # pitfall-ok: src-grep greps the tool's stdout, not bin sources
wcmd=$(printf '%s\n' "$werr" | sed -n 's/^.*run: //;s/ (add --discard.*//p')
ok "the warning prints the full command line"     '[ "$wcmd" = "$spawn --prune -t $TW --yes" ]'
[ "$(git rev-list --count "HEAD..devkit/$TW-left" 2>/dev/null || echo 1)" = 0 ] || wcmd="$wcmd --discard" # unmerged branch: the printed command alone would keep it, so add --discard
out=$(bash -c "$wcmd" 2>&1); rc=$?
ok "the printed command tears down the worktree"  '[ $rc -eq 0 ] && [ ! -d "$DW/wt/left" ]'
ok "the printed command deletes the branch"       '[ -z "$(git branch --list "devkit/$TW-left")" ]'
# --- regression: the printed command is absolute, so it works verbatim from a subdirectory or a symlinked path of the owning repo
R=$(mktemp -d); ( cd "$R" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i )
RL="$R-link"; ln -s "$R" "$RL"
for where in sub link; do
  SX=sess-abs-$where; TX=$(cd "$R" && env -u DEVKIT_DIR CLAUDE_CODE_SESSION_ID=$SX "$ledger" start abs-$where x); DX="$R/.devkit/tasks/$TX"
  mkdir -p "$DX/wt"; ( cd "$R" && git worktree add -q "$DX/wt/w1" -b "devkit/$TX-w1" )
  ( cd "$R" && env -u DEVKIT_DIR "$ledger" -t "$TX" accept "w1 accepted" "checked" "" pass >/dev/null 2>&1 )
  werr=$(cd "$R" && env -u DEVKIT_DIR CLAUDE_CODE_SESSION_ID=$SX "$ledger" done "left" 2>&1 >/dev/null)
  wcmd=$(printf '%s\n' "$werr" | sed -n 's/^.*run: //;s/ (add --discard.*//p')
  case $werr in *"add --discard"*) wcmd="$wcmd --discard";; esac
  ok "$where: the printed path is absolute"        'case $wcmd in /*) true;; *) false;; esac'
  ok "$where: the printed tool exists and runs"    'sp=${wcmd%% *}; [ -x "$sp" ] && [ "$sp" = "$spawn" ]'
  if [ $where = sub ]; then mkdir -p "$R/deep/er"; cwdx="$R/deep/er"; else cwdx="$RL"; fi
  out=$(cd "$cwdx" && env -u DEVKIT_DIR -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID bash -c "$wcmd" 2>&1); rc=$?
  ok "$where: the printed command works verbatim"  '[ $rc -eq 0 ]'
  ok "$where: the worktree is gone"                '[ ! -d "$DX/wt/w1" ]'
  ok "$where: the branch is gone"                  '[ -z "$(cd "$R" && git branch --list "devkit/$TX-w1")" ]'
done
rm -rf "$RL" "$R"
# --- regression: the printed command survives a bin path with a space, so it must be shell-quoted
RX=$(mktemp -d); ( cd "$RX" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i )
LB="$t/my bin"; ln -s "$here/bin" "$LB" # pitfall-ok: whole tools dir shared, only ledger/spawn involved here
TXS=$(cd "$RX" && env -u DEVKIT_DIR "$LB/ledger" start spacewarn x); DXS="$RX/.devkit/tasks/$TXS"
mkdir -p "$DXS/wt"; ( cd "$RX" && env -u DEVKIT_DIR git worktree add -q "$DXS/wt/w1" -b "devkit/$TXS-w1" )
( cd "$RX" && env -u DEVKIT_DIR "$LB/ledger" -t "$TXS" accept "w1 accepted" "checked" "" pass >/dev/null 2>&1 )
swerr=$(cd "$RX" && env -u DEVKIT_DIR "$LB/ledger" -t "$TXS" done "left" 2>&1 >/dev/null); rc=$?
ok "space path: done still warns with the pruned count" '[ $rc -eq 0 ] && printf "%s\n" "$swerr" | grep -q "1 worker worktree"'
swcmd=$(printf '%s\n' "$swerr" | sed -n 's/^.*run: //;s/ (add --discard.*//p')
out=$(cd "$RX" && unset DEVKIT_DIR DEVKIT_TASK && eval "$swcmd" 2>&1); rc=$?
ok "space path: the printed command runs verbatim (eval)" '[ $rc -eq 0 ]'
ok "space path: the worktree is gone" '[ ! -d "$DXS/wt/w1" ]'
ok "space path: the branch is gone" '[ -z "$(cd "$RX" && git branch --list "devkit/$TXS-w1")" ]'
rm -rf "$RX"
TV=$(CLAUDE_CODE_SESSION_ID=sess-warn-clean "$ledger" start warnclean x)
gate_pass "$TV"
out=$(CLAUDE_CODE_SESSION_ID=sess-warn-clean "$ledger" done "clean" 2>&1 >/dev/null); rc=$?
ok "done with no leftovers is still silent"       '[ $rc -eq 0 ] && [ -z "$out" ]'
NG2=$(mktemp -d)
NT=$(cd "$NG2" && DEVKIT_DIR="$NG2/nd" CLAUDE_CODE_SESSION_ID=sess-warn-nongit "$ledger" start nongit-warn x)
out=$(cd "$NG2" && DEVKIT_DIR="$NG2/nd" CLAUDE_CODE_SESSION_ID=sess-warn-nongit "$ledger" done "no git" 2>&1 >/dev/null); rc=$?
ok "done outside git is still silent"             '[ $rc -eq 0 ] && [ -z "$out" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
