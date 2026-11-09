#!/usr/bin/env bash
# Tests for bin/spawn --prune using real git worktrees. Usage: tests/spawn-prune.test.sh
set -u
unset DEVKIT_DEPTH  # this suite must pass when run from inside a worker too
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
export DEVKIT_MODE=headless DEVKIT_VIEW=off
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"; ledger="$here/bin/ledger"; reconcile="$here/bin/reconcile"; verify="$here/bin/verify"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
# a verify-gate pass row for the current tree, the shape bin/verify writes (scratch repos cannot run the real gate)
gate_pass() { local d; d=$("$ledger" -t "$1" path) && mkdir -p "$d/runs" && echo gate > "$d/runs/gate.log" \
  && "$ledger" -t "$1" gate-row full "tree $("$verify" tree) 1s" "$d/runs/gate.log" pass; }
t=$(mktemp -d); live=
cleanup() { [ -z "$live" ] || kill "$live" 2>/dev/null; rm -rf "$t"; }
trap cleanup EXIT
cd "$t" && git init -q && echo base > f.txt && echo keep > keep.txt && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
export DEVKIT_DIR="$t/.devkit"
TA=$("$ledger" start task-a x); TB=$("$ledger" start task-b y)
TD="$DEVKIT_DIR/tasks/$TA"; TD2="$DEVKIT_DIR/tasks/$TB"; export DEVKIT_TASK=$TA
mkdir -p "$TD/run" "$TD2/run"
mkwt() { mkdir -p "$1/wt"; git worktree add -q "$1/wt/$3" -b "devkit/$2-$3"; } # $1=task dir $2=task id $3=worker id
acc() { "$ledger" -t "$1" accept "$2 accepted" "checked" "" pass; }
st() { echo "done 0 $(date +%s)" > "$1/run/$2.status"; }

# one of each state: the running pid is live; the dirty, unaccepted and unmerged ones must survive --yes
mkwt "$TD" "$TA" merged;     acc "$TA" merged;     st "$TD" merged
mkwt "$TD" "$TA" running;    acc "$TA" running;    sleep 30 & live=$!; disown "$live" 2>/dev/null; echo "running $live $(date +%s)" > "$TD/run/running.status" # sleep-ok: live-pid fixture, killed by cleanup
mkwt "$TD" "$TA" dirty;      acc "$TA" dirty;      st "$TD" dirty; echo changed > "$TD/wt/dirty/f.txt"
mkwt "$TD" "$TA" unaccepted; st "$TD" unaccepted
mkwt "$TD" "$TA" unmerged;   acc "$TA" unmerged
( cd "$TD/wt/unmerged" && echo more >> f.txt && git -c user.name=t -c user.email=t@t commit -qam work )
git merge -q --squash devkit/$TA-unmerged && git -c user.name=t -c user.email=t@t commit -qm "squash unmerged" # content on HEAD, the branch commit is not an ancestor
mkwt "$TD2" "$TB" other;     acc "$TB" other;      st "$TD2" other
git worktree add -q "$t/foreign" -b keepme

out=$("$spawn" --prune -t "$TA" 2>&1); rc=$?
ok "dry run exits 0" '[ $rc -eq 0 ]'
ok "dry run: accepted, clean, merged worker is marked remove"  'printf "%s\n" "$out" | grep -q "^merged  remove"'
ok "dry run: a running worker is kept"                        'printf "%s\n" "$out" | grep -q "^running  keep"'
ok "dry run: a dirty worktree is kept"                        'printf "%s\n" "$out" | grep -q "^dirty  keep"'
ok "dry run: a worker with no accept row is kept"             'printf "%s\n" "$out" | grep -q "^unaccepted  keep"'
ok "dry run: an unmerged branch is kept with the --discard hint" 'printf "%s\n" "$out" | grep -q "^unmerged  keep  commits not on HEAD; if merged by squash or abandoned rerun with --discard"'
ok "dry run prints a summary"                                  'printf "%s\n" "$out" | grep -q "1 remove, 4 keep"'
ok "dry run changes nothing"                                   '[ -d "$TD/wt/merged" ] && git rev-parse --verify -q refs/heads/devkit/$TA-merged >/dev/null && [ -d "$TD/wt/unmerged" ]'
ok "dry run writes no pruned row"                              '[ "$(grep -c "pruned" "$TD/ledger.tsv")" -eq 0 ]'

