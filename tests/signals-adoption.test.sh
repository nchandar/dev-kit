#!/usr/bin/env bash
# Content checks for the signals-in-tests rule (what lint-budget cannot see). Usage: tests/signals-adoption.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); cd "$here" || exit 2
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }

d=library/deep/observe-and-test.md
ok "deep file exists, at most 45 lines"          "[ -f $d ] && [ \$(wc -l < $d) -le 45 ]"
ok "deep file has the worked example"            "grep -q 'event=job_dropped' $d && grep -q 'attempt=3' $d && grep -q 'run_id' $d"
ok "deep file covers debug, test and refactor"   "grep -qi 'debug' $d && grep -qi 'refactor' $d && grep -qi 'identical' $d"
ok "deep file bans call-count assertions"        "grep -qi 'never.*call count' $d"
ok "principles points at the deep file"          'grep -q "deep/observe-and-test" library/principles.md'
o=library/observability.md
ok "observability: stable event name"            "grep -qi 'stable event name' $o"
ok "observability: entry-point field"            "grep -qi 'entry-point' $o"
ok "observability: saturation and histograms"    "grep -qi 'saturation' $o && grep -qi 'histogram' $o"
ok "observability: alert threshold from SLO"     "grep -qi 'SLO' $o"
ok "observability: define working first"         "grep -qi 'working' $o"
ok "observability: assert the signal in a test"  "grep -qi 'in-memory' $o && grep -qi 'assert' $o"
ok "observability: test fails when signal gone"  "grep -qi 'removed' $o"
ok "verify names the asserting test"             'grep -qi "asserts it" library/verify.md'
ok "debug-method reads signals first"            'grep -qi "existing" library/debug-method.md && grep -qi "signals" library/debug-method.md'
for s in feature debug refactor review; do
  f=skills/dev-$s/SKILL.md
  ok "dev-$s checklist has a signal item"        "awk '/^## Checklist/{c=1;next} /^\*\*Hand off to/{c=0} c' $f | grep -q 'library/observability' && awk '/^## Checklist/{c=1;next} /^\*\*Hand off to/{c=0} c' $f | grep -qi 'signal'"
done
ok "lint-budget passes"                          'bin/lint-budget >/dev/null 2>&1'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
