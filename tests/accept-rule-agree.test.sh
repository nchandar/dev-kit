#!/usr/bin/env bash
# The accept rule is written twice: bin/reconcile gates on it (--gate), bin/spawn --prune deletes a
# worktree on it. This suite extracts both real awk copies from the scripts, feeds them the same
# seeded random ledgers, and asserts they reach the same accepted/unaccepted verdict for every id.
# Usage: tests/accept-rule-agree.test.sh
# Env: ACCEPT_RULE_CASES (default 300), ACCEPT_RULE_SEED (default 20261111),
#      ACCEPT_RULE_SRC (default this repo; point at a copy to prove a mutated rule is caught).
set -u
# this suite must pass when run from inside a worker too
unset DEVKIT_DEPTH CLAUDE_CODE_SESSION_ID

here=$(cd "$(dirname "$0")/.." && pwd)
src=${ACCEPT_RULE_SRC:-$here}
cases=${ACCEPT_RULE_CASES:-300}
seed=${ACCEPT_RULE_SEED:-20261111}
case $cases in ''|*[!0-9]*|0) echo "accept-rule-agree: ACCEPT_RULE_CASES must be a positive integer, got '$cases'" >&2; exit 2;; esac
case $seed in ''|*[!0-9]*) echo "accept-rule-agree: ACCEPT_RULE_SEED must be a whole number, got '$seed'" >&2; exit 2;; esac
cases=$((10#$cases)); seed=$((10#$seed))
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT

# the rule is the single-quoted argument after `-v id=`; refuse a line that moved or lost its verdict
rule_of() { # $1 script -> the awk program on stdout
  local prog
  prog=$(awk -F"'" '
    index($0, "$2==\"spawn\"") && index($0, "$2==\"accept\"") { print $4; found = 1; exit }
    END { if (!found) exit 3 }' "$1") || return 1
  [ -n "$prog" ] || return 1
  case $prog in *'ac>ex'*) ;; *) return 1;; esac
  printf '%s\n' "$prog"; }

# read only: this suite never runs either tool
rec_src=$src/bin/reconcile
spawn_src=$src/bin/spawn
rule_of "$rec_src" > "$t/rec.awk" || { echo "FAIL the accept rule line moved or changed in $rec_src; update tests/accept-rule-agree.test.sh" >&2; fail=$((fail+1)); }
rule_of "$spawn_src" > "$t/spawn.awk" || { echo "FAIL the accept rule line moved or changed in $spawn_src; update tests/accept-rule-agree.test.sh" >&2; fail=$((fail+1)); }
if [ "$fail" -ne 0 ]; then echo "$pass passed, $fail failed"; exit 1; fi

# awk exit status is the rule's verdict: 0 accepted, 1 unaccepted; anything else is an error
vig() { # $1 program $2 ledger $3 id -> the exit status as text
  local v
  awk -F'\t' -v id="$3" -f "$1" "$2"
  v=$?
  printf '%s' "$v"; }
agree() { # $1 program a $2 program b $3 ledger $4 id -> "0"/"1", or "X:<a>:<b>" on a disagree
  local a b
  a=$(vig "$1" "$3" "$4"); b=$(vig "$2" "$3" "$4")
  if [ "$a" = "$b" ]; then printf '%s' "$a"; else printf 'X:%s:%s' "$a" "$b"; fi; }

ledger_head() { printf 'time\tphase\tdecision\treason\tevidence\tresult\n' > "$1"; }
ledger_row() { printf '2026-01-01T00:00:00Z\t%s\t%s\tnote\t-\tok\n' "$2" "$3" >> "$1"; }

# --- pinned semantics: the row kinds the rule must treat as (not) a new exit
ledger_head "$t/nudge.tsv"
ledger_row "$t/nudge.tsv" spawn "w9 running"
ledger_row "$t/nudge.tsv" accept "w9 accepted"
ledger_row "$t/nudge.tsv" spawn "w9 nudge"
ok "a nudge row after an accept does not undo it" '[ "$(agree "$t/rec.awk" "$t/spawn.awk" "$t/nudge.tsv" w9)" = 0 ]'

ledger_head "$t/scout.tsv"
ledger_row "$t/scout.tsv" spawn "w9 running"
ledger_row "$t/scout.tsv" accept "w9 accepted"
ledger_row "$t/scout.tsv" spawn "w9 scout changed files"
ok "a scout row after an accept does not undo it" '[ "$(agree "$t/rec.awk" "$t/spawn.awk" "$t/scout.tsv" w9)" = 0 ]'

for verb in route-warning owns-overlap isolation-violation; do
  f="$t/$verb.tsv"
  ledger_head "$f"
  ledger_row "$f" spawn "w9 running"
  ledger_row "$f" accept "w9 accepted"
  ledger_row "$f" spawn "w9 $verb"
  ok "a $verb row after an accept makes it unaccepted again" '[ "$(agree "$t/rec.awk" "$t/spawn.awk" "$t/'"$verb"'.tsv" w9)" = 1 ]'
done

ledger_head "$t/respawn.tsv"
ledger_row "$t/respawn.tsv" spawn "w9 running"
ledger_row "$t/respawn.tsv" accept "w9 accepted"
ledger_row "$t/respawn.tsv" spawn "w9 running"
ok "a later spawn row after an accept makes it unaccepted again" '[ "$(agree "$t/rec.awk" "$t/spawn.awk" "$t/respawn.tsv" w9)" = 1 ]'

ledger_head "$t/reject.tsv"
ledger_row "$t/reject.tsv" spawn "w9 running"
ledger_row "$t/reject.tsv" spawn "w9 done"
ledger_row "$t/reject.tsv" accept "w9 rejected"
ok "a reject row is a decision, not an outstanding worker" '[ "$(agree "$t/rec.awk" "$t/spawn.awk" "$t/reject.tsv" w9)" = 0 ]'

ledger_head "$t/otherid.tsv"
ledger_row "$t/otherid.tsv" spawn "w1 running"
ledger_row "$t/otherid.tsv" accept "w2 accepted"
ok "an accept for one id does not clear another" '[ "$(agree "$t/rec.awk" "$t/spawn.awk" "$t/otherid.tsv" w1)" = 1 ]'

# --- seeded random ledgers over start, exit, nudge, scout, accept, warning and violation rows
: > "$t/manifest"
RANDOM=$seed
c=1
while [ "$c" -le "$cases" ]; do
  f=$t/case-$c.tsv
  ledger_head "$f"
  nid=$((RANDOM % 3 + 1))
  n=$((RANDOM % 16))
  i=0
  while [ "$i" -lt "$n" ]; do
    id=w$((RANDOM % nid + 1))
    if [ $((RANDOM % 10)) -lt 2 ]; then
      case $((RANDOM % 2)) in
        0) ledger_row "$f" accept "$id accepted";;
        *) ledger_row "$f" accept "$id rejected";;
      esac
    else
      case $((RANDOM % 8)) in
        0) ledger_row "$f" spawn "$id running";;
        1) ledger_row "$f" spawn "$id done";;
        2) ledger_row "$f" spawn "$id failed";;
        3) ledger_row "$f" spawn "$id timeout";;
        4) ledger_row "$f" spawn "$id killed";;
        5) ledger_row "$f" spawn "$id nudge";;
        6) ledger_row "$f" spawn "$id scout changed files";;
        *) case $((RANDOM % 3)) in
             0) ledger_row "$f" spawn "$id route-warning";;
             1) ledger_row "$f" spawn "$id owns-overlap";;
             *) ledger_row "$f" spawn "$id isolation-violation";;
           esac;;
      esac
    fi
    i=$((i+1))
  done
  printf '%s %s\n' "$f" "$nid" >> "$t/manifest"
  c=$((c+1))
