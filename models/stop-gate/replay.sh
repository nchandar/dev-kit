#!/usr/bin/env bash
# Replay of the StopGate.tla counterexamples against the real scripts.
# Everything runs in a scratch DEVKIT_DIR here; the repo is read-only. A scratch copy
# of bin/ is used only for the three injected variants (stall before the exit row,
# stall before the status write, status written before the exit row, no start row).
# usage: ./replay.sh
set -u
unset DEVKIT_DEPTH DEVKIT_TASK DEVKIT_WORKER CLAUDE_CODE_SESSION_ID
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../.." && pwd)   # the repo under test is the one holding models/
[ -x "$REPO/bin/spawn" ] || { echo "replay: no bin/spawn in $REPO" >&2; exit 2; }
SC=$here/scratch
rm -rf "$SC"; mkdir -p "$SC"
cp -R "$REPO/bin/." "$SC/bin"/
chmod +x "$SC"/bin/*
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }

# the fake CLI: records its pid, holds while FAKE_HOLD exists, sleeps FAKE_SLEEP, writes the handoff
cat > "$SC/fake" <<'F'
#!/usr/bin/env bash
echo $$ > "$DEVKIT_DIR/fakepid.${FAKE_ID:-x}"
[ -z "${FAKE_HOLD:-}" ] || while [ -e "$FAKE_HOLD" ]; do sleep 0.05; done # sleep-ok: bounded poll on the test's release file
sleep "${FAKE_SLEEP:-0}"
printf 'stub handoff\n## Checklist\n- [x] 1. done\n' > "$2"
F
chmod +x "$SC/fake"

# --- injected variants of the real spawn (scratch copy only) -----------------
python3 - "$SC" <<'PY'
import sys
sc = sys.argv[1]
src = open(sc + "/bin/spawn").read()
row = '# publish the terminal row before the status: a parent may only see done after its row exists\n'
assert row in src
# V1: stall before the exit row -> the accept window of R3
v = src.replace(row, 'sleep "${STALL:-0}" # injected: before the exit row\n' + row)
open(sc + "/bin/spawn-stallrow", "w").write(v)
# V2: stall before the status write -> the respawn guard window of :275
mark = 'echo "$state $rc $(date +%s)" > "$st"'
assert src.count(mark) == 1
v = src.replace(mark, 'sleep "${STALL:-0}" # injected: before the status write\n' + mark)
open(sc + "/bin/spawn-stallstatus", "w").write(v)
# V3 (broken order, pre-PR-25): the status write moves above the exit row
i = src.index(row); j = src.index(mark, i)
block = src[i:j]
v = src[:i] + mark + "\nsleep \"${STALL:-0}\" # injected: between the status and the exit row\n" + block + src[j + len(mark):]
open(sc + "/bin/spawn-statusfirst", "w").write(v)
# V5: stall after the status write and before the worker launch -> :481..:616
mark413 = 'rm -f "$hf" "$T/run/$id.timedout"; echo "running $$ $(date +%s)" > "$st"'
assert mark413 in src
open(sc + "/bin/spawn-stallafterstatus", "w").write(
    src.replace(mark413, mark413 + '\nsleep "${STALL:-0}" # injected: before the worker launch'))
# V4 (broken): no start row at :410, so an earlier accept still counts
start = '''# a start row outdates any earlier accept: a respawn is unreviewed even if it dies without its exit row
if ! "$here/ledger" -t "$task" spawn "$id running" "cli=$cli shape=$shape parent=${DEVKIT_WORKER:-main}" "${brief:-$T/briefs/$id.md}" running 2>/dev/null; then
  echo "spawn: cannot record the start row for $id; not starting it" >&2; exit 2
fi
'''
assert start in src
open(sc + "/bin/spawn-nostart", "w").write(src.replace(start, ""))
PY
chmod +x "$SC"/bin/spawn-*

echo "## setup"
cd "$SC" && git init -q . && echo base > f.txt && git add f.txt && git -c user.name=t -c user.email=t@t commit -qm init
echo "do the thing" > "$SC/brief.md"
mkdir -p "$SC/home"
export HOME="$SC/home" # never the real HOME: nothing here may touch the user install
export DEVKIT_DIR="$SC/dk" DEVKIT_MODE=headless DEVKIT_VIEW=off DEVKIT_TIMEOUT=0 DEVKIT_FAKE="$SC/fake" \
       CLAUDE_CODE_SESSION_ID=sess PATH="$SC:$PATH"
mkdir -p "$SC/dk/run"
T=; sp=
newtask() { T=$("$SC/bin/ledger" start "$1" x); export DEVKIT_TASK=$T; rm -f "$DEVKIT_DIR/run/gate-sess.count"; }
status() { cut -d' ' -f1 "$DEVKIT_DIR/tasks/$T/run/$1.status" 2>/dev/null; }
waitfor() { local i; for i in $(seq 1 400); do [ "$(status "$1")" = "$2" ] && return 0; sleep 0.05; done; echo "  (timeout waiting $1=$2)"; return 1; } # sleep-ok: bounded poll
waitfake() { local i; for i in $(seq 1 400); do [ -e "$DEVKIT_DIR/fakepid.$1" ] && return 0; sleep 0.05; done; return 1; } # sleep-ok: bounded poll
waithandoff() { local i; for i in $(seq 1 400); do [ -s "$DEVKIT_DIR/tasks/$T/handoffs/$1.md" ] && return 0; sleep 0.05; done; echo "  (timeout waiting the handoff of $1)"; return 1; } # sleep-ok: bounded poll
waitrow() { local i; for i in $(seq 1 400); do rows | grep -q "$1" && return 0; sleep 0.05; done; return 1; } # sleep-ok: bounded poll
rows() { cut -f2,3 "$DEVKIT_DIR/tasks/$T/ledger.tsv" 2>/dev/null | tail -n +2; }
gate() { out=$("$SC/bin/reconcile" --gate -t "$T" 2>&1); grc=$?; }
hook() { hout=$(printf '{"session_id":"sess"}' | "$SC/bin/stop-gate" 2>&1); hrc=$?; }
start_held() { local id=$1; : > "$SC/hold.$id"; FAKE_ID=$id FAKE_HOLD="$SC/hold.$id" "$SC/bin/$2" "$id" fake "$SC/brief.md" > "$SC/$id.out" 2>&1 & sp=$!; waitfor "$id" running; }
start_plain() { local id=$1; FAKE_ID=$id "$SC/bin/$2" "$id" fake "$SC/brief.md" > "$SC/$id.out" 2>&1 & sp=$!; }
release() { rm -f "$SC/hold.$1"; wait "$sp" 2>/dev/null; sp=; }
accept() { "$SC/bin/ledger" -t "$T" accept "$1 accepted" "read the handoff"; }

echo "## C1 R1/R5: the running check blocks a stop even with an accept row (reconcile:30)"
newtask c1; start_held w1 spawn
accept w1; ok "C1: an accept can be appended while the worker runs" 'rows | grep -q "w1 accepted"'
gate; ok "C1: the gate still reports it running" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 running"'
hook; ok "C1: the stop hook blocks (rc 2)" '[ $hrc -eq 2 ]'
release w1; gate; ok "C1: after the exit row, the mid-run accept is stale" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 done, unaccepted"'
accept w1; gate; ok "C1: a fresh accept clears the gate" '[ $grc -eq 0 ] && [ -z "$out" ]'

echo "## C2 R2: an accept of run 1 never covers run 2 (spawn:478 start row)"
newtask c2; start_plain w1 spawn; wait "$sp"; sp=
waitfor w1 done; accept w1; gate; ok "C2: run 1 accepted, gate clear" '[ $grc -eq 0 ]'
start_held w1 spawn; gate; ok "C2: the respawn blocks while it runs" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 running"'
release w1; waitfor w1 done; gate; ok "C2: run 2 needs its own accept" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 done, unaccepted"'
accept w1; gate; ok "C2: accepting run 2 clears it" '[ $grc -eq 0 ]'

echo "## C2b kill -9 after an accept: the start row keeps run 2 unreviewed"
newtask c2b; start_plain w1 spawn; wait "$sp"; sp=
waitfor w1 done; accept w1; gate; ok "C2b: run 1 accepted" '[ $grc -eq 0 ]'
start_held w1 spawn; kill -9 "$sp" 2>/dev/null; kill -9 "$(cat "$DEVKIT_DIR/fakepid.w1" 2>/dev/null)" 2>/dev/null; wait "$sp" 2>/dev/null; sp=
gate; ok "C2b: the real spawn keeps run 2 unreviewed" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "unaccepted"'
newtask c2c; start_plain w1 spawn-nostart; wait "$sp"; sp=
waitfor w1 done; accept w1; gate; ok "C2c: run 1 accepted" '[ $grc -eq 0 ]'
start_held w1 spawn-nostart; kill -9 "$sp" 2>/dev/null; kill -9 "$(cat "$DEVKIT_DIR/fakepid.w1" 2>/dev/null)" 2>/dev/null; wait "$sp" 2>/dev/null; sp=
gate; ok "C2c: without the start row the stale accept clears the gate" '[ $grc -eq 0 ]'

echo "## C3 R3: an early accept is a false block; the current order hides it behind the running check"
newtask c3; STALL=6 start_plain w1 spawn-stallrow; waithandoff w1; sleep 0.5 # sleep-ok: let spawn reach the injected stall
# status is still "running" while the exit row is pending: the current order (row before status)
gate; ok "C3: in the window the gate says running, not accepted" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 running"'
accept w1; gate; ok "C3: the early accept does not clear it" '[ $grc -eq 1 ]'
wait "$sp"; sp=; gate; ok "C3: after the row the worker is unaccepted until a fresh accept" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 done, unaccepted"'
accept w1; gate; ok "C3: a fresh accept clears it" '[ $grc -eq 0 ]'
newtask c3b; STALL=6 start_plain w1 spawn-statusfirst; waitfor w1 done
gate; ok "C3b broken order: the window shows done, unaccepted" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 done, unaccepted"'
accept w1; gate; ok "C3b broken order: the early accept clears the gate" '[ $grc -eq 0 ]'
wait "$sp"; sp=; gate; ok "C3b broken order: the exit row then invalidates it (NoFalseBlock)" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 done, unaccepted"'

echo "## C4 R4: fail-open only after the 3 blocks (stop-gate:17-27)"
newtask c4; start_held w1 spawn
hook; r1=$hrc; hook; r2=$hrc; hook; r3=$hrc; hook; r4=$hrc
ok "C4: the first three stops are blocked (rc 2,2,2)" '[ "$r1$r2$r3" = 222 ]'
ok "C4: the fourth fails open (rc 0)" '[ "$r4" -eq 0 ]'
ok "C4: the fail-open is ledgered" 'rows | grep -q "fail-open"'
release w1

echo "## C5 timeout: the kill leaves a timeout row and an unaccepted worker (spawn:581,623-630)"
newtask c5; FAKE_SLEEP=30 DEVKIT_TIMEOUT=2 FAKE_ID=w1 "$SC/bin/spawn" w1 fake "$SC/brief.md" > "$SC/w1.out" 2>&1 & sp=$!
waitfor w1 timeout; wait "$sp"; sp=
ok "C5: status is timeout" '[ "$(status w1)" = timeout ]'
ok "C5: the timeout row counts as an exit row" 'rows | grep -q "w1 timeout"'
gate; ok "C5: unaccepted until the parent accepts" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 timeout, unaccepted"'
accept w1; gate; ok "C5: accepting clears it" '[ $grc -eq 0 ]'

echo "## C6 killed row: a signal writes a killed row before the status (spawn:431-437)"
newtask c6; start_held w1 spawn; waitfake w1; sleep 0.2 # sleep-ok: past the :481..:616 window where no killed row exists
kill -TERM "$sp" 2>/dev/null; wait "$sp" 2>/dev/null; sp=
waitfor w1 killed; ok "C6: status is killed" '[ "$(status w1)" = killed ]'; echo "  dbg: status=$(status w1) sp=$sp rows=$(rows | tr "\n" "|")"
ok "C6: the killed row counts as an exit row" 'rows | grep -q "w1 killed"'
gate; ok "C6: unaccepted until the parent accepts" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "w1 killed, unaccepted"'
accept w1; gate; ok "C6: accepting clears it" '[ $grc -eq 0 ]'

echo "## C7 respawn guard: a respawn is refused while the old spawn's status still says running (spawn:275)"
newtask c7; STALL=6 start_plain w1 spawn-stallstatus; waitrow "w1 done"; sleep 0.3 # sleep-ok: the row lands before the status
ok "C7: status still says running in the exit window" '[ "$(status w1)" = running ]'
"$SC/bin/spawn" w1 fake "$SC/brief.md" > "$SC/w1b.out" 2>&1; rc=$?
ok "C7: the second spawn is refused (exit 2, already running)" '[ $rc -eq 2 ] && grep -q "already running" "$SC/w1b.out"'
wait "$sp"; sp=; waitfor w1 done; ok "C7: the first spawn then publishes status done" '[ "$(status w1)" = done ]'

echo "## C8 the :481..:616 window: a signal before the worker launch leaves no killed row"
newtask c8; STALL=6 start_plain w1 spawn-stallafterstatus; waitfor w1 running; sleep 0.3 # sleep-ok: inside the injected stall
kill -TERM "$sp" 2>/dev/null; wait "$sp" 2>/dev/null; sp=
ok "C8: status stays running (no terminal status write)" '[ "$(status w1)" = running ]'
ok "C8: no killed row is written" '! rows | grep -q "w1 killed"'
gate; ok "C8: the gate still blocks (unaccepted)" '[ $grc -eq 1 ] && printf "%s" "$out" | grep -q "unaccepted"'
echo "  note: this is the model's no-row kill (Kill9); it breaks no rule, the gate blocks"

echo "## result: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
