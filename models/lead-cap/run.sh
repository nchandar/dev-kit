#!/usr/bin/env bash
# Run the clean and broken LeadClaim configs and compare each verdict to the rule
# it guards. Prints one line per config; full output goes to <cfg>.log (git-ignored).
# -deadlock is needed because a completed run is a legitimate terminal state.
# usage: ./run.sh [cfg...]   (from anywhere; no args runs the whole matrix)
set -u
here=$(cd "$(dirname "$0")" && pwd)
cd "$here" || exit 2
J=${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}
[ -f "$J" ] || { echo "run: no tla2tools.jar at $J (set TLA2TOOLS)" >&2; exit 2; }
rm -rf states; mkdir -p states
fail=0
run() { # $1=spec module  $2=cfg stem  $3=expected verdict regex
  local line rc
  java -XX:+UseParallelGC -cp "$J" tlc2.TLC -workers 4 -metadir "states/$2" \
    -deadlock -config "$2.cfg" "$1.tla" > "$2.log" 2>&1
  rc=$?
  line=$(grep -m1 -E '^Error: [A-Za-z].*|No error has been found' "$2.log" || true)
  if printf '%s' "$line" | grep -Eq -- "$3"; then
    printf 'ok   %-26s %s\n' "$2" "$line"
  else
    printf 'FAIL %-26s want /%s/ got: %s (rc=%s, log %s.log)\n' "$2" "$3" "${line:-no verdict}" "$rc" "$2"
    fail=$((fail+1))
  fi
}

# clean: cap 1 and 2, fairness, and the progress promise the fixed order keeps
run LeadClaim LeadClaim-cap1           'No error has been found'
run LeadClaim LeadClaim-cap2           'No error has been found'
run LeadClaim LeadClaim-live-cap1      'No error has been found'
run LeadClaim LeadClaim-live-cap2      'No error has been found'
run LeadClaim LeadClaim-progress-cap1  'No error has been found'
run LeadClaimChart LeadClaimChart      'No error has been found'
# broken copies, each must fail its guarded rule
run LeadClaimNoLock       broken-NoLock-cap1       'NoLostCandidate is violated'
run LeadClaimCountFirst   broken-CountFirst-cap1   'LeadsBounded is violated'
run LeadClaimNoLockSteal  broken-NoLockSteal-cap1  'Temporal properties were violated'
run LeadClaimCountStale   broken-CountStale-cap1   'CountsOnlyLive is violated'
run LeadClaimCountStale   broken-CountStale-live   'Temporal properties were violated'

[ "$fail" -eq 0 ] || { echo "run: $fail cfg(s) did not match" >&2; exit 1; }
