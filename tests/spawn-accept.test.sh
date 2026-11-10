#!/usr/bin/env bash
# Tests for the stop-gate accept protocol: spawn's start/exit ledger rows and status order.
# Usage: tests/spawn-accept.test.sh
set -u
unset DEVKIT_DEPTH DEVKIT_TASK CLAUDE_CODE_SESSION_ID  # the suite must run inside a worker too
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); sp=
trap '[ -z "${sp:-}" ] || kill -9 "$sp" 2>/dev/null; pkill -9 -f "$t/fake" 2>/dev/null; rm -rf "$t"' EXIT
cd "$t" && git init -q && echo base > f.txt && git add f.txt && git -c user.name=t -c user.email=t@t commit -qm init
echo "do the thing" > "$t/brief.md"
export DEVKIT_DIR="$t/.devkit" DEVKIT_MODE=headless DEVKIT_VIEW=off DEVKIT_TIMEOUT=0
T=$("$here/bin/ledger" start accept-gate x); export DEVKIT_TASK=$T
TD=$DEVKIT_DIR/tasks/$T
cat > "$t/fake" <<'F'
#!/usr/bin/env bash
echo $$ > "$DEVKIT_DIR/fakepid.${FAKE_ID:-x}"
[ -z "${FAKE_HOLD:-}" ] || while [ -e "$FAKE_HOLD" ]; do sleep 0.05; done # sleep-ok: bounded poll until the test releases the stub
sleep "${FAKE_SLEEP:-0}"
[ -n "${FAKE_NOHANDOFF:-}" ] || printf 'stub handoff\n## Checklist\n- [x] 1. done\n' > "$2"
F
chmod +x "$t/fake"; export DEVKIT_FAKE="$t/fake"

# A copy of bin/ whose ledger can hold one chosen row: that makes the status-vs-row
# window deterministic instead of a race.
BIN="$t/bin"; cp -R "$here/bin/." "$BIN"/
cat > "$BIN/ledger" <<'L'
#!/usr/bin/env bash
if [ "${GATE_BLOCK_ON:-0}" = 1 ] && printf '%s' "$*" | grep -qF -- " $GATE_BLOCK_ROW "; then
  echo 1 > "$GATE_BLOCK_MARKER"
  n=0; while [ ! -e "$GATE_BLOCK_RELEASE" ] && [ "$n" -lt 400 ]; do sleep 0.05; n=$((n+1)); done # sleep-ok: bounded poll for the test's release file
fi
exec "$GATE_REAL_LEDGER" "$@"
L
chmod +x "$BIN/ledger"
export GATE_REAL_LEDGER="$here/bin/ledger" GATE_BLOCK_ON=0

status() { cut -d' ' -f1 "$TD/run/$1.status" 2>/dev/null; }
waitfor() { local i; for i in $(seq 1 300); do [ "$(status "$1")" = "$2" ] && return 0; sleep 0.05; done; return 1; } # sleep-ok: bounded poll for a status the stub sets
waitfile() { local i; for i in $(seq 1 300); do [ -e "$1" ] && return 0; sleep 0.05; done; return 1; } # sleep-ok: bounded poll for the test's marker file
start_held() { : > "$t/hold.$1"; FAKE_ID=$1 FAKE_HOLD="$t/hold.$1" "$BIN/spawn" "$1" fake "$t/brief.md" > "$t/$1.out" 2>&1 & sp=$!; waitfor "$1" running; }
start_plain() { FAKE_ID=$1 "$BIN/spawn" "$1" fake "$t/brief.md" > "$t/$1.out" 2>&1 & sp=$!; }
release() { rm -f "$t/hold.$1"; wait "$sp" 2>/dev/null; sp=; }
accept() { "$here/bin/ledger" -t "$T" accept "$1 accepted" "checked"; }
gate() { out=$(DEVKIT_TASK=$T "$BIN/reconcile" --gate 2>&1); grc=$?; }
block() { GATE_BLOCK_ROW=$1 GATE_BLOCK_MARKER="$t/m.$2" GATE_BLOCK_RELEASE="$t/r.$2" GATE_BLOCK_ON=1; export GATE_BLOCK_ROW GATE_BLOCK_MARKER GATE_BLOCK_RELEASE GATE_BLOCK_ON; }
unblock() { GATE_BLOCK_ON=0; export GATE_BLOCK_ON; : > "${GATE_BLOCK_RELEASE:-/dev/null}"; }

