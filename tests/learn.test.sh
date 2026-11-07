#!/usr/bin/env bash
# Tests for bin/learn (local learning inbox). Usage: tests/learn.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
here=$(cd "$(dirname "$0")/.." && pwd); ledger="$here/bin/ledger"; learn="$here/bin/learn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && unset DEVKIT_DIR DEVKIT_TASK
export DEVKIT_LEARN_DIR="$t/inbox"
T=$("$ledger" start lt "x"); export DEVKIT_TASK=$T; S=".devkit/tasks/$T/state.md"
cat > "$S" <<'S2'
# state
goal: see spec.md

## Findings

## Decisions

## Direction

## Open questions

## Learnings
- [ ] general lesson about retries | scope: general | ref: handoffs/a.md:3
- [ ] recipe: build needs flag Y because Z | scope: recipe | ref: runs/001.log
- [ ] this project uses make test | scope: project | ref: Makefile:2
- [x] already promoted | scope: general | ref: library/tdd
S2

ok "count is 0 before anything is queued"          '[ "$("$learn" count)" = 0 ]'
out=$("$learn" queue); rc=$?
ok "queue succeeds and reports 2"                  '[ $rc -eq 0 ] && echo "$out" | grep -q "queued 2"'
ok "general and recipe learnings are marked [~]"   'grep -q "^- \[~\] general lesson" "$S" && grep -q "^- \[~\] recipe: build" "$S"'
ok "the project learning stays open"               'grep -q "^- \[ \] this project uses make test" "$S"'
ok "an already promoted one is untouched"          'grep -q "^- \[x\] already promoted" "$S"'
ok "inbox has a header and 2 rows"                 '[ "$(wc -l < "$t/inbox/inbox.tsv")" -eq 3 ] && head -1 "$t/inbox/inbox.tsv" | grep -q "^time	project	task	scope	lesson	ref	from"'
ok "inbox row carries scope, lesson and ref"       'grep -q "	recipe	recipe: build needs flag Y because Z	runs/001.log	" "$t/inbox/inbox.tsv"'
out=$("$learn" queue)
ok "queue is idempotent"                           'echo "$out" | grep -q "queued 0" && [ "$(wc -l < "$t/inbox/inbox.tsv")" -eq 3 ]'
ok "count is 2"                                    '[ "$("$learn" count)" = 2 ]'
out=$("$learn" list)
ok "list shows ids, scope and lesson"              'echo "$out" | grep -q "^1 .*general.*general lesson about retries" && echo "$out" | grep -q "^2 .*recipe.*build needs flag Y"'
"$learn" done 1 promoted >/dev/null; rc=$?
ok "done 1 promoted succeeds"                      '[ $rc -eq 0 ]'
ok "done flips the state.md box to [x]"            'grep -q "^- \[x\] general lesson about retries" "$S"'
ok "count drops to 1"                              '[ "$("$learn" count)" = 1 ]'
"$learn" done 2 dropped >/dev/null
ok "dropped flips the box to [-]"                  'grep -q "^- \[-\] recipe: build" "$S" && [ "$("$learn" count)" = 0 ]'
"$learn" done 9 promoted >/dev/null 2>&1; rc=$?
ok "unknown id exits 2"                            '[ $rc -eq 2 ]'
"$learn" done 1 maybe >/dev/null 2>&1; rc=$?
ok "bad outcome exits 2"                           '[ $rc -eq 2 ]'
out=$("$learn" list)
ok "list with nothing queued says so"              'echo "$out" | grep -qi "no learnings queued"'
env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$learn" queue >/dev/null 2>&1; rc=$?
ok "queue without a task exits 2"                  '[ $rc -eq 2 ]'

# --- session pointer fallback (queue path): -t, then $DEVKIT_TASK, then `ledger current`
LS=sess-learn; LP=$(CLAUDE_CODE_SESSION_ID=$LS "$ledger" start ptr-learn "x"); LPS=".devkit/tasks/$LP/state.md"
cat > "$LPS" <<'S3'
# state
goal: see spec.md

## Findings

## Decisions

## Direction

## Open questions

## Learnings
- [ ] lesson from the pointer | scope: general | ref: handoffs/c.md:1
S3
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$LS "$learn" queue); rc=$?
ok "no DEVKIT_TASK: the pointer supplies the task" '[ $rc -eq 0 ] && echo "$out" | grep -q "queued 1" && tail -1 "$t/inbox/inbox.tsv" | grep -q "	$LP	"'
printf -- '- [ ] lesson from the explicit task | scope: general | ref: handoffs/d.md:1\n' >> "$S"
out=$(DEVKIT_TASK=$T CLAUDE_CODE_SESSION_ID=$LS "$learn" queue); rc=$?
ok "DEVKIT_TASK wins over the pointer"             'echo "$out" | grep -q "queued 1" && tail -1 "$t/inbox/inbox.tsv" | grep -q "	$T	" && tail -1 "$t/inbox/inbox.tsv" | grep -q "lesson from the explicit task" && grep -q "^- \[~\] lesson from the pointer" "$LPS"'
out=$(env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$learn" queue 2>&1); rc=$?
ok "no pointer: the existing no-task error"        '[ $rc -eq 2 ] && echo "$out" | grep -q "learn: no task (set DEVKIT_TASK or pass -t)"'
"$ledger" -t "$LP" done "closed" >/dev/null 2>&1
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$LS "$learn" queue 2>&1); rc=$?
ok "closed pointer: the clear error names the task" '[ $rc -eq 2 ] && echo "$out" | grep -q "last task $LP is closed (or gone)"'

git -c user.name=t -c user.email=t@t commit -q --allow-empty -m wt-base; mkdir -p "$t/sub/deep"
LDS=sess-learn-dir; LDT=$(CLAUDE_CODE_SESSION_ID=$LDS "$ledger" start ptr-dir "x"); LDS_F=".devkit/tasks/$LDT/state.md"
git worktree add -q "$t/wt-learn" -b wt-learn-b
learnline() { printf -- '- [ ] %s | scope: general | ref: handoffs/e.md:1\n' "$1" >> "$2"; }
learnline "from the subdir" "$LDS_F"
out=$(cd "$t/sub/deep" && env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$LDS "$learn" queue); rc=$?
ok "learn resolves the pointer from a subdirectory of the repo"    '[ $rc -eq 0 ] && echo "$out" | grep -q "queued 1" && grep -q "^- \[~\] from the subdir" "$LDS_F"'
learnline "from the worktree" "$LDS_F"
out=$(cd "$t/wt-learn" && env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$LDS "$learn" queue); rc=$?
ok "learn resolves the pointer from a git worktree of the repo"    '[ $rc -eq 0 ] && echo "$out" | grep -q "queued 1" && grep -q "^- \[~\] from the worktree" "$LDS_F"'
learnline "for the dash t task" "$S"; learnline "left for the pointer" "$LDS_F"
out=$(DEVKIT_TASK=$LDT CLAUDE_CODE_SESSION_ID=$LDS "$learn" queue -t "$T"); rc=$?
ok "learn: -t wins over both DEVKIT_TASK and the pointer"          '[ $rc -eq 0 ] && echo "$out" | grep -q "queued 1" && grep -q "^- \[~\] for the dash t task" "$S" && grep -q "^- \[ \] left for the pointer" "$LDS_F"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