out=$("$spawn" --prune -t "$TA" --yes 2>&1); rc=$?
ok "--yes removes the merged worker: worktree and branch gone" '[ $rc -eq 0 ] && [ ! -e "$TD/wt/merged" ] && ! git rev-parse --verify -q refs/heads/devkit/$TA-merged >/dev/null'
ok "the removal appends exactly one pruned ledger row"         '[ "$(grep -c "merged pruned" "$TD/ledger.tsv")" -eq 1 ]'
prow=$(grep -F "merged pruned" "$TD/ledger.tsv")
ok "the removal row uses the prune phase"                      '[ "$(printf "%s\n" "$prow" | cut -f2)" = prune ]'
ok "an unmerged branch survives --yes without --discard"      '[ -d "$TD/wt/unmerged" ] && git rev-parse --verify -q refs/heads/devkit/$TA-unmerged >/dev/null && printf "%s\n" "$out" | grep -q "^unmerged  keep  commits not on HEAD"'
ok "--yes keeps a running worker"                             '[ -d "$TD/wt/running" ] && printf "%s\n" "$out" | grep -q "^running  keep"'
ok "--yes keeps a dirty worktree"                             '[ -d "$TD/wt/dirty" ] && printf "%s\n" "$out" | grep -q "^dirty  keep"'
ok "--yes keeps a worker with no accept row"                  '[ -d "$TD/wt/unaccepted" ] && printf "%s\n" "$out" | grep -q "^unaccepted  keep"'

out=$("$spawn" --prune -t "$TA" --discard --yes 2>&1); rc=$?
ok "--discard removes an accepted, clean worker merged by squash" '[ $rc -eq 0 ] && [ ! -e "$TD/wt/unmerged" ] && ! git rev-parse --verify -q refs/heads/devkit/$TA-unmerged >/dev/null'
ok "the discard removal appends one pruned row"                  '[ "$(grep -c "unmerged pruned" "$TD/ledger.tsv")" -eq 1 ]'
ok "--discard never waives a running worker"                     '[ -d "$TD/wt/running" ]'
ok "--discard never waives a dirty worktree"                     '[ -d "$TD/wt/dirty" ]'
ok "--discard never waives a missing accept row"                 '[ -d "$TD/wt/unaccepted" ]'

out=$("$spawn" --prune -t "$TA" --yes merged 2>&1); rc=$?
ok "a second prune of an already-removed worker is a quiet no-op" '[ $rc -eq 0 ] && [ -z "$out" ]'

mkwt "$TD2" "$TB" envonly; acc "$TB" envonly; st "$TD2" envonly
out=$(DEVKIT_TASK=$TB "$spawn" --prune --yes envonly 2>&1); rc=$?
ok "the task defaults to DEVKIT_TASK when -t is absent" '[ $rc -eq 0 ] && [ ! -e "$TD2/wt/envonly" ] && ! git rev-parse --verify -q refs/heads/devkit/$TB-envonly >/dev/null'
out=$("$reconcile" --gate -t "$TB" 2>&1); rc=$?
ok "a pruned worker's leftover done status does not gate the task" '[ $rc -eq 0 ] && [ -z "$out" ]'

DEVKIT_TASK=$TB "$spawn" --prune -t "$TA" --discard --yes >/dev/null 2>&1
ok "-t wins over DEVKIT_TASK: another task's worktree is untouched" '[ -d "$TD2/wt/other" ] && git rev-parse --verify -q refs/heads/devkit/$TB-other >/dev/null'
ok "a worktree on a non-devkit branch is untouched"                 '[ -d "$t/foreign" ] && git rev-parse --verify -q refs/heads/keepme >/dev/null'
ok "the main working tree is untouched"                             '[ -f "$t/f.txt" ] && [ -d "$t/.git" ]'

# branch delete fails (the branch is held by a worktree outside <task>/wt): worktree gone, branch kept, prune-partial row
mkwt "$TD" "$TA" partial; acc "$TA" partial; st "$TD" partial
git worktree add -q --force --force "$t/foreign-partial" "devkit/$TA-partial"
out=$("$spawn" --prune -t "$TA" --yes partial 2>&1); rc=$?
ok "a failed branch delete is a keep carrying git's message" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "^partial  keep  worktree removed but branch delete failed: .*devkit/$TA-partial"'
ok "a failed branch delete still removes the worktree dir"   '[ ! -e "$TD/wt/partial" ]'
ok "a failed branch delete leaves the branch in place"       'git rev-parse --verify -q refs/heads/devkit/$TA-partial >/dev/null'
prow=$(grep -F "partial prune-partial" "$TD/ledger.tsv")
ok "a failed branch delete writes one prune-partial row with the prune phase" '[ -n "$prow" ] && [ "$(printf "%s\n" "$prow" | wc -l | tr -d " ")" -eq 1 ] && [ "$(printf "%s\n" "$prow" | cut -f2)" = prune ]'
ok "a failed branch delete writes no pruned row"             '! grep -q -F "partial pruned" "$TD/ledger.tsv"'

