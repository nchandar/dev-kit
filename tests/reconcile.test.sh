#!/usr/bin/env bash
# Tests for bin/reconcile. Usage: tests/reconcile.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); rec="$here/bin/reconcile"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
unset HARNESS_DIR HARNESS_TASK

out=$("$rec"); rc=$?
ok "no tasks: friendly message, exit 0"    '[ $rc -eq 0 ] && echo "$out" | grep -qi "no tasks"'

A=$("$ledger" start feat-a "x"); B=$("$ledger" start bug-b "y"); C=$("$ledger" start old-c "z")
"$ledger" -t "$A" plan "split into 3 slices" why
"$ledger" -t "$C" done "shipped"
out=$("$rec")
ok "lists open tasks only, one line each"  '[ "$(echo "$out" | wc -l)" -eq 2 ] && echo "$out" | grep -q "$A" && echo "$out" | grep -q "$B" && ! echo "$out" | grep -q "$C"'
ok "line shows last phase and decision"   'echo "$out" | grep "$A" | grep -q "plan: split into 3 slices"'
ok "--all includes finished tasks"         '"$rec" --all | grep -q "$C"'
ok "--all marks finished as done"          '"$rec" --all | grep "$C" | grep -q "done"'

"$ledger" -t "$A" next "run slice s2: bin/run tests/s2" "resume point"
D=$(.harness/../bin/ledger base 2>/dev/null || "$ledger" base)/tasks/$A
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
export HARNESS_LEARN_DIR="$t/inbox"
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

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
