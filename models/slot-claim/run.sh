#!/usr/bin/env bash
# Run one TLC config per line and compare the verdict to what the model promises.
# Clean configs must pass; every broken variant must fail the rule it guards.
# Full output goes to <spec>-<cfg>.log (git-ignored); -deadlock is needed because
# a finished run is a legitimate terminal state.
# usage: ./run.sh [spec:cfg...]   (from anywhere; no args runs the whole matrix)
set -u
here=$(cd "$(dirname "$0")" && pwd)
cd "$here" || exit 2
J=${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}
[ -f "$J" ] || { echo "run: no tla2tools.jar at $J (set TLA2TOOLS)" >&2; exit 2; }
rm -rf states; mkdir -p states
fail=0
expect() { # $1=spec module  $2=cfg stem  $3=expected verdict regex
  local name="$1-$2" line rc
  java -XX:+UseParallelGC -cp "$J" tlc2.TLC -workers 1 -deadlock \
    -metadir "states/$name" -config "$2.cfg" "$1.tla" > "$name.log" 2>&1
  rc=$?
  line=$(grep -m1 -E '^Error: [A-Za-z].*|No error has been found' "$name.log" || true)
  if printf '%s' "$line" | grep -Eq -- "$3"; then
    printf 'ok   %-24s %s\n' "$name" "$line"
  else
    printf 'FAIL %-24s want /%s/ got: %s (rc=%s, log %s.log)\n' "$name" "$3" "${line:-no verdict}" "$rc" "$name"
    fail=$((fail+1))
  fi
}

# clean: the current order (lock first) and the pre-fix model under its 1s grace
expect SlotClaimLockFirst SlotClaimLockFirst-cap1 'No error has been found'
expect SlotClaimLockFirst SlotClaimLockFirst-cap2 'No error has been found'
expect SlotClaimTimed     SlotClaim-cap1            'No error has been found'
expect SlotClaimTimed     SlotClaim-cap2            'No error has been found'
expect SlotClaimTimed     SlotClaim-cap1-2actors    'No error has been found'
expect SlotClaimTimed     SlotClaim-cap2-2actors    'No error has been found'
# chart projection (2 actors, no pre-lowering slot)
expect SlotClaimChart     SlotClaimChart            'No error has been found'
# the pre-fix order without the grace: the finding the replay reproduces
expect SlotClaim           SlotClaim-cap1            'HoldersHaveSlot is violated'
expect SlotClaim           SlotClaim-cap2            'HoldersHaveSlot is violated'
# broken copies: each fails the rule its removed mechanism protects
expect SlotClaimNoFence    SlotClaim-cap1            'HoldersHaveSlot is violated'
expect SlotClaimNoFence    SlotClaim-cap2            'HoldersHaveSlot is violated'
expect SlotClaimNoLock     SlotClaim-cap1            'HoldersHaveSlot is violated'
expect SlotClaimNoLock     SlotClaim-cap2            'HoldersHaveSlot is violated'
expect SlotClaimNoLiveness SlotClaim-cap1            'HoldersHaveSlot is violated'
expect SlotClaimNoLiveness SlotClaim-cap2            'HoldersHaveSlot is violated'
expect SlotClaimNoRecount  SlotClaim-cap1            'HeldCap is violated'
# derived from the pre-fix base, so at cap2 TLC names the base's fence bug first;
# only-HeldCap-cap2 below names the rule the removed recount owns
expect SlotClaimNoRecount  SlotClaim-cap2            'HoldersHaveSlot is violated'
# single-rule configs: name the rule one break owns, and show strict LiveCap is
# false by design (the exploratory only-HeldCap runs count the comment, not a promise)
expect SlotClaimNoFence    only-NoDoubleHold-cap1    'NoDoubleHold is violated'
expect SlotClaimNoFence    only-NoDoubleHold-cap2    'NoDoubleHold is violated'
expect SlotClaimNoLock     only-NoDoubleHold-cap1    'NoDoubleHold is violated'
expect SlotClaimNoLock     only-NoDoubleHold-cap2    'NoDoubleHold is violated'
expect SlotClaimNoLiveness only-NoDoubleHold-cap1    'NoDoubleHold is violated'
expect SlotClaimNoLiveness only-NoDoubleHold-cap2    'NoDoubleHold is violated'
expect SlotClaimNoRecount  only-HeldCap-cap1         'HeldCap is violated'
expect SlotClaimNoRecount  only-HeldCap-cap2         'HeldCap is violated'
expect SlotClaim           only-HoldersHaveSlot-cap1 'HoldersHaveSlot is violated'
expect SlotClaim           only-HoldersHaveSlot-cap2 'HoldersHaveSlot is violated'

[ "$fail" -eq 0 ] || { echo "run: $fail cfg(s) did not match" >&2; exit 1; }
