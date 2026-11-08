#!/usr/bin/env bash
# library/git-ship.md must carry the CI-green merge rule. Usage: tests/git-ship.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); cd "$here" || exit 2
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
f=library/git-ship.md
sec() { awk -v s="## $1" '$0==s{c=1;next} /^## /{c=0} c' $f; }

ok "step names the never-merge-unless-every-check-passed rule" 'grep -qi "never merge.*every CI check" $f'
ok "step verifies with gh pr checks"                          'grep -q "gh pr checks" $f'
ok "step treats no checks as do not merge"                    'grep -qi "no checks" $f'
ok "rule holds even when the user says merge it"              'grep -qi "merge it" $f'
ok "after a merge, read the CI run on main"                   'grep -qi "run on main" $f'
ok "Red Flags lists a failing, pending or missing check"      'sec "Red Flags" | grep -qi "merging with a failing, pending or missing check"'
ok "Verification requires every check passing before a merge" 'sec Verification | grep -q "gh pr checks"'
ok "lint-budget passes"                                       'bin/lint-budget >/dev/null 2>&1'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
