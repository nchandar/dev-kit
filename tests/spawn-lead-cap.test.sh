#!/usr/bin/env bash
# Regression: the --lead cap counted live leads and then started, with no atomic claim, so two
# simultaneous lead spawns both passed DEVKIT_MAX_LEADS and ran. A lead now claims its place
# under a repo-wide owner lock before the count, and releases it on every exit path.
# Usage: tests/spawn-lead-cap.test.sh  (fake CLI, scratch repo, no network)
set -u
unset DEVKIT_DEPTH  # these suites must pass when run from inside a worker too
unset CLAUDE_CODE_SESSION_ID
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_LEADS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
export DEVKIT_MODE=headless DEVKIT_TIMEOUT=0 DEVKIT_VIEW=off DEVKIT_VIEW_CLOSE_DELAY=0
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'pkill -9 -f "$t/fake" 2>/dev/null; rm -rf "$t"' EXIT
cd "$t" && git init -q -b main && echo base > f.txt
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
T=$("$ledger" start lead-cap x); export DEVKIT_TASK=$T
TD="$DEVKIT_DIR/tasks/$T"; C="$TD/run"; E="$DEVKIT_DIR/events"
cat > "$t/fake" <<'F'
#!/usr/bin/env bash
echo "start ${FAKE_ID:-x} $$" >> "$DEVKIT_DIR/events"
: > "$DEVKIT_DIR/started-${FAKE_ID:-x}"
[ -z "${FAKE_HOLD:-}" ] || while [ -e "$FAKE_HOLD" ]; do sleep 0.1; done # sleep-ok: bounded by the test, which removes the hold
printf 'ran %s\n\n## Checklist\n- [x] done\n' "${FAKE_ID:-x}" > "$2"
F
chmod +x "$t/fake"; export DEVKIT_FAKE="$t/fake"
echo "do the thing" > "$t/brief.md"; : > "$E"
starts() { grep -c "^start $1 " "$E" 2>/dev/null; }
waitstart() { local n=0; while [ ! -e "$DEVKIT_DIR/started-$1" ] && [ $n -lt 100 ]; do sleep 0.05; n=$((n+1)); done; } # sleep-ok: bounded poll
leads() { ( export FAKE_ID=$1 FAKE_HOLD=$2 DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=$3
  "$spawn" --lead "$1" fake "$t/brief.md" >/dev/null 2>"$t/$1.err"; echo $? > "$t/$1.rc" ) & }

# --- the bug: two simultaneous --lead spawns at cap 1. No stagger, no shim: the loser must
#     refuse while the winner is still waiting for its worker, not only after a marker exists.
hold="$t/race.hold"; : > "$hold"
leads ra "$hold" 1; pra=$!
leads rb "$hold" 1; prb=$!
n=0
while [ $n -lt 100 ]; do
  [ -e "$t/ra.rc" ] && break
  [ -e "$t/rb.rc" ] && break
  [ -e "$DEVKIT_DIR/started-ra" ] && [ -e "$DEVKIT_DIR/started-rb" ] && break
  sleep 0.05; n=$((n+1)) # sleep-ok: bounded poll for the first resolution
done
rm -f "$hold"; wait "$pra" 2>/dev/null; wait "$prb" 2>/dev/null
rca=$(cat "$t/ra.rc" 2>/dev/null || echo missing); rcb=$(cat "$t/rb.rc" 2>/dev/null || echo missing)
sra=$(starts ra); srb=$(starts rb)
ok "two simultaneous --lead spawns at cap 1 start exactly one worker" '{ [ "$sra" -eq 1 ] && [ "$srb" -eq 0 ]; } || { [ "$sra" -eq 0 ] && [ "$srb" -eq 1 ]; }'
ok "exactly one of them exits 4 and the other exits 0" '{ [ "$rca" -eq 4 ] && [ "$rcb" -eq 0 ]; } || { [ "$rca" -eq 0 ] && [ "$rcb" -eq 4 ]; }'
if [ "$rca" = 4 ]; then lid=ra; else lid=rb; fi
ok "the refusal keeps the existing message and exit code" 'grep -qx "spawn: 1 live lead(s) already, at the limit DEVKIT_MAX_LEADS=1; wait for one to finish or raise it" "$t/$lid.err"'
ok "the refused lead made no worktree" '[ ! -e "$TD/wt/$lid" ]'
ok "the refused lead left no claim behind" '[ ! -e "$C/$lid.lead" ]'
ok "the winner released its claim when it finished" '[ -z "$(ls "$C"/*.lead 2>/dev/null)" ]'

