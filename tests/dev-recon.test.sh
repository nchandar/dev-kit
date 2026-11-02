#!/usr/bin/env bash
# Content checks for the recon/options/grill-loop port (dev-feature, dev-debug)
# and the dev-spawn nesting fix. Usage: tests/dev-recon.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
feat="$here/skills/dev-feature/SKILL.md"
dbg="$here/skills/dev-debug/SKILL.md"
spn="$here/skills/dev-spawn/SKILL.md"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }

ok "feature step 1 is Recon, options, clarify" 'grep -qi "recon.*options.*clarify\|1\. Recon" "$feat"'
ok "feature recon reads the research report first" 'grep -qi "research report" "$feat"'
ok "feature recon announces a tier" 'grep -q "T0" "$feat" && grep -q "T1" "$feat" && grep -q "T2" "$feat"'
ok "feature recon lists options with a recommendation" 'grep -qi "recommendation" "$feat"'
ok "feature recon loops back on unknowns, max 3 rounds" 'grep -qi "loop back to recon" "$feat" && grep -q "3 rounds" "$feat"'
ok "debug has a Recon step" 'grep -qi "recon" "$dbg"'
ok "debug recon announces a tier" 'grep -q "T0" "$dbg" && grep -q "T1" "$dbg" && grep -q "T2" "$dbg"'
ok "debug recon lists hypotheses/options with a recommendation" 'grep -qi "recommendation" "$dbg"'
ok "debug recon loops back on unknowns, max 3 rounds" 'grep -qi "loop back to recon" "$dbg" && grep -q "3 rounds" "$dbg"'
ok "debug keeps repro, doubt and regression-test steps" 'grep -qi "repro" "$dbg" && grep -qi "doubt" "$dbg" && grep -qi "regression test" "$dbg"'
ok "debug fix step lists options and asks the user's pick" 'grep -qi "user.s pick" "$dbg"'
ok "spawn drops the stale no-nesting claim" '! grep -q "Depth is 1" "$spn" && ! grep -q "refuses inside a worker" "$spn"'
ok "spawn says workers spawn up to DEVKIT_MAX_DEPTH" 'grep -q "DEVKIT_MAX_DEPTH" "$spn"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
