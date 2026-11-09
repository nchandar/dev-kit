#!/usr/bin/env bash
# Tests for bin/state check (state.md and memory.md rules). Usage: tests/state.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
here=$(cd "$(dirname "$0")/.." && pwd); ledger="$here/bin/ledger"; state="$here/bin/state"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q -b main && unset DEVKIT_DIR DEVKIT_TASK
T=$("$ledger" start st "x"); D=".devkit/tasks/$T"; S="$D/state.md"
chk() { "$state" check -t "$T" 2>&1; }
reset() { printf '# state\ngoal: see spec.md\n\n## Findings\n\n## Decisions\n\n## Direction\n\n## Open questions\n\n## Learnings\n' > "$S"; }
put() { reset; awk -v sec="$1" -v line="$2" '{print} $0=="## " sec {print line}' "$S" > "$S.new" && mv "$S.new" "$S"; }

out=$(chk); rc=$?
ok "fresh template passes"                         '[ $rc -eq 0 ]'
put Findings '- uses a bash 3.2 safe empty-array guard (handoffs/a.md:4)'
ok "finding with a pointer passes"                 'chk >/dev/null'
put Findings '- the lint was changed to cap the library'
out=$(chk); rc=$?
ok "finding without a pointer fails"               '[ $rc -ne 0 ] && echo "$out" | grep -qi pointer'
put Decisions '- chose two tiers (L2)'
ok "decision with an L<n> pointer passes"          'chk >/dev/null'
reset; sed -i.bak 's/^## Open questions$//' "$S"; rm "$S.bak"
out=$(chk); rc=$?
ok "missing section fails"                         '[ $rc -ne 0 ] && echo "$out" | grep -q "Open questions"'
reset; printf '\n## Next\n- do the thing\n' >> "$S"
out=$(chk); rc=$?
ok "a Next section fails (the ledger next row owns it)" '[ $rc -ne 0 ] && echo "$out" | grep -q "Next"'
put Findings "- $(printf 'x%.0s' $(seq 1 150)) (handoffs/a.md)"
out=$(chk); rc=$?
ok "bullet over 140 chars fails"                   '[ $rc -ne 0 ] && echo "$out" | grep -qi "140"'
"$ledger" -t "$T" design "adopt a two tier principles digest with deep files loaded on demand" "keeps the always read cost small" "" ok
put Findings '- adopt a two tier principles digest with deep files loaded on demand (L3)'
out=$(chk); rc=$?
ok "text copied from a ledger row fails"           '[ $rc -ne 0 ] && echo "$out" | grep -qi "ledger"'
reset; for i in $(seq 1 62); do printf -- '- ok line %s (handoffs/a.md)\n' "$i" >> "$S"; done
out=$(chk); rc=$?
ok "state.md over 60 lines fails"                  '[ $rc -ne 0 ] && echo "$out" | grep -q "60"'
reset; awk '{print} $0=="## Direction"{print "line one";print "line two";print "line three";print "line four"}' "$S" > "$S.new" && mv "$S.new" "$S"
out=$(chk); rc=$?
ok "Direction over 3 lines fails"                  '[ $rc -ne 0 ] && echo "$out" | grep -qi direction'
put Learnings '- [ ] build needs flag Y because Z | scope: recipe | ref: runs/003.log'
ok "valid learning passes"                         'chk >/dev/null'
put Learnings '- [ ] build needs flag Y because Z | scope: weird | ref: runs/003.log'
out=$(chk); rc=$?
ok "learning with an unknown scope fails"          '[ $rc -ne 0 ] && echo "$out" | grep -qi scope'
put Learnings '- [?] lesson | scope: project | ref: runs/003.log'
ok "learning with a bad checkbox fails"            '! chk >/dev/null'
put Learnings '- [x] lesson without ref | scope: project'
ok "learning without ref fails"                    '! chk >/dev/null'

