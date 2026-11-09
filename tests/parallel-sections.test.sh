#!/usr/bin/env bash
# A parallel suite must fail when one of its sections dies before reporting a count.
# Usage: tests/parallel-sections.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t" "$here"/tests/_crash-*.test.sh*' EXIT # an interrupt must not leave a stray suite for run-all's glob

# copy the suite beside the real ones (it locates bin/ from its own path) with one section replaced by a crash
crash() { # suite section
  cp "$here/tests/$1.test.sh" "$here/tests/_crash-$1.test.sh"
  sed -i.bak "s/^for s in /$2() { exit 2; }\nfor s in /" "$here/tests/_crash-$1.test.sh"; rm -f "$here/tests/_crash-$1.test.sh.bak"
  bash "$here/tests/_crash-$1.test.sh" > "$t/$1.out" 2>&1; echo $? > "$t/$1.rc"
  rm -f "$here/tests/_crash-$1.test.sh"
}
crash verify-scan sec_mutation & crash lint-budget sec_recipes & wait

ok "verify-scan: a crashed section fails the suite" '[ "$(cat $t/verify-scan.rc)" -ne 0 ]'
ok "verify-scan: the crash is named in the output" 'grep -q "FAIL section mutation crashed" $t/verify-scan.out'
ok "lint-budget: a crashed section fails the suite" '[ "$(cat $t/lint-budget.rc)" -ne 0 ]'
ok "lint-budget: the crash is named in the output" 'grep -q "FAIL section recipes crashed" $t/lint-budget.out'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
