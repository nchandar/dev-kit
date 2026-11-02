#!/usr/bin/env bash
# Content checks for the simplified recon port (dev-feature, dev-debug run
# dev-research with an external standard/cutting-edge pass, no tiers).
# Usage: tests/dev-recon.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
feat="$here/skills/dev-feature/SKILL.md"
dbg="$here/skills/dev-debug/SKILL.md"
spn="$here/skills/dev-spawn/SKILL.md"
rsch="$here/skills/dev-research/SKILL.md"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }

ok "feature step 1 is Recon, options, clarify" 'grep -q "^- \[ \] 1\..*Recon.*options.*clarify" "$feat"'
ok "feature recon reads the research report first" 'grep -q "^- \[ \] 1\..*research report" "$feat" || grep -q "research report" "$feat"'
ok "feature recon runs dev-research from step 1" 'grep -q "^- \[ \] 1\..*dev-research" "$feat"'
ok "feature recon names no tiers" '! grep -q "T0" "$feat" && ! grep -q "T1" "$feat" && ! grep -q "T2" "$feat" && ! grep -qi "tier" "$feat"'
ok "feature recon lists options with a recommendation" 'grep -q "^- \[ \] 1\..*recommendation" "$feat"'
ok "feature recon skips research clarify, folds checkpoint into options" 'grep -q "^- \[ \] 1\..*clarify skipped" "$feat" && grep -q "^- \[ \] 1\..*checkpoint.*options" "$feat"'
ok "feature recon loops back on unknowns, max 3 rounds" 'grep -q "^- \[ \] 1\..*loop back to recon" "$feat" && grep -q "^- \[ \] 1\..*3 rounds" "$feat"'
ok "debug has a Recon step running dev-research" 'grep -q "^- \[ \] 1\..*Recon" "$dbg" && grep -q "^- \[ \] 1\..*dev-research" "$dbg"'
ok "debug recon runs dev-research" 'grep -q "^- \[ \] 1\..*dev-research" "$dbg"'
ok "debug recon names no tiers" '! grep -q "T0" "$dbg" && ! grep -q "T1" "$dbg" && ! grep -q "T2" "$dbg" && ! grep -qi "tier" "$dbg"'
ok "debug recon lists hypotheses/options with a recommendation" 'grep -q "^- \[ \] 1\..*hypotheses" "$dbg" && grep -q "^- \[ \] 1\..*recommendation" "$dbg"'
ok "debug recon skips research clarify, folds checkpoint into options" 'grep -q "^- \[ \] 1\..*clarify skipped" "$dbg" && grep -q "^- \[ \] 1\..*checkpoint.*options" "$dbg"'
ok "debug recon loops back on unknowns, max 3 rounds" 'grep -q "^- \[ \] 1\..*loop back to recon" "$dbg" && grep -q "^- \[ \] 1\..*3 rounds" "$dbg"'
ok "debug keeps repro, doubt and regression-test steps" 'grep -qi "repro" "$dbg" && grep -qi "doubt" "$dbg" && grep -qi "regression test" "$dbg"'
ok "debug fix step lists options and asks the user's pick" 'grep -qi "user.s pick" "$dbg"'
ok "research names the industry-standard pass" 'grep -q "^- \[ \] 2\..*industry-standard" "$rsch"'
ok "research names the cutting-edge pass" 'grep -q "^- \[ \] 2\..*cutting-edge" "$rsch"'
ok "research grounds the external pass in primary sources and docs-grounding" 'grep -q "^- \[ \] 2\..*primary sources" "$rsch" && grep -q "library/docs-grounding" "$rsch"'
ok "research labels options standard, cutting-edge or local" 'grep -q "^- \[ \] 8\..*standard.*cutting-edge.*local" "$rsch"'
ok "spawn drops the stale no-nesting claim" '! grep -q "Depth is 1" "$spn" && ! grep -q "refuses inside a worker" "$spn"'
ok "spawn says workers spawn up to DEVKIT_MAX_DEPTH" 'grep -q "DEVKIT_MAX_DEPTH" "$spn"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
