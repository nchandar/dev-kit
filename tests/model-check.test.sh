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

# R2: when a model beats a test, tool choice, commands, budgets
m=library/deep/model-check.md
ok "model-check exists, at most 45 lines"            "[ -f $m ] && [ \$(wc -l < $m) -le 45 ]"
ok "model-check has When to Load and Red Flags"      "grep -q '^## When to Load' $m && grep -q '^## Red Flags' $m"
ok "model-check: ordering, concurrency, small state" "for w in ordering concurrency 'small state'; do grep -qi \"\$w\" $m || exit 1; done"
ok "model-check: not for single actor, UI, plain logic" "for w in 'single actor' UI 'plain logic'; do grep -qi \"\$w\" $m || exit 1; done"
ok "model-check: TLC default, stateful tests, Quint, Apalache" "for w in TLC 'stateful property test' Quint Apalache; do grep -qi \"\$w\" $m || exit 1; done"
ok "model-check: plain TLC command"                  "grep -q 'tlc2.TLC' $m && grep -q -- '-workers 1' $m"
ok "model-check: statechart through bun and STATECHART" "grep -qF 'bun \"\$STATECHART/scripts/statechart.ts\"' $m"
ok "model-check: Mermaid from the TLC trace when statechart is absent" "grep -qi mermaid $m && grep -qi 'TLC trace' $m"
ok "model-check: chart at 2 workers, check at 3, 500 states" "grep -q 'chart at 2 workers' $m && grep -q 'check at 3 workers' $m && grep -q '500' $m"
ok "model-check: every rule fails on a broken variant" "grep -qi 'broken variant' $m"
ok "model-check: never weaken a rule"                "grep -qi 'never weaken' $m"
ok "model-check: a finding needs a replay on real code" "grep -qi replay $m && grep -qi 'real code' $m"

# R3: the explicit-only skill
s=skills/dev-model-check/SKILL.md
ok "skill exists, at most 150 lines"                 "[ -f $s ] && [ \$(wc -l < $s) -le 150 ]"
ok "skill is explicit-only and named dev-model-check" "grep -q '^name: dev-model-check$' $s && grep -q '^disable-model-invocation: true$' $s"
ok "skill description is one line starting Use when" "grep -q '^description: Use when' $s && [ \$(grep -c '^description:' $s) -eq 1 ]"
ok "skill has the five required sections"            "for h in 'When to Use' Checklist Rationalizations 'Red Flags' Verification; do grep -q \"^## \$h\" $s || exit 1; done"
ok "skill reads both deep files and library/state"   "grep -q 'library/deep/model-check' $s && grep -q 'library/deep/verify-sync' $s && grep -q 'library/state' $s"
ok "skill opens the host todo list"                  "grep -q 'host todo list' $s"
ok "skill mentions bin/ledger"                       "grep -q 'bin/ledger' $s"
ok "skill: no outside references"                    "! grep -Eq '\.\./|references/' $s"

# R4: wiring, no new route, install link
ok "README lists dev-model-check"                    "grep -q 'dev-model-check' README.md"
ok "CONTRIBUTING mentions dev-model-check"           "grep -q 'dev-model-check' CONTRIBUTING.md"
ok "ARCHITECTURE mentions dev-model-check"           "grep -q 'dev-model-check' ARCHITECTURE.md"
ok "AGENTS.md and CLAUDE.md mention dev-model-check" "grep -q 'dev-model-check' AGENTS.md && grep -q 'dev-model-check' CLAUDE.md"
ok "dev-feature Reads points at model-check"         "grep -q 'dev-model-check' skills/dev-feature/SKILL.md"
ok "no new route: dev-mode stays unaware"            "! grep -q 'model-check' skills/dev-mode/SKILL.md"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
HOME="$t" ./install.sh >/dev/null 2>&1
ok "install.sh links dev-model-check for every CLI"  '[ -f "$t/.claude/skills/dev-model-check/SKILL.md" ] && [ -f "$t/.codex/skills/dev-model-check/SKILL.md" ] && [ -f "$t/.agents/skills/dev-model-check/SKILL.md" ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