# a bad id anywhere in the list must exit 2 before any removal, even under --yes
mkwt "$TD" "$TA" keepa; acc "$TA" keepa; st "$TD" keepa
mkwt "$TD" "$TA" keepb; acc "$TA" keepb; st "$TD" keepb
out=$("$spawn" --prune -t "$TA" --yes keepa keepb "bad id" 2>&1); rc=$?
ok "a bad id anywhere exits 2"                               '[ $rc -eq 2 ]'
ok "a bad id anywhere leaves both worktrees in place"        '[ -d "$TD/wt/keepa" ] && [ -d "$TD/wt/keepb" ]'
ok "a bad id anywhere leaves both branches in place"         'git rev-parse --verify -q refs/heads/devkit/$TA-keepa >/dev/null && git rev-parse --verify -q refs/heads/devkit/$TA-keepb >/dev/null'
ok "a bad id anywhere writes no prune rows for the valid ids" '! grep -q -E "keep[ab] (pruned|prune-partial)" "$TD/ledger.tsv"'

# --- session pointer fallback: -t, then $DEVKIT_TASK, then `ledger current`
PSS=sess-prune; PP=$(CLAUDE_CODE_SESSION_ID=$PSS "$ledger" start ptr-prune x); PPD="$DEVKIT_DIR/tasks/$PP"; mkdir -p "$PPD/run"
mkwt "$PPD" "$PP" pw1; acc "$PP" pw1; st "$PPD" pw1
mkwt "$TD2" "$TB" ex1; acc "$TB" ex1; st "$TD2" ex1
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$PSS "$spawn" --prune 2>&1); rc=$?
ok "pointer only: the dry run lists the pointed task's worker" '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "^pw1  remove" && ! printf "%s\n" "$out" | grep -q "^ex1"'
ok "pointer only: the dry run removes nothing"                '[ -d "$PPD/wt/pw1" ]'
out=$(DEVKIT_TASK=$TB CLAUDE_CODE_SESSION_ID=$PSS "$spawn" --prune 2>&1); rc=$?
ok "DEVKIT_TASK wins over the pointer"                        '[ $rc -eq 0 ] && printf "%s\n" "$out" | grep -q "^ex1  remove" && ! printf "%s\n" "$out" | grep -q "^pw1"'
out=$(DEVKIT_TASK=$TB CLAUDE_CODE_SESSION_ID=$PSS "$spawn" --prune -t "$TA" 2>&1); rc=$?
ok "-t wins over both DEVKIT_TASK and the pointer"            '[ $rc -eq 0 ] && ! printf "%s\n" "$out" | grep -q "^pw1" && ! printf "%s\n" "$out" | grep -q "^ex1"'
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$PSS "$spawn" --prune -t "" 2>&1); rc=$?
ok "an empty -t does not fall back to the pointer (exit 2)"   '[ $rc -eq 2 ] && ! printf "%s\n" "$out" | grep -q "^pw1" && [ -d "$PPD/wt/pw1" ]'
out=$(env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$spawn" --prune 2>&1); rc=$?
ok "no pointer keeps the old message"                         '[ $rc -eq 2 ] && printf "%s\n" "$out" | grep -q "spawn: no task. Pass --prune -t <id> or set DEVKIT_TASK"'
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$PSS "$spawn" --prune --yes 2>&1); rc=$?
ok "--yes with only the pointer removes the pointed task's worker" '[ $rc -eq 0 ] && [ ! -e "$PPD/wt/pw1" ] && ! git rev-parse --verify -q refs/heads/devkit/$PP-pw1 >/dev/null && [ "$(grep -c "pw1 pruned" "$PPD/ledger.tsv")" -eq 1 ]'
ok "--yes with only the pointer leaves another task's worker alone" '[ -d "$TD2/wt/ex1" ]'
gate_pass "$PP"; "$ledger" -t "$PP" done "closed" >/dev/null 2>&1
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$PSS "$spawn" --prune 2>&1); rc=$?
ok "a closed pointer gives the clear message naming the task" '[ $rc -eq 2 ] && printf "%s\n" "$out" | grep -q "last task $PP is closed (or gone)"'

out=$(env -u DEVKIT_TASK "$spawn" --prune 2>&1); rc=$?
ok "no task exits 2" '[ $rc -eq 2 ] && printf "%s\n" "$out" | grep -qi "no task"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