reset; M=".devkit/memory.md"; printf '# memory\n## Build\n- run `make test` before commit\n- release steps in docs/release.md\n' > "$M"
ok "valid memory.md passes"                        'chk >/dev/null'
printf -- '- a claim with neither command nor pointer\n' >> "$M"
ok "memory bullet with no pointer or command fails" '! chk >/dev/null'
{ echo "# memory"; for i in $(seq 1 82); do echo "- see docs/a.md $i"; done; } > "$M"
out=$(chk); rc=$?
ok "memory.md over 80 lines fails"                 '[ $rc -ne 0 ] && echo "$out" | grep -q "80"'
rm -f "$M"
"$state" check -t nosuch >/dev/null 2>&1; rc=$?
ok "unknown task exits 2"                          '[ $rc -eq 2 ]'
# --- characters that corrupt the learning inbox
put Findings "$(printf -- '- has a tab\there (handoffs/a.md)')"
out=$(chk); rc=$?
ok "a tab in state.md fails"                       '[ $rc -ne 0 ] && echo "$out" | grep -qi "tab"'
put Findings "$(printf -- '- crlf line (handoffs/a.md)\r')"
out=$(chk); rc=$?
ok "a carriage return in state.md fails"           '[ $rc -ne 0 ] && echo "$out" | grep -qi "tab or"'

H=$("$ledger" start hdr-only "x"); HD=".devkit/tasks/$H"; head -1 "$HD/ledger.tsv" > "$HD/ledger.new" && mv "$HD/ledger.new" "$HD/ledger.tsv"
cp "$S" "$HD/state.md"; reset
cp "$S" "$HD/state.md"
out=$("$state" check -t "$H" 2>&1); rc=$?
ok "header-only ledger does not swallow state.md" '[ $rc -eq 0 ]'

# --- session pointer fallback: explicit -t, then $DEVKIT_TASK, then `ledger current`
SS=sess-state; PS=$(CLAUDE_CODE_SESSION_ID=$SS "$ledger" start ptr-state "x")
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SS "$state" check 2>&1); rc=$?
ok "no DEVKIT_TASK: the pointer supplies the task"      '[ $rc -eq 0 ] && echo "$out" | grep -q "^OK"'
put Findings '- no pointer here'
out=$(DEVKIT_TASK=$T CLAUDE_CODE_SESSION_ID=$SS "$state" check 2>&1); rc=$?
ok "DEVKIT_TASK wins over the pointer"                  '[ $rc -ne 0 ] && echo "$out" | grep -qi pointer'
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SS "$state" check 2>&1); rc=$?
ok "the pointer task stays clean while the explicit one fails" '[ $rc -eq 0 ]'
out=$(env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$state" check 2>&1); rc=$?
ok "no pointer: the existing no-task error"             '[ $rc -eq 2 ] && echo "$out" | grep -q "state: no task (set DEVKIT_TASK or pass -t)"'
"$ledger" -t "$PS" done "closed" >/dev/null 2>&1
out=$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SS "$state" check 2>&1); rc=$?
ok "closed pointer: the clear error names the task"     '[ $rc -eq 2 ] && echo "$out" | grep -q "last task $PS is closed (or gone)"'

git -c user.name=t -c user.email=t@t commit -q --allow-empty -m wt-base; mkdir -p "$t/sub/deep"
WSS=sess-state-dir; WST=$(CLAUDE_CODE_SESSION_ID=$WSS "$ledger" start ptr-dir "x")
git worktree add -q "$t/wt-state" -b wt-state-b
out=$(cd "$t/sub/deep" && env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$WSS "$state" check 2>&1); rc=$?
ok "state resolves the pointer from a subdirectory of the repo"    '[ $rc -eq 0 ] && echo "$out" | grep -q "^OK"'
out=$(cd "$t/wt-state" && env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$WSS "$state" check 2>&1); rc=$?
ok "state resolves the pointer from a git worktree of the repo"    '[ $rc -eq 0 ] && echo "$out" | grep -q "^OK"'
put Findings '- no pointer here'
out=$(DEVKIT_TASK=$WST CLAUDE_CODE_SESSION_ID=$WSS "$state" check -t "$T" 2>&1); rc=$?
ok "state: -t wins over both DEVKIT_TASK and the pointer"          '[ $rc -ne 0 ] && echo "$out" | grep -qi pointer'
out=$(DEVKIT_TASK=$T CLAUDE_CODE_SESSION_ID=$WSS "$state" check -t "$WST" 2>&1); rc=$?
ok "state: -t names a clean task even when DEVKIT_TASK is dirty"   '[ $rc -eq 0 ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