# --- S0, what must not change: run, accept, respawn, run
start_held w1; ok "S0: a held worker is running" '[ "$(status w1)" = running ]'
gate; ok "S0: running worker blocks" '[ "$grc" -eq 1 ] && echo "$out" | grep -q "w1 running"'
release w1; ok "S0: run 1 finished" '[ "$(status w1)" = done ]'
gate; ok "S0: finished, unaccepted blocks" '[ "$grc" -eq 1 ] && echo "$out" | grep -q "w1 done, unaccepted"'
accept w1; gate; ok "S0: accept clears the gate" '[ "$grc" -eq 0 ] && [ -z "$out" ]'
start_held w1; ok "S0: the respawn is running again" '[ "$(status w1)" = running ]'
gate; ok "S0: a respawn blocks while it runs" '[ "$grc" -eq 1 ] && echo "$out" | grep -q "w1 running"'
release w1; gate; ok "S0: the respawn needs its own accept" '[ "$grc" -eq 1 ] && echo "$out" | grep -q "w1 done, unaccepted"'
accept w1; gate; ok "S0: the second accept clears it" '[ "$grc" -eq 0 ]'

# --- F2: kill -9 after a respawn leaves no exit row; the start row must outdate the old accept
start_plain w2; wait "$sp" 2>/dev/null; sp=; accept w2
gate; ok "F2 setup: the first run is accepted" '[ "$grc" -eq 0 ]'
start_held w2; waitfor w2 running
ok "F2: a respawn writes a start row" 'grep -qE "^[^\t]*\tspawn\tw2 running\t" "$TD/ledger.tsv"'
kill -9 "$sp" 2>/dev/null; wait "$sp" 2>/dev/null; sp=
[ ! -s "$DEVKIT_DIR/fakepid.w2" ] || kill -9 "$(cat "$DEVKIT_DIR/fakepid.w2")" 2>/dev/null
rm -rf "$DEVKIT_DIR"/run/slot.*
gate
ok "F2: a killed respawn reads killed, not its old accept" '[ "$grc" -eq 1 ] && echo "$out" | grep -q "w2 killed, unaccepted"'
accept w2 # keep the fixture clean for the next scenario

# --- F1: respawn after an accept; the old accept must not clear the exit window
start_plain w3; wait "$sp" 2>/dev/null; sp=; accept w3
block "spawn w3 done" f1
export CLAUDE_CODE_SESSION_ID=sess-f1
start_held w3; waitfor w3 running; rm -f "$t/hold.w3"; waitfile "$t/m.f1"
ok "F1: the terminal status is not published before the exit row" '[ "$(status w3)" = running ]'
gate; ok "F1: the exit window is not accepted on the old run" '[ "$grc" -eq 1 ]'
hook=$(printf '{"session_id":"sess-f1"}' | "$BIN/stop-gate" 2>&1); hrc=$?
ok "F1: the stop hook blocks in the exit window" '[ "$hrc" -eq 2 ]'
unset CLAUDE_CODE_SESSION_ID
unblock f1; wait "$sp" 2>/dev/null; sp=
gate; ok "F1: after the exit row the respawn still needs an accept" '[ "$grc" -eq 1 ] && echo "$out" | grep -q "w3 done, unaccepted"'
accept w3; gate; ok "F1: the new accept clears it" '[ "$grc" -eq 0 ]'

# --- F3: an accept of a finished worker must not be outranked by a later exit row
block "spawn w4 done" f3
start_held w4; waitfor w4 running; rm -f "$t/hold.w4"; waitfile "$t/m.f3"
accepted=0
if [ "$(status w4)" = done ]; then accept w4; accepted=1; fi # the old order publishes done first
unblock f3; wait "$sp" 2>/dev/null; sp=
waitfor w4 done || true
[ "$accepted" = 1 ] || accept w4 # the new order publishes the row first
gate; ok "F3: an accept of a finished worker is not outranked" '[ "$grc" -eq 0 ] && [ "$(status w4)" = done ]'
accept w4 # keep the fixture clean for the next scenario

# --- same fault class: the interrupt path also wrote status before its killed row
block "spawn w5 killed" km
start_held w5; waitfile "$DEVKIT_DIR/fakepid.w5"
kill -TERM "$sp" 2>/dev/null; waitfile "$t/m.km"
ok "killed: the killed status is not published before its row" '[ "$(status w5)" != killed ] && [ -n "$(status w5)" ]'
unblock km; wait "$sp" 2>/dev/null; sp=
ok "killed: the interrupt still lands as killed" '[ "$(status w5)" = killed ]'
gate; ok "killed: an interrupted worker still needs an accept" '[ "$grc" -eq 1 ] && echo "$out" | grep -q "w5 killed, unaccepted"'
accept w5; gate; ok "killed: the accept clears it" '[ "$grc" -eq 0 ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
