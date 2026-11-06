#!/usr/bin/env bash
# Tests for evals/spawn-interactive.sh scoring with a fake herdr and a fake spawn (no tokens, no real herdr).
set -u
here=$(cd "$(dirname "$0")/.." && pwd); ev="$here/evals/spawn-interactive.sh"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
ok "the eval exists and is executable"        '[ -x "$ev" ] && bash -n "$ev"'
out=$("$ev" --list 2>&1); rc=$?
ok "--list exits 0 and names every cli"       '[ $rc -eq 0 ] && for c in claude codex opencode; do echo "$out" | grep -q "$c" || exit 1; done'
ok "--list names the assertions"              'for w in "tab created" "agent detected" "ticked checklist" "tab closed" "exit 0"; do echo "$out" | grep -q "$w" || exit 1; done'
ok "ARCHITECTURE.md documents the eval"       'grep -q "evals/spawn-interactive.sh" "$here/ARCHITECTURE.md"'

# fake herdr: answers like the real one; fake spawn: drives the herdr calls an interactive run makes and writes a handoff
mkdir -p "$t/bin"; cat > "$t/herdr" <<'S'
#!/usr/bin/env bash
case "$1 $2" in
  "tab list") exit 0;;
  "agent get") echo '{"result":{"agent":{"agent_status":"working","kind":"claude"}}}';;
esac
exit 0
S
cat > "$t/spawn" <<'S'
#!/usr/bin/env bash
# args: --shape scout <id> <cli> --prompt-or-brief ... ; env FAKE_HANDOFF decides the handoff text
while [ $# -gt 0 ]; do case $1 in --shape|--model) shift 2;; --prompt) shift 2;; *) break;; esac; done
id=$1
[ -n "${FAKE_NOTAB:-}" ] || herdr tab create --label "$id" >/dev/null
herdr agent start "$id" --kind "$2" --pane p >/dev/null
herdr agent get "$id" >/dev/null
mkdir -p "$DEVKIT_DIR/tasks/$DEVKIT_TASK/handoffs"
printf '%b' "$FAKE_HANDOFF" > "$DEVKIT_DIR/tasks/$DEVKIT_TASK/handoffs/$id.md"
[ -n "${FAKE_NOTAB:-}" ] || herdr tab close T >/dev/null
exit "${FAKE_RC:-0}"
S
chmod +x "$t/herdr" "$t/spawn"
good='result: PASS\n\n## Checklist\n- [x] 1. done\n'
run() { EVAL_HERDR="$t/herdr" EVAL_SPAWN="$t/spawn" EVAL_CLIS=claude "$ev" 2>&1; }
out=$(FAKE_HANDOFF="$good" run); rc=$?
ok "all assertions pass -> exit 0"            '[ $rc -eq 0 ] && ! echo "$out" | grep -q FAIL && [ $(echo "$out" | grep -c "^PASS") -eq 5 ]'
# run from inside a worker: depth and task are inherited; the eval must still get its own sandbox task at depth 0
cat > "$t/spawn-depth" <<'S'
#!/usr/bin/env bash
echo "depth=${DEVKIT_DEPTH:-0} task=${DEVKIT_TASK:-} dir=${DEVKIT_DIR:-} pwd=$(pwd -P) top=$(git rev-parse --show-toplevel 2>/dev/null)" > "$FAKE_SEEN"
exec "$FAKE_REAL" "$@"
S
chmod +x "$t/spawn-depth"
out=$(DEVKIT_DEPTH=1 DEVKIT_TASK=bogus FAKE_SEEN="$t/seen" FAKE_REAL="$t/spawn" FAKE_HANDOFF="$good" EVAL_HERDR="$t/herdr" EVAL_SPAWN="$t/spawn-depth" EVAL_CLIS=claude "$ev" 2>&1); rc=$?
ok "runs from a depth-1 worker: still exit 0 and 5 PASS"  '[ $rc -eq 0 ] && [ $(echo "$out" | grep -c "^PASS") -eq 5 ]'
ok "the nested spawn sees depth 0, its own sandbox task and dir"  'grep -q "^depth=0 task=spawn-eval" "$t/seen" && grep -q "dir=.*/.devkit" "$t/seen" && ! grep -q "task=bogus" "$t/seen"'
# claude and codex ask "trust this folder?" in a fresh temp dir; a git-ignored dir under the repo's .devkit sits inside a trusted tree
ok "the sandbox lives under the repo's .devkit and is removed on exit" 'p=$(sed -n "s/.* pwd=\([^ ]*\).*/\1/p" "$t/seen"); case "$p" in "$(cd "$here" && pwd -P)"/.devkit/*) [ ! -e "$p" ];; *) false;; esac'
# claude takes a nested git repo as its own trust root and asks again; without one it inherits the repo's trust
ok "the sandbox has no .git of its own" 'p=$(sed -n "s/.* pwd=\([^ ]*\).*/\1/p" "$t/seen"); top=$(sed -n "s/.* top=//p" "$t/seen"); [ -n "$p" ] && [ "$top" != "$p" ]'
ok ".devkit is git-ignored" 'git -C "$here" check-ignore -q .devkit/x'
out=$(FAKE_HANDOFF='result: PASS\n' run); rc=$?
ok "no ticked checklist -> that assertion FAILs, exit 1" '[ $rc -ne 0 ] && echo "$out" | grep "^FAIL" | grep -q "ticked checklist"'
out=$(FAKE_HANDOFF="$good" FAKE_NOTAB=1 run); rc=$?
ok "no tab created or closed -> both FAIL"    '[ $rc -ne 0 ] && echo "$out" | grep "^FAIL" | grep -q "tab created" && echo "$out" | grep "^FAIL" | grep -q "tab closed"'
out=$(FAKE_HANDOFF="$good" FAKE_RC=1 run); rc=$?
ok "spawn exit 1 -> exit 0 assertion FAILs"   '[ $rc -ne 0 ] && echo "$out" | grep "^FAIL" | grep -q "exit 0"'
out=$(EVAL_HERDR="$t/none" EVAL_SPAWN="$t/spawn" EVAL_CLIS=claude "$ev" 2>&1); rc=$?
ok "no herdr -> refuses to run (exit 2)"      '[ $rc -eq 2 ] && echo "$out" | grep -qi "herdr"'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
