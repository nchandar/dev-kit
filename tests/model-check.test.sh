#!/usr/bin/env bash
# Content checks for the model-check prototype (what lint-budget cannot see). Usage: tests/model-check.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); cd "$here" || exit 2
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }

# R1: coverage record and sync commit
c=library/deep/verify-sync.md
ok "verify-sync exists, at most 45 lines"            "[ -f $c ] && [ \$(wc -l < $c) -le 45 ]"
ok "verify-sync has When to Load and Red Flags"      "grep -q '^## When to Load' $c && grep -q '^## Red Flags' $c"
ok "verify-sync records covered files and functions" "grep -qi 'files and functions' $c"
ok "verify-sync defines the sync commit"             "grep -qi 'sync commit' $c"
ok "verify-sync gives the diff command"              "grep -q 'git diff <sync>..HEAD' $c"
ok "verify-sync lists the four outcomes"             "for w in 'in sync' updated bug blocked; do grep -qi \"\$w\" $c || exit 1; done"
ok "verify-sync advances the sync only after confirmation" "grep -qi 'advance' $c && grep -qi 'confirm' $c"
ok "verify-sync mentions bin/ledger"                 "grep -q 'bin/ledger' $c"
ok "verify-sync: no outside references"              "! grep -Eq '\.\./|references/' $c"
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
