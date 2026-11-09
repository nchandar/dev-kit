#!/usr/bin/env bash
# Tests for bin/spawn worker isolation: the --worktree prompt rule and the main-checkout guard.
# Usage: tests/spawn-isolation.test.sh
set -u
unset DEVKIT_DEPTH DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY DEVKIT_MODE DEVKIT_POLL DEVKIT_GRACE GIT_CONFIG_COUNT
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && tp=$(pwd -P) && git init -q && echo base > f.txt && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
export DEVKIT_DIR="$t/.devkit" DEVKIT_MODE=headless DEVKIT_VIEW=off DEVKIT_VIEW_CLOSE_DELAY=0
TA=$("$here/bin/ledger" start iso x); TD="$DEVKIT_DIR/tasks/$TA"; export DEVKIT_TASK=$TA
echo "do the thing" > "$t/brief.md"

cat > "$t/fake" <<'F'
#!/usr/bin/env bash
# $1=prompt $2=handoff path. Behaviour via FAKE_* env.
[ -n "${FAKE_WT_EDIT:-}" ] && echo wt >> f.txt
[ -n "${FAKE_ROOT_EDIT:-}" ] && echo changed >> "$FAKE_ROOT/f.txt"
[ -n "${FAKE_ROOT_COMMIT:-}" ] && ( cd "$FAKE_ROOT" && echo worker > worker.txt && git add worker.txt && git -c user.name=t -c user.email=t@t commit -qm worker )
[ -n "${FAKE_ROOT_RESET:-}" ] && git -C "$FAKE_ROOT" reset --hard HEAD~1 >/dev/null
[ -n "${FAKE_MARK:-}" ] && : > "$FAKE_MARK"
sleep "${FAKE_SLEEP:-0}"
printf 'fake handoff\n' > "$2"
F
chmod +x "$t/fake"; export DEVKIT_FAKE="$t/fake"

# --- item 7: the prompt rule for a --worktree worker names both real paths
out=$(DEVKIT_DRYRUN=1 "$spawn" --worktree pw fake "$t/brief.md")
ok "worktree prompt: the real worktree path, relative paths only" 'printf "%s\n" "$out" | grep -qF "/tasks/$TA/wt/pw. Edit and commit ONLY inside it, with relative paths"'
ok "worktree prompt: the real main root is read-only" 'printf "%s\n" "$out" | grep -qF "the main checkout at $tp is read-only for you"'
ok "prompt: the worker reads its updates file before each slice and before the handoff" 'printf "%s\n" "$out" | grep -qF "/tasks/$TA/updates/pw.md" && printf "%s\n" "$out" | grep -qF "Before each slice"'
ok "worktree prompt: it asks for pwd and the branch first" 'printf "%s\n" "$out" | grep -qF "run pwd and git rev-parse --abbrev-ref HEAD first"'
out=$(DEVKIT_DRYRUN=1 "$spawn" npw fake "$t/brief.md")
ok "no --worktree: the prompt rule is unchanged" '! printf "%s\n" "$out" | grep -qF "Your working directory is"'

# --- item 8/9: a commit in the root is flagged, once, with the HEAD range
FAKE_ROOT="$tp" FAKE_ROOT_COMMIT=1 "$spawn" --worktree rc1 fake "$t/brief.md" 2>"$t/rc1.err"; rc=$?
old=$(git rev-parse HEAD~1); new=$(git rev-parse HEAD)
ok "root commit: flagged exactly once with the HEAD range" '[ $rc -eq 0 ] && grep -qF "spawn: WARN rc1 changed the main checkout (1 file(s), HEAD $old..$new)" "$t/rc1.err" && [ "$(grep -c "^spawn: WARN rc1 " "$t/rc1.err")" -eq 1 ]'
ok "root commit: exactly one isolation ledger row" '[ "$(grep -c "rc1 isolation-violation" $TD/ledger.tsv)" -eq 1 ]'
ok "root commit: state and exit code are unchanged" '[ $rc -eq 0 ] && grep -q "^done 0" $TD/run/rc1.status'
ok "root commit: noted in the handoff footer" 'grep -q "^isolation: WARN the main checkout changed" $TD/handoffs/rc1.md'
ok "root commit: says its work is not on the worktree branch" 'grep -qF "its work is not on its worktree branch" "$t/rc1.err"'
ok "root commit: the worktree branch did not move" '[ "$(git rev-parse devkit/$TA-rc1)" = "$old" ]'

# --- item 10: a reset moves the main HEAD back and is flagged too
echo second >> f.txt && git -c user.name=t -c user.email=t@t commit -qam second
old=$(git rev-parse HEAD)
FAKE_ROOT="$tp" FAKE_ROOT_RESET=1 "$spawn" --worktree rs1 fake "$t/brief.md" 2>"$t/rs1.err"; rc=$?
new=$(git rev-parse HEAD)
ok "root reset: flagged with the old and new HEAD" '[ $rc -eq 0 ] && grep -qF "HEAD $old..$new" "$t/rs1.err" && grep -qF "spawn: WARN rs1 changed the main checkout" "$t/rs1.err"'
ok "root reset: exactly one isolation ledger row" '[ "$(grep -c "rs1 isolation-violation" $TD/ledger.tsv)" -eq 1 ]'
ok "root reset: state and exit code are unchanged" '[ $rc -eq 0 ] && grep -q "^done 0" $TD/run/rs1.status'

