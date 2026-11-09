#!/usr/bin/env bash
# A parallel suite must fail when one of its sections dies before reporting a count.
# Usage: tests/parallel-sections.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# copy the suite into the suite's own temp dir (never the repo tree) with here= pinned to the
# real repo and one section replaced by a crash
crash() { # suite section
  cp "$here/tests/$1.test.sh" "$t/_crash-$1.test.sh"
  sed -i.bak "s|here=\$(cd \"\$(dirname \"\$0\")/..\" && pwd)|here='$here'|" "$t/_crash-$1.test.sh"
  sed -i.bak "s/^for s in /$2() { exit 2; }\nfor s in /" "$t/_crash-$1.test.sh"; rm -f "$t/_crash-$1.test.sh.bak"
  bash "$t/_crash-$1.test.sh" > "$t/$1.out" 2>&1; echo $? > "$t/$1.rc"
  rm -f "$t/_crash-$1.test.sh"
}

# a repo scan running beside the crash helpers must not see their copies: probe, bounded, while they run
probe() {
  n=0; pfails=0; echo 0 > "$t/probe.fails"
  while [ "$n" -lt 40 ]; do # at least one probe runs, then it stops once the crash helpers are done
    n=$((n+1))
    if ! "$here/bin/lint-budget" >/dev/null 2>&1; then pfails=$((pfails+1)); echo "$pfails" > "$t/probe.fails"; fi
    [ ! -e "$t/stop" ] || break
  done
  echo "$n" > "$t/probe.n"
}
probe & probe_pid=$!
crash verify-scan sec_mutation & c1=$!
crash lint-budget sec_recipes & c2=$!
wait "$c1" "$c2"
touch "$t/stop"; wait "$probe_pid"

ok "the concurrent probe ran at least once" '[ "$(cat $t/probe.n)" -gt 0 ]'
ok "a concurrent bin/lint-budget probe never fails" '[ "$(cat $t/probe.fails)" -eq 0 ]'
ok "no crash copy is left in tests/" '[ -z "$(ls "$here"/tests/_crash-* 2>/dev/null)" ]'
ok "verify-scan: the pinned copy still runs its earlier sections" 'grep -q "^ok   bad: removed assertion is weakened" $t/verify-scan.out'
ok "lint-budget: the pinned copy still runs its earlier sections" 'grep -q "^ok   good tree passes" $t/lint-budget.out'
ok "verify-scan: a crashed section fails the suite" '[ "$(cat $t/verify-scan.rc)" -ne 0 ]'
ok "verify-scan: the crash is named in the output" 'grep -q "FAIL section mutation crashed" $t/verify-scan.out'
ok "lint-budget: a crashed section fails the suite" '[ "$(cat $t/lint-budget.rc)" -ne 0 ]'
ok "lint-budget: the crash is named in the output" 'grep -q "FAIL section recipes crashed" $t/lint-budget.out'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
