#!/usr/bin/env bash
# Tests for bin/learn (local learning inbox). Usage: tests/learn.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); ledger="$here/bin/ledger"; learn="$here/bin/learn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && unset HARNESS_DIR HARNESS_TASK
export HARNESS_LEARN_DIR="$t/inbox"
T=$("$ledger" start lt "x"); export HARNESS_TASK=$T; S=".harness/tasks/$T/state.md"
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
env -u HARNESS_TASK "$learn" queue >/dev/null 2>&1; rc=$?
ok "queue without a task exits 2"                  '[ $rc -eq 2 ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