# --- a worker that only touches its worktree is clean
FAKE_WT_EDIT=1 "$spawn" --worktree wt1 fake "$t/brief.md" 2>"$t/wt1.err"; rc=$?
ok "worktree-only: not flagged" '[ $rc -eq 0 ] && ! grep -q "WARN wt1" "$t/wt1.err" && ! grep -q "wt1 isolation-violation" $TD/ledger.tsv'
ok "worktree-only: the change landed in the worktree" 'grep -q "^wt$" $TD/wt/wt1/f.txt'

# --- pre-existing dirt in the root is not blamed (compare before and after)
echo pre > "$t/pre.txt"
FAKE_WT_EDIT=1 "$spawn" --worktree wt2 fake "$t/brief.md" 2>"$t/wt2.err"; rc=$?
ok "dirty before: pre-existing dirt is not blamed" '[ $rc -eq 0 ] && ! grep -q "WARN wt2" "$t/wt2.err" && ! grep -q "wt2 isolation-violation" $TD/ledger.tsv'
rm -f "$t/pre.txt"

# --- a file already dirty in the root: a worker edit to it leaves status identical but must be flagged
echo pre >> f.txt
FAKE_WT_EDIT=1 "$spawn" --worktree pd1 fake "$t/brief.md" 2>"$t/pd1.err"; rc=$?
ok "pre-dirty f.txt untouched: not blamed" '[ $rc -eq 0 ] && ! grep -q "WARN pd1" "$t/pd1.err" && ! grep -q "pd1 isolation-violation" $TD/ledger.tsv'
FAKE_ROOT="$tp" FAKE_ROOT_EDIT=1 "$spawn" --worktree pd2 fake "$t/brief.md" 2>"$t/pd2.err"; rc=$?
ok "pre-dirty f.txt edited again: flagged once" '[ $rc -eq 0 ] && grep -q "spawn: WARN pd2 changed the main checkout" "$t/pd2.err" && [ "$(grep -c "pd2 isolation-violation" $TD/ledger.tsv)" -eq 1 ]'
ok "pre-dirty f.txt edited again: state and exit code unchanged" 'grep -q "^done 0" $TD/run/pd2.status'
git checkout -q f.txt

# --- a worker without --worktree is not checked
FAKE_ROOT="$tp" FAKE_ROOT_EDIT=1 "$spawn" nowt fake "$t/brief.md" 2>"$t/nowt.err"; rc=$?
ok "no --worktree: the main checkout is not checked" '[ $rc -eq 0 ] && ! grep -q "WARN nowt" "$t/nowt.err" && ! grep -q "nowt isolation-violation" $TD/ledger.tsv'
git checkout -q f.txt

# --- the guard still runs after a timeout
FAKE_ROOT="$tp" FAKE_ROOT_EDIT=1 FAKE_SLEEP=30 DEVKIT_TIMEOUT=1 "$spawn" --worktree to1 fake "$t/brief.md" 2>"$t/to1.err"; rc=$?
ok "timeout: the guard still runs and the state stays timeout" '[ $rc -ne 0 ] && grep -q "^timeout" $TD/run/to1.status && grep -q "spawn: WARN to1 " "$t/to1.err" && [ "$(grep -c "to1 isolation-violation" $TD/ledger.tsv)" -eq 1 ]'
git checkout -q f.txt

# --- the guard still runs when the spawn is killed (cleanup path)
rm -f "$DEVKIT_DIR/km.marker"
FAKE_ROOT="$tp" FAKE_ROOT_EDIT=1 FAKE_MARK="$DEVKIT_DIR/km.marker" FAKE_SLEEP=30 "$spawn" --worktree km1 fake "$t/brief.md" 2>"$t/km1.err" &
sp=$!
n=0; while [ ! -e "$DEVKIT_DIR/km.marker" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll for the fake worker to edit the root
kill -TERM $sp; wait $sp; rc=$?; p=0; while ! grep -q "km1 isolation-violation" $TD/ledger.tsv && [ $p -lt 50 ]; do sleep 0.02; p=$((p+1)); done # sleep-ok: bounded poll for the cleanup guard to write its row
ok "killed: the guard still runs in cleanup, state stays killed" '[ $rc -ne 0 ] && grep -q "^killed" $TD/run/km1.status && grep -q "spawn: WARN km1 " "$t/km1.err" && [ "$(grep -c "km1 isolation-violation" $TD/ledger.tsv)" -eq 1 ]'
ok "killed: the warning appears exactly once" '[ "$(grep -c "^spawn: WARN km1 " "$t/km1.err")" -eq 1 ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