# --- cap N: two leads fit, the third is refused with the same wording
holdn="$t/n.hold"; : > "$holdn"
FAKE_ID=n1 FAKE_HOLD="$holdn" DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=2 "$spawn" --lead n1 fake "$t/brief.md" >/dev/null 2>&1 & pn1=$!
waitstart n1
FAKE_ID=n2 FAKE_HOLD="$holdn" DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=2 "$spawn" --lead n2 fake "$t/brief.md" >/dev/null 2>&1 & pn2=$!
waitstart n2
DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=2 "$spawn" --lead n3 fake "$t/brief.md" >/dev/null 2>"$t/n3.err"; rc=$?
ok "a third lead past a cap of 2 exits 4" '[ "$rc" -eq 4 ]'
ok "the cap-2 message counts two live leads" 'grep -qx "spawn: 2 live lead(s) already, at the limit DEVKIT_MAX_LEADS=2; wait for one to finish or raise it" "$t/n3.err"'
ok "the refused third lead made no worktree" '[ ! -e "$TD/wt/n3" ] && [ ! -e "$C/n3.lead" ]'
rm -f "$holdn"; wait "$pn1" 2>/dev/null; wait "$pn2" 2>/dev/null
FAKE_ID=n4 DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=2 "$spawn" --lead n4 fake "$t/brief.md" >/dev/null 2>&1; rc=$?
ok "a finished lead frees its place for the next one" '[ "$rc" -eq 0 ] && [ ! -e "$C/n4.lead" ]'

# --- a dead owner's claim is reclaimed instead of blocking the next lead
mkdir -p "$C/dead.lead"; echo 99999999 > "$C/dead.lead/pid"; echo bogus > "$C/dead.lead/start"
FAKE_ID=dead DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" --lead dead fake "$t/brief.md" 2>"$t/dead.err"; rc=$?
ok "a dead lead's claim does not block (taken over, then released)" '[ "$rc" -eq 0 ] && [ ! -e "$C/dead.lead" ]'

# --- a live pid whose start record differs was reused: the claim is reclaimed
sleep 30 & owner=$! # sleep-ok: reused-pid fixture, killed right after
mkdir -p "$C/reused.lead"; echo "$owner" > "$C/reused.lead/pid"; echo bogus > "$C/reused.lead/start"
FAKE_ID=reused DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" --lead reused fake "$t/brief.md" 2>"$t/reused.err"; rc=$?
kill "$owner" 2>/dev/null; wait "$owner" 2>/dev/null
ok "a reused owner pid's claim is reclaimed" '[ "$rc" -eq 0 ] && [ ! -e "$C/reused.lead" ]'

# --- a dead spawner's live worker keeps the lead place (same rule as the slot and id claims)
sleep 30 & worker=$! # sleep-ok: live worker fixture, killed right after
mkdir -p "$C/held.lead"; echo 99999999 > "$C/held.lead/pid"; echo "$worker" > "$C/held.lead/wpid"
FAKE_ID=fresh DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" --lead fresh fake "$t/brief.md" 2>"$t/fresh.err"; rc=$?
ok "a dead spawner's live worker still counts against the cap (exit 4)" '[ "$rc" -eq 4 ] && grep -q "1 live lead" "$t/fresh.err"'
kill "$worker" 2>/dev/null; wait "$worker" 2>/dev/null
FAKE_ID=fresh DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" --lead fresh fake "$t/brief.md" >/dev/null 2>&1; rc=$?
ok "once that worker is gone too, the stale place is reclaimed" '[ "$rc" -eq 0 ] && [ ! -e "$C/fresh.lead" ] && [ ! -e "$C/held.lead" ]'

# --- a duplicate of a live lead id keeps the exit 2 and 'already running' message
sleep 30 & dupowner=$! # sleep-ok: live claim owner fixture, killed right after
mkdir -p "$C/dup.lead"; echo "$dupowner" > "$C/dup.lead/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$dupowner" > "$C/dup.lead/start"
FAKE_ID=dup DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" --lead dup fake "$t/brief.md" 2>"$t/dup.err"; rc=$?
ok "a duplicate live lead id exits 2 with the existing message" '[ "$rc" -eq 2 ] && grep -qx "spawn: dup is already running (pid $dupowner); pick another id" "$t/dup.err"'
ok "the live lead's claim is left alone" '[ -d "$C/dup.lead" ]'
kill "$dupowner" 2>/dev/null; wait "$dupowner" 2>/dev/null; rm -rf "$C/dup.lead"

# --- a signalled lead releases its place
holdt="$t/t.hold"; : > "$holdt"
FAKE_ID=intr FAKE_HOLD="$holdt" DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" --lead intr fake "$t/brief.md" >/dev/null 2>&1 & pi=$!
waitstart intr
ok "a live lead holds its claim while it runs" '[ -d "$C/intr.lead" ]'
kill -TERM "$pi" 2>/dev/null; wait "$pi" 2>/dev/null; rm -f "$holdt"
ok "a signalled lead releases its claim" '[ ! -e "$C/intr.lead" ]'

# --- non-lead spawns are not bound by the lead cap
holdl="$t/l.hold"; : > "$holdl"
FAKE_ID=keep FAKE_HOLD="$holdl" DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" --lead keep fake "$t/brief.md" >/dev/null 2>&1 & pk=$!
waitstart keep
FAKE_ID=plain DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 "$spawn" plain fake "$t/brief.md" 2>"$t/plain.err"; rc=$?
ok "a non-lead spawn still runs while a lead holds the only place" '[ "$rc" -eq 0 ] && [ ! -e "$TD/wt/plain" ]'
rm -f "$holdl"; wait "$pk" 2>/dev/null

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
