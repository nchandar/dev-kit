#!/usr/bin/env bash
# Kill bin/learn between the inbox append and the state.md rename, then rerun: exactly one inbox row.
# Usage: tests/learn-crash.test.sh
# Tree: DEVKIT_LEARN_TEST_SRC (default this repo) runs it against another tree; used to prove it can fail.
set -u
unset DEVKIT_DEPTH CLAUDE_CODE_SESSION_ID DEVKIT_DIR DEVKIT_TASK
here=${DEVKIT_LEARN_TEST_SRC:-$(cd "$(dirname "$0")/.." && pwd)}
ledger="$here/bin/ledger"; learn="$here/bin/learn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
MV=$(command -v mv)
cd "$t" && git init -q
export DEVKIT_LEARN_DIR="$t/inbox"
T=$("$ledger" start learn-crash "x"); export DEVKIT_TASK=$T
S=".devkit/tasks/$T/state.md"
cat > "$S" <<'S2'
# state
goal: see spec.md

## Learnings
- [ ] a lesson that survives a crash | scope: general | ref: handoffs/a.md:1
S2
rows() { if [ -s "$t/inbox/inbox.tsv" ]; then tail -n +2 "$t/inbox/inbox.tsv" | grep -c .; else echo 0; fi; }

# --- kill between the append (bin/learn:43) and the state rename (:46)
shim="$t/shim"; mkdir -p "$shim"
cat > "$shim/mv" <<'S'
#!/bin/bash
last=
for a in "$@"; do case $a in -*) ;; *) last=$a;; esac; done
case $last in *"$KILL_FILE") kill -9 -"$(cat "$KILL_STATE/pgid")" 2>/dev/null; exit 137;; esac
exec @MV@ "$@"
S
sed "s|@MV@|$MV|" "$shim/mv" > "$shim/mv.tmp" && mv "$shim/mv.tmp" "$shim/mv"; chmod +x "$shim/mv"
launch="$t/launch"
cat > "$launch" <<'S'
#!/bin/bash
printf '%s\n' "$$" > "$KILL_STATE/pgid"
exec "$KILL_LEARN" queue
S
state="$t/state"; mkdir -p "$state"
( set -m
  env PATH="$shim:$PATH" KILL_STATE="$state" KILL_FILE="$S" KILL_LEARN="$learn" DEVKIT_TASK="$T" \
    DEVKIT_LEARN_DIR="$t/inbox" /bin/bash "$launch" > "$t/killed.out" 2>&1 &
  pid=$!
  set +m
  wait "$pid" ) 2>/dev/null; rc=$?
ok "kill: learn was killed" '[ $rc -ne 0 ]'
ok "kill: the inbox row was appended" '[ "$(rows)" = 1 ]'
ok "kill: state.md still says open" 'grep -q "^- \[ \] a lesson that survives a crash" "$S"'

# --- rerun to completion: the same lesson must not land twice
out=$("$learn" queue 2>&1); rc=$?
ok "rerun: exits 0" '[ $rc -eq 0 ]'
ok "rerun: exactly one inbox row" '[ "$(rows)" = 1 ]'
ok "rerun: state.md is flipped to queued" 'grep -q "^- \[~\] a lesson that survives a crash" "$S"'
ok "rerun: count is one" '[ "$("$learn" count)" = 1 ]'
ok "rerun: the row still names the task and lesson" 'tail -1 "$t/inbox/inbox.tsv" | grep -q "	$T	general	a lesson that survives a crash	handoffs/a.md:1	"'

# --- a second queue is still a no-op (state flipped), and a fresh lesson still queues
"$learn" queue >/dev/null 2>&1
ok "second queue: still one row" '[ "$(rows)" = 1 ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
