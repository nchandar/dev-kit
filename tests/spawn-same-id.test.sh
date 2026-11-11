#!/usr/bin/env bash
# Regression: one live spawn per worker id, from before the slot wait through cleanup.
# A retry or double launch must be refused instead of sharing the handoff, log, status and worktree.
# Usage: tests/spawn-same-id.test.sh  (fake CLI, scratch repo, no network)
set -u
unset DEVKIT_DEPTH  # these suites must pass when run from inside a worker too
unset CLAUDE_CODE_SESSION_ID
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
export DEVKIT_MODE=headless DEVKIT_TIMEOUT=0 DEVKIT_VIEW=off DEVKIT_VIEW_CLOSE_DELAY=0
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'pkill -9 -f "$t/fake" 2>/dev/null; rm -rf "$t"' EXIT
cd "$t" && git init -q && echo base > f.txt
cat > .gitignore <<'I'
/*.err
/*.rc
/*.hold
/fake
/brief*.md
I
git add -A && git -c user.name=t -c user.email=t@t commit -qm init
export DEVKIT_DIR="$t/.devkit"
# tripwire: a PATH-first fake herdr so a real one on the machine is never reached
tripwire="$t/tripwire"; mkdir -p "$tripwire"
export HERDR_TRIPWIRE_LOG="$t/herdr-tripwire.log"; : > "$HERDR_TRIPWIRE_LOG"
printf '#!/usr/bin/env bash\necho "$*" >> "$HERDR_TRIPWIRE_LOG"\nexit 1\n' > "$tripwire/herdr"
chmod +x "$tripwire/herdr"; export PATH="$tripwire:$PATH"
T=$("$ledger" start dup-id x); export DEVKIT_TASK=$T
TD="$DEVKIT_DIR/tasks/$T"; C="$TD/run"; E="$DEVKIT_DIR/events"
cat > "$t/fake" <<'F'
#!/usr/bin/env bash
echo "start ${FAKE_ID:-x} $$" >> "$DEVKIT_DIR/events"
echo $$ > "$DEVKIT_DIR/fakepid-${FAKE_ID:-x}"
[ -z "${FAKE_HOLD:-}" ] || while [ -e "$FAKE_HOLD" ]; do sleep 0.1; done # sleep-ok: bounded by the test, which removes the hold
printf 'ran %s\n\n## Checklist\n- [x] done\n' "${FAKE_ID:-x}" > "$2"
echo "end ${FAKE_ID:-x}" >> "$DEVKIT_DIR/events"
F
chmod +x "$t/fake"; export DEVKIT_FAKE="$t/fake"
echo "do the thing" > "$t/brief.md"; : > "$E"
waitfile() { local n=0; while [ ! -e "$1" ] && [ $n -lt 100 ]; do sleep 0.05; n=$((n+1)); done; } # sleep-ok: bounded poll
starts() { grep -c "^start $1 " "$E" 2>/dev/null; }
# a spawn in a subshell so its exit code lands in a file the test can poll (kill -0 stays true for a zombie)
dupspawn() { ( export FAKE_ID=dup FAKE_HOLD="$hold" DEVKIT_MAX_WORKERS=1
  "$spawn" dup fake "$t/brief.md" >/dev/null 2>"$t/$1.err"; echo $? > "$t/$1.rc" ) & }

# --- the bug: a duplicate queued behind a full pool both passes the guard and runs
hold="$t/a.hold"; : > "$hold"
FAKE_ID=blk FAKE_HOLD="$hold" DEVKIT_MAX_WORKERS=1 "$spawn" blk fake "$t/brief.md" >/dev/null 2>&1 & pblk=$!
waitfile "$DEVKIT_DIR/fakepid-blk"
dupspawn dup1; p1=$!
waitfile "$C/dup.claim"
dupspawn dup2; p2=$!
n=0; while [ ! -e "$t/dup2.rc" ] && [ $n -lt 40 ]; do sleep 0.05; n=$((n+1)); done # sleep-ok: bounded window the fix answers in
rm -f "$hold"; wait "$pblk" 2>/dev/null; wait "$p1" 2>/dev/null; wait "$p2" 2>/dev/null
rc2=$(cat "$t/dup2.rc" 2>/dev/null || echo missing)
ok "a duplicate spawn of a queued id is refused (exit 2)" '[ "$rc2" -eq 2 ]'
ok "the refusal keeps the existing 'already running' message" 'grep -qE "^spawn: dup is already running \(pid [0-9]+\); pick another id$" "$t/dup2.err"'
ok "only one worker of the id ever starts" '[ "$(starts dup)" -eq 1 ]'
ok "the refusal exits cleanly (one line, no cleanup noise)" '[ "$(wc -l < "$t/dup2.err" | tr -d " ")" -eq 1 ] && ! grep -q "command not found" "$t/dup2.err"'
ok "the surviving run still finishes with its own handoff" 'grep -q "^done 0" "$C/dup.status" && grep -q "ran dup" "$TD/handoffs/dup.md"'

# --- the claim is released on every normal exit path
FAKE_ID=solo "$spawn" solo fake "$t/brief.md"
ok "a normal run releases its claim" '[ ! -e "$C/solo.claim" ] && grep -q "^done 0" "$C/solo.status"'
FAKE_ID=solo "$spawn" solo fake "$t/brief.md"; rc=$?
ok "the same id can be spawned again once the first is done" '[ $rc -eq 0 ] && grep -q "^done 0" "$C/solo.status"'

# --- a stale claim (dead owner) must not block a respawn
mkdir -p "$C/dead.claim"; echo 99999999 > "$C/dead.claim/pid"
FAKE_ID=dead "$spawn" dead fake "$t/brief.md" 2>"$t/dead.err"; rc=$?
ok "a claim whose owner pid is dead is taken" '[ $rc -eq 0 ] && grep -q "^done 0" "$C/dead.status" && [ ! -e "$C/dead.claim" ]'

# --- a live claim refuses the duplicate and stays put
sleep 30 & owner=$! # sleep-ok: live claim owner fixture, killed right after
mkdir -p "$C/live.claim"; echo "$owner" > "$C/live.claim/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$owner" > "$C/live.claim/start"
before=$(starts live)
FAKE_ID=live "$spawn" live fake "$t/brief.md" 2>"$t/live.err"; rc=$?
ok "a live claim with a matching start refuses the duplicate (exit 2)" '[ $rc -eq 2 ] && grep -q "spawn: live is already running (pid $owner); pick another id" "$t/live.err"'
ok "the refused duplicate starts no worker and leaves the claim in place" '[ "$(starts live)" -eq "$before" ] && [ -e "$C/live.claim" ]'
kill "$owner" 2>/dev/null; wait "$owner" 2>/dev/null
rm -rf "$C/live.claim"

# --- a live pid whose start record differs was reused: the claim is reclaimed
sleep 30 & owner=$! # sleep-ok: reused-pid fixture, killed right after
mkdir -p "$C/reused.claim"; echo "$owner" > "$C/reused.claim/pid"; echo bogus > "$C/reused.claim/start"
FAKE_ID=reused "$spawn" reused fake "$t/brief.md" 2>"$t/reused.err"; rc=$?
kill "$owner" 2>/dev/null; wait "$owner" 2>/dev/null
ok "a claim whose owner pid was reused is reclaimed" '[ $rc -eq 0 ] && grep -q "^done 0" "$C/reused.status"'

# --- kill -9 of the spawner: its worker still runs, so the id stays held until the worker is gone
sleep 30 & worker=$! # sleep-ok: live worker fixture, killed right after
mkdir -p "$C/orph.claim"; echo 99999999 > "$C/orph.claim/pid"; echo "$worker" > "$C/orph.claim/wpid"
FAKE_ID=orph "$spawn" orph fake "$t/brief.md" 2>"$t/orph.err"; rc=$?
ok "a dead spawner's live worker keeps the id held" '[ $rc -eq 2 ] && grep -q "already running" "$t/orph.err"'
kill "$worker" 2>/dev/null; wait "$worker" 2>/dev/null
FAKE_ID=orph "$spawn" orph fake "$t/brief.md"; rc=$?
ok "once that worker is gone too, the id is usable again" '[ $rc -eq 0 ] && grep -q "^done 0" "$C/orph.status"'

# --- an interrupted queued spawn releases its claim instead of wedging the id
hold="$t/b.hold"; : > "$hold"
FAKE_ID=b2 FAKE_HOLD="$hold" DEVKIT_MAX_WORKERS=1 "$spawn" b2 fake "$t/brief.md" >/dev/null 2>&1 & pb=$!
waitfile "$DEVKIT_DIR/fakepid-b2"
FAKE_ID=q FAKE_HOLD="$hold" DEVKIT_MAX_WORKERS=1 "$spawn" q fake "$t/brief.md" >/dev/null 2>&1 & pq=$!
waitfile "$C/q.claim/pid" # the claim is complete before the signal, so this pins the claimed exit path
kill -TERM "$pq" 2>/dev/null; wait "$pq" 2>/dev/null
ok "an interrupted queued spawn releases its claim" '[ ! -e "$C/q.claim" ]'
rm -f "$hold"; wait "$pb" 2>/dev/null
FAKE_ID=q "$spawn" q fake "$t/brief.md"; rc=$?
ok "the interrupted id is usable again" '[ $rc -eq 0 ] && grep -q "^done 0" "$C/q.status"'

# --- claims are per task: one task's live claim cannot block the same id in another task
TB=$("$ledger" start other-task y); TBD="$DEVKIT_DIR/tasks/$TB"
sleep 30 & owner=$! # sleep-ok: live claim fixture, killed right after
mkdir -p "$C/iso.claim"; echo "$owner" > "$C/iso.claim/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$owner" > "$C/iso.claim/start"
DEVKIT_TASK=$TB FAKE_ID=iso "$spawn" iso fake "$t/brief.md"; rc=$?
kill "$owner" 2>/dev/null; wait "$owner" 2>/dev/null
ok "the same id in another task is not blocked by this task's claim" '[ $rc -eq 0 ] && [ -s "$TBD/handoffs/iso.md" ] && [ ! -e "$TBD/run/iso.claim" ]'
rm -rf "$C/iso.claim"

ok "no claim or slot is left behind" '[ -z "$(ls -d "$C"/*.claim "$DEVKIT_DIR"/run/slot.* 2>/dev/null)" ]'
ok "no call escaped to the tripwire herdr (real herdr never reached)" '[ ! -s "$HERDR_TRIPWIRE_LOG" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
