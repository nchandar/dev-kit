#!/usr/bin/env bash
# Generate the StopGate configs, run TLC on each, and compare the verdict to the
# rule the config is there to check. Clean configs pass; every broken variant
# fails the rule it guards. Full output goes to <name>.log (git-ignored).
# usage: ./run.sh [names...]   (from anywhere; no args runs the whole matrix)
set -u
here=$(cd "$(dirname "$0")" && pwd); cd "$here" || exit 2
J=${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}
[ -f "$J" ] || { echo "run: no tla2tools.jar at $J (set TLA2TOOLS)" >&2; exit 2; }
R1=StopNeedsAccept R2=StaleAcceptIgnored R3=NoFalseBlock R4=FailOpenAfterBlocks R5=NoEndTurnWhileRunningOrUnaccepted
cfg() { # name W MAXRUNS GUARD ROWORDER RUNCHECK NEWERROW STARTROW NUDGE OPENAT GATEACCEPTS EARLY invariants
  printf 'SPECIFICATION Spec\nCONSTANTS\n  W = {%s}\n  MAXBLOCKS = 3\n  MAXRUNS = %s\n  GUARD_STATUS = %s\n  ROWORDER = "%s"\n  RUNCHECK = %s\n  NEWERROW = %s\n  STARTROW = %s\n  NUDGEIGNORED = %s\n  OPENAT = %s\n  GATE_ACCEPTS = %s\n  EARLY = "%s"\nINVARIANTS TypeOK %s\n' \
    "${@:2}" > "$1.cfg"; }
W3=w1,w2,w3; W2=w1,w2
ALL="$R1 $R2 $R3 $R4 $R5"
#    name          W    RUN GUARD ORDER       RUN   NEW   STRT  NUDGE OPEN GATE  EARLY INVS
cfg clean          $W3  2   TRUE  rowfirst    TRUE  TRUE  TRUE  TRUE  3    TRUE  end   "$ALL"
cfg clean-early    $W3  2   TRUE  rowfirst    TRUE  TRUE  TRUE  TRUE  3    TRUE  any   "$ALL"
cfg clean-noguard  $W3  2   FALSE rowfirst    TRUE  TRUE  TRUE  TRUE  3    TRUE  end   "$ALL"
cfg clean-nudge    $W3  2   TRUE  rowfirst    TRUE  TRUE  TRUE  FALSE 3    TRUE  end   "$ALL"
cfg broken-R1      $W3  2   TRUE  rowfirst    FALSE TRUE  TRUE  TRUE  3    TRUE  any   "$R1 $R5"
cfg broken-R2      $W3  2   TRUE  rowfirst    TRUE  FALSE TRUE  TRUE  3    TRUE  end   "$R2"
cfg broken-R3      $W3  2   TRUE  statusfirst  TRUE  TRUE  TRUE  TRUE  3    TRUE  end   "$R3"
cfg broken-R3b     $W3  2   TRUE  rowfirst    TRUE  TRUE  TRUE  TRUE  3    FALSE end   "$R3"
cfg broken-R4      $W3  2   TRUE  rowfirst    TRUE  TRUE  TRUE  TRUE  1    TRUE  end   "$R4"
cfg broken-R5      $W3  2   TRUE  rowfirst    TRUE  TRUE  FALSE TRUE  3    TRUE  end   "$R2"
cfg broken-R5b     $W3  2   TRUE  rowfirst    TRUE  TRUE  FALSE TRUE  3    TRUE  end   "$R5"
cfg chart2         $W2  1   TRUE  rowfirst    TRUE  TRUE  TRUE  TRUE  3    TRUE  end   "$ALL"
echo 'CHECK_DEADLOCK FALSE' >> chart2.cfg # a terminal path is not a broken rule in a chart cfg
fail=0
expect() { # $1=cfg stem  $2=expected verdict regex
  local line
  java -XX:+UseParallelGC -cp "$J" tlc2.TLC -workers 8 -deadlock -config "$1.cfg" StopGate.tla > "$1.log" 2>&1
  line=$(grep -m1 -E '^Error: [A-Za-z].*|No error has been found' "$1.log" || true)
  if printf '%s' "$line" | grep -Eq -- "$2"; then
    printf 'ok   %-16s %s\n' "$1" "$line"
  else
    printf 'FAIL %-16s want /%s/ got: %s (log %s.log)\n' "$1" "$2" "${line:-no verdict}" "$1"
    fail=$((fail+1))
  fi
}
if [ $# -gt 0 ]; then names=$*; else names="clean clean-early clean-noguard clean-nudge broken-R1 broken-R2 broken-R3 broken-R3b broken-R4 broken-R5 broken-R5b chart2"; fi
for n in $names; do
  case $n in
    clean|clean-noguard|clean-nudge|chart2) expect "$n" 'No error has been found';;
    # the assumption that an accept before the exit row is harmless: R3 falsifies it
    clean-early) expect "$n" "$R3 is violated";;
    broken-R1) expect "$n" "$R1 is violated";;
    broken-R2) expect "$n" "$R2 is violated";;
    broken-R3|broken-R3b) expect "$n" "$R3 is violated";;
    broken-R4) expect "$n" "$R4 is violated";;
    broken-R5) expect "$n" "$R2 is violated";;
    broken-R5b) expect "$n" "$R5 is violated";;
    *) echo "run: unknown cfg $n" >&2; fail=$((fail+1));;
  esac
done
[ "$fail" -eq 0 ] || { echo "run: $fail cfg(s) did not match" >&2; exit 1; }
