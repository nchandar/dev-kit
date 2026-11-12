#!/usr/bin/env bash
# Regression: a claimer stalled between its slot mkdir and its pid write must not let
# a reclaimer free the slot and a third spawner recreate it, so two live spawners hold
# one slot. claim(), slot_lock() and slot_live() are extracted verbatim from bin/spawn
# and run in three real processes; the only injection is a mkdir wrapper that sleeps
# after a successful mkdir, the same technique as the model's replay.sh.
# Usage: tests/spawn-slot-stall.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# --- the functions under test, copied from the real source (never edited here)
lib="$t/slot-lib.sh"
sed -n '/^slot_live() {/,/^}/p; /^slot_lock() {/,/^}/p; /^claim() {/,/^  done; return 1; }/p' "$spawn" > "$lib"
ok "slot_live, slot_lock and claim are extractable verbatim" \
  '[ "$(grep -c "^slot_live() {" "$lib")" -eq 1 ] && [ "$(grep -c "^slot_lock() {" "$lib")" -eq 1 ] && [ "$(grep -c "^claim() {" "$lib")" -eq 1 ] && [ "$(grep -c "done; return 1; }" "$lib")" -eq 1 ]'

# --- one real claimant: its own $$ is the pid claim() records, as a spawner's would be.
# The mkdir wrapper stalls after a successful mkdir only when the scenario asks for it.
cat > "$t/claimant.sh" <<'C'
#!/usr/bin/env bash
set -u
id=$1
. "$SLOT_LIB"
: "${RUN_DIR:?}"; CAP=${CAP:-2}; export H=$RUN_DIR CAP
mkdir() { /bin/mkdir "$@"; local rc=$?; [ $rc -eq 0 ] || return $rc; [ -z "${MKDIR_STALL:-}" ] || sleep "$MKDIR_STALL"; }
claim; rc=$?
if [ -n "${slot:-}" ]; then
  printf '%s %s %s\n' "$id" "$$" "${slot##*.}" >> "$H/holds"
  while [ ! -e "$H/stop" ]; do sleep 0.05; done # sleep-ok: bounded by the scenario's stop marker
else
  printf '%s %s none rc=%s\n' "$id" "$$" "$rc" >> "$H/missed"
fi
C
chmod +x "$t/claimant.sh"

run_claim() { # $1=plain|stalled: run three claimants, wait for each to finish, print sorted holds
  local run=$1 d="$t/run-$1" n=0
  rm -rf "$d"; mkdir -p "$d/run"
  export RUN_DIR="$d" CAP=2 SLOT_LIB="$lib"
  case $run in
    plain)
      bash "$t/claimant.sh" A & pa=$!
      bash "$t/claimant.sh" B & pb=$!
      bash "$t/claimant.sh" C & pc=$!
      ;;
    stalled) # A mkdirs slot.1 then stalls; B reclaims the empty dir; C recreates it; A writes late
      MKDIR_STALL=2.5 bash "$t/claimant.sh" A & pa=$!
      sleep 0.2 # sleep-ok: scenario timing, inside A's mkdir -> lock window
      bash "$t/claimant.sh" B & pb=$!
      sleep 1.3 # sleep-ok: scenario timing, C recreates the dir B emptied
      MKDIR_STALL=2.5 bash "$t/claimant.sh" C & pc=$!
      ;;
  esac
  while [ "$(cat "$d/holds" "$d/missed" 2>/dev/null | wc -l | tr -d ' ')" -lt 3 ] && [ "$n" -lt 200 ]; do sleep 0.05; n=$((n+1)); done # sleep-ok: bounded poll until all three claims resolve
  touch "$d/stop"
  wait $pa $pb $pc 2>/dev/null
  sort "$d/holds" 2>/dev/null
}

# --- the bug: a stall past the 1s grace let two claimants hold slot.1 (three holders for CAP 2)
st=$(run_claim stalled)
st_holds=$(printf '%s\n' "$st" | grep -c .)
st_dups=$(printf '%s\n' "$st" | awk '{print $3}' | sort | uniq -d | tr '\n' ' ')
ok "stalled: two claimants never hold one slot (double hold: ${st_dups:-none})" '[ -z "$st_dups" ]'
ok "stalled: at most CAP=2 claimants hold a slot (held: $st_holds)" '[ "$st_holds" -le 2 ]'
ok "stalled: all three claimants resolve (one may wait for a slot)" '[ "$st_holds" -ge 1 ] && [ "$(cat "$t/run-stalled/holds" "$t/run-stalled/missed" 2>/dev/null | wc -l | tr -d " ")" -eq 3 ]'

# --- control: no stall, the cap still admits two and turns one away
pl=$(run_claim plain)
pl_holds=$(printf '%s\n' "$pl" | grep -c .)
pl_dups=$(printf '%s\n' "$pl" | awk '{print $3}' | sort | uniq -d | tr '\n' ' ')
ok "plain: no two claimants hold one slot (double hold: ${pl_dups:-none})" '[ -z "$pl_dups" ]'
ok "plain: CAP=2 lets exactly two claimants hold a slot (held: $pl_holds)" '[ "$pl_holds" -eq 2 ]'
ok "plain: the third claimant is turned away, not double-held" '[ "$(grep -c " none " "$t/run-plain/missed" 2>/dev/null)" -eq 1 ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