done
digest=$(cat "$t"/case-*.tsv | cksum)
echo "seed=$seed cases=$cases digest=$digest"

checks=0; mism=0
while IFS=' ' read -r f nid; do
  j=1
  while [ "$j" -le "$nid" ]; do
    id=w$j
    v=$(agree "$t/rec.awk" "$t/spawn.awk" "$f" "$id")
    checks=$((checks+1))
    case $v in
      0|1) ;;
      *) mism=$((mism+1))
         echo "FAIL reconcile --gate and spawn --prune disagree on $id (reconcile:spawn=$v)"
         echo "----- replay ledger: $f -----"
         cat "$f"
         echo "-------------------------------" ;;
    esac
    j=$((j+1))
  done
done < "$t/manifest"
ok "both copies agree on $checks (ledger, worker) pairs from $cases ledgers (seed $seed)" '[ "$mism" -eq 0 ]'

# --- the harness can fail: an edited copy of the rule that counts nudge as an exit row must disagree
sed 's/w\[2\]!="nudge" && //' "$t/rec.awk" > "$t/mutant.awk"
if cmp -s "$t/rec.awk" "$t/mutant.awk"; then
  echo "FAIL the mutation self-check no longer matches the rule; update it" >&2
  fail=$((fail+1))
fi
ledger_head "$t/mutant.tsv"
ledger_row "$t/mutant.tsv" spawn "w9 running"
ledger_row "$t/mutant.tsv" accept "w9 accepted"
ledger_row "$t/mutant.tsv" spawn "w9 nudge"
ok "an edited copy of the rule is caught disagreeing (reconcile accepts, mutant does not)" '[ "$(agree "$t/rec.awk" "$t/mutant.awk" "$t/mutant.tsv" w9)" = X:0:1 ]'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
