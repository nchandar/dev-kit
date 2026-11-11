#!/usr/bin/env bash
# Wiring checks for the deep files and routes (what lint-budget cannot see). Usage: tests/deep-wiring.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); cd "$here" || exit 2
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
refd() { grep -rlq "library/deep/$1" skills library/*.md; }

for d in sketch writing ketchup blast-radius app-verification-recipe typescript experience-first overnight; do
  ok "deep $d exists and is not empty"  "[ -s library/deep/$d.md ]"
  ok "deep $d is referenced from a skill or library file"  "refd $d"
done
ok "dev-refactor skill exists"                    '[ -f skills/dev-refactor/SKILL.md ]'
ok "dev-mode names sharpen and grill carries it"   'grep -q sharpen skills/dev-mode/SKILL.md && grep -qi sharpen library/grill.md'
ok "dev-eval skill exists"                        '[ -f skills/dev-eval/SKILL.md ]'
ok "dev-mode routes evals to dev-eval"            'grep -q "dev-eval" skills/dev-mode/SKILL.md'
ok "route eval has a dev-eval case"               'grep -q "^dev-eval" evals/route.cases'
ok "dev-mode routes refactors to dev-refactor"    'grep -q "dev-refactor" skills/dev-mode/SKILL.md'
ok "dev-feature points to dev-refactor"  'grep -q "dev-refactor" skills/dev-feature/SKILL.md'
ok "route eval has a dev-refactor case"           'grep -q "^dev-refactor" evals/route.cases'
for s in skills/dev-*/SKILL.md; do
  case $s in skills/dev-mode/*) continue;; esac  # dev-mode only classifies; each playbook opens the list
  ok "$s opens the host todo list"                "grep -q 'host todo list' $s"
done
ok "AGENTS.md states the todo rule"               'grep -q "host todo list" AGENTS.md'
ok "dev-research and dev-feature use explain-html" 'grep -q "explain-html" skills/dev-research/SKILL.md && grep -q "explain-html" skills/dev-feature/SKILL.md'
ok "dev-debug uses explain-html for cross-component bugs" 'grep -q "explain-html" skills/dev-debug/SKILL.md'
ok "dev-feature offers the sketch step"           'grep -q "deep/sketch" skills/dev-feature/SKILL.md'
ok "dev-review has the blast-radius ladder and proven-by-a-run rule"  'grep -q "deep/blast-radius" skills/dev-review/SKILL.md && grep -qi "proven by a run" library/doubt.md'
ok "dev-mode closing follows ketchup and writing" 'grep -q "deep/ketchup" skills/dev-mode/SKILL.md && grep -q "deep/writing" skills/dev-mode/SKILL.md'
ok "overnight recipe is reachable from dev-spawn" 'grep -q "deep/overnight" skills/dev-spawn/SKILL.md'
ok "grill has the sharpen lines"                  'grep -qi "top professional" library/grill.md'
ok "encode-lessons has the rule table"            'grep -qi "rule table" library/deep/encode-lessons.md'
ok "test-strategy has the twin-case rule"         'grep -qi "twin" library/deep/test-strategy.md'
ok "decision-records has the internal-only rule"  'grep -qi "internal-only" library/deep/decision-records.md'
ok "docs say nine skills, not seven"             '! grep -qi "seven skills" ARCHITECTURE.md AGENTS.md README.md CONTRIBUTING.md && ! grep -qi "eight skills" ARCHITECTURE.md AGENTS.md README.md CONTRIBUTING.md'
ok "lint-budget passes"                           'bin/lint-budget >/dev/null 2>&1'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
