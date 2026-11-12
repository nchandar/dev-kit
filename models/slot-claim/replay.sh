#!/usr/bin/env bash
# Replay the model's shortest counterexample on the extracted functions.
# The only timing injection is claimant.sh's mkdir wrapper (a stall after a
# successful mkdir). All claim/lock/liveness code is byte-identical to
# bin/spawn 301-351 as extracted by extract-slot-lib.sh.
#   replay.sh plain     three claimants, no stall
#   replay.sh stalled   A stalls 2.5s after mkdir; C starts at 1.5s and stalls 2.5s
set -u
here=$(cd "$(dirname "$0")" && pwd)
RUN_DIR=${RUN_DIR:-$here/replay-run}
export RUN_DIR CAP=${CAP:-2}
rm -rf "$RUN_DIR"; mkdir -p "$RUN_DIR/run" "$RUN_DIR/home"
export HOME="$RUN_DIR/home" # never the real HOME: nothing here may touch the user install

run=${1:-plain}
case $run in
  plain)
    bash "$here/claimant.sh" A & pa=$!
    bash "$here/claimant.sh" B & pb=$!
    bash "$here/claimant.sh" C & pc=$!
    ;;
  stalled)
    # A's mkdir at 0; B reclaims the empty dir at ~1.2; C recreates it at 1.5;
    # A writes its pid at 2.5; C takes the lock at 4.0 and overwrites it.
    MKDIR_STALL=2.5 bash "$here/claimant.sh" A & pa=$!
    sleep 0.2
    bash "$here/claimant.sh" B & pb=$!
    sleep 1.3
    MKDIR_STALL=2.5 bash "$here/claimant.sh" C & pc=$!
    ;;
  *) echo "usage: replay.sh plain|stalled" >&2; exit 2;;
esac
sleep 5
touch "$RUN_DIR/stop"
wait $pa $pb $pc 2>/dev/null

echo "run=$run cap=$CAP holds:"
sort "$RUN_DIR/holds" 2>/dev/null || true
echo "missed:"; sort "$RUN_DIR/missed" 2>/dev/null || true
dup=$(awk '{print $3}' "$RUN_DIR/holds" 2>/dev/null | grep -v none | sort | uniq -d | tr '\n' ' ')
if [ -n "$dup" ]; then echo "DOUBLE-HOLD slot(s): $dup"; exit 1; fi
echo "no double hold"
