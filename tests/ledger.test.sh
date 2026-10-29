#!/usr/bin/env bash
# Tests for bin/ledger (per-task ledgers). Usage: tests/ledger.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && mkdir -p sub/deep
unset HARNESS_DIR HARNESS_LEDGER HARNESS_LEDGER_MIRROR HARNESS_TASK

A=$(cd sub/deep && "$ledger" start fix-login "first look")
ok "start prints a slugged id"              '[[ $A == fix-login-* ]] && [ -d ".harness/tasks/$A" ]'
ok "start writes header + start row"        '[ "$(wc -l < .harness/tasks/$A/ledger.tsv)" -eq 2 ] && sed -n 1p .harness/tasks/$A/ledger.tsv | grep -q "^time	phase	decision	reason	evidence	result$" && sed -n 2p .harness/tasks/$A/ledger.tsv | awk -F"\t" "\$2==\"start\"{f=1} END{exit !f}"'
B=$("$ledger" start fix-login "second session, same slug")
ok "same slug twice gets distinct ids"      '[ "$A" != "$B" ] && [ -d ".harness/tasks/$B" ]'

"$ledger" plan "split" "two areas" 2>/dev/null; rc=$?
ok "no task: refuses (exit 2), writes nothing shared" '[ $rc -eq 2 ] && [ ! -e .harness/ledger.tsv ]'
"$ledger" -t nosuch plan a b 2>/dev/null; rc=$?
ok "unknown task exits 2"                   '[ $rc -eq 2 ]'

"$ledger" -t "$A" plan "split work" "two areas" "plan.json" ok
HARNESS_TASK=$B "$ledger" plan "other work" "different task"
ok "-t appends to that task only"           'grep -q "split work" .harness/tasks/$A/ledger.tsv && ! grep -q "split work" .harness/tasks/$B/ledger.tsv'
ok "HARNESS_TASK env works, isolated"       'grep -q "other work" .harness/tasks/$B/ledger.tsv && ! grep -q "other work" .harness/tasks/$A/ledger.tsv'

(cd sub/deep && "$ledger" -t "$A" plan "from subdir" r)
ok "subdir resolves to repo root"           'grep -q "from subdir" .harness/tasks/$A/ledger.tsv && [ ! -d sub/deep/.harness ]'
git worktree add -q "$t/wt1" -b wtb 2>/dev/null
(cd "$t/wt1" && "$ledger" -t "$A" plan "from worktree" r)
ok "linked worktree shares main .harness"   'grep -q "from worktree" .harness/tasks/$A/ledger.tsv && [ ! -d "$t/wt1/.harness" ]'
ok "path prints the task dir"               '[ "$("$ledger" path -t "$A")" = "$t/.harness/tasks/$A" ]'
ok "base prints the .harness dir"           '[ "$("$ledger" base)" = "$t/.harness" ]'

"$ledger" -t "$A" verify "a | b	tab" "multi
line" "" pass
ok "tabs and newlines flattened, 6 columns" '[ "$(tail -1 .harness/tasks/$A/ledger.tsv | awk -F"\t" "{print NF}")" -eq 6 ] && tail -1 .harness/tasks/$A/ledger.tsv | grep -q "a | b tab"'
"$ledger" -t "$A" big "$(head -c 3000 /dev/zero | tr '\0' z)" r
ok "oversized cell truncated (<2000B row)"  '[ "$(tail -1 .harness/tasks/$A/ledger.tsv | wc -c)" -lt 2000 ]'

C=$("$ledger" start parallel "x")
for w in 1 2 3 4 5 6 7 8; do ( for i in $(seq 1 25); do "$ledger" -t "$C" work "w$w-$i" "concurrent"; done ) & done; wait
ok "8 parallel writers: 200 intact rows"    '[ "$(awk -F"\t" "\$2==\"work\"" .harness/tasks/$C/ledger.tsv | wc -l)" -eq 200 ] && [ "$(awk -F"\t" "NF!=6" .harness/tasks/$C/ledger.tsv | wc -l)" -eq 0 ]'

"$ledger" -t "$C" done "all finished"
ok "done writes phase=done"                 'tail -1 .harness/tasks/$C/ledger.tsv | awk -F"\t" "\$2==\"done\"{f=1} END{exit !f}"'

M="$t/mirror.out"; HARNESS_LEDGER_MIRROR="echo \"\$1\" >> $M" "$ledger" -t "$A" ph2 dec2 why2
ok "mirror runs with row text as \$1"       'grep -q "ph2" "$M"'
HARNESS_LEDGER_MIRROR='exit 9' "$ledger" -t "$A" a b c; rc=$?
ok "failing mirror does not fail ledger"    '[ $rc -eq 0 ] && awk -F"\t" "\$2==\"a\" && \$3==\"b\"{f=1} END{exit !f}" .harness/tasks/$A/ledger.tsv'
"$ledger" -t "$A" onlytwo 2>/dev/null; rc=$?
ok "too few args exits 2"                   '[ $rc -eq 2 ]'
# --- local-only: .harness never shows up in git status, and state.md starts from a template
G=$(mktemp -d); ( cd "$G" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i )
LA=$(cd "$G" && "$ledger" start local-test "x")
ok "start keeps .harness out of git status"      '[ -z "$(git -C "$G" status --porcelain)" ]'
ok "exclude holds .harness/ exactly once"        '[ "$(grep -cxF ".harness/" "$G/.git/info/exclude")" -eq 1 ]'
( cd "$G" && "$ledger" start again "y" >/dev/null )
ok "a second start adds no duplicate exclude"    '[ "$(grep -cxF ".harness/" "$G/.git/info/exclude")" -eq 1 ]'
ok "start creates state.md from the template"    'grep -q "^## Findings" "$G/.harness/tasks/$LA/state.md" && grep -q "^## Learnings" "$G/.harness/tasks/$LA/state.md" && ! grep -q "^## Next" "$G/.harness/tasks/$LA/state.md"'
ok "state.md does not copy the ledger start row" '! grep -q "local-test" "$G/.harness/tasks/$LA/state.md"'
W=$(mktemp -d); ( cd "$G" && git worktree add -q "$W/wt" -b wtb2 2>/dev/null ); ( cd "$W/wt" && "$ledger" start from-wt "z" >/dev/null )
ok "start from a linked worktree is clean too"   '[ -z "$(git -C "$G" status --porcelain)" ] && [ -z "$(git -C "$W/wt" status --porcelain)" ]'
N=$(mktemp -d); ( cd "$N" && "$ledger" start nongit "q" >/dev/null ); rc=$?
ok "outside git: no error, no exclude attempted" '[ $rc -eq 0 ] && [ -d "$N/.harness/tasks" ]'

# --- truncation is visible, not silent
err=$("$ledger" -t "$A" big "$(head -c 500 /dev/zero | tr '\0' z)" r 2>&1 >/dev/null)
ok "a field over 400 chars warns on stderr"        'echo "$err" | grep -qi "truncated"'
err=$("$ledger" -t "$A" small "short" r 2>&1 >/dev/null)
ok "a short field stays silent"                    '[ -z "$err" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
