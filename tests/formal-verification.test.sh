#!/usr/bin/env bash
# Content checks for the three formal-verification skills (what lint-budget cannot see). Usage: tests/formal-verification.test.sh
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
ok "verify-sync lists the four outcomes"             "for w in 'in sync' updated bug blocked; do grep -q -- \"- \$w:\" $c || exit 1; done"
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
ok "model-check: chart through tlachart with the full command" "grep -qF 'tlachart SPEC.tla --config SPEC.cfg --view VIEW.mjs --out DIR' $m"
ok "model-check: without tlachart, the chart is blocked and the user is asked" "grep -qF 'chart blocked and ask' $m && grep -qF 'do not install unasked' $m"
ok "model-check: optional pele SVG over the tlachart output" "grep -qi 'optional' $m && grep -qF 'pele' $m && grep -qF 'render(' $m && grep -qi 'svg' $m"
ok "model-check: chart at 2 actors, check at 3, 500 states" "grep -q 'chart at 2 actors' $m && grep -q 'check at 3 actors' $m && grep -q '500' $m"
ok "model-check: every rule fails on a broken variant" "grep -qi 'broken variant' $m"
ok "model-check: never weaken a rule"                "grep -qi 'never weaken' $m"
ok "model-check: a finding needs a replay on real code" "grep -qi replay $m && grep -qi 'real code' $m"
ok "model-check: timers, expiry and stalls named"    "grep -qi 'timer' $m && grep -qi 'expiry' $m && grep -qi 'stall' $m"
ok "model-check: Red Flag for a safe verdict without timing" "sed -n '/^## Red Flags/,\$p' $m | grep -qi 'expiry'"
ok "model-check: jar path inline, blocked when missing" "grep -qF 'TLA2TOOLS:-' $m && grep -qi 'blocked' $m"
old_env="STATE""CHART"; author="github/""ref"
ok "model-check: no clone env var and no author path" "! grep -q \"\$old_env\" $m && ! grep -q \"\$author\" $m"

# R3: the three explicit-only skills
entry=skills/dev-formal-verification-skill/SKILL.md
create=skills/dev-create-formal-verification-skill/SKILL.md
maint=skills/dev-maintain-formal-verification-skill/SKILL.md
ok "entry skill exists, at most 60 lines"            "[ -f $entry ] && [ \$(wc -l < $entry) -le 60 ]"
ok "create skill exists, at most 75 lines"           "[ -f $create ] && [ \$(wc -l < $create) -le 75 ]"
ok "maintain skill exists, at most 60 lines"         "[ -f $maint ] && [ \$(wc -l < $maint) -le 60 ]"
for pair in "$entry:dev-formal-verification-skill" "$create:dev-create-formal-verification-skill" "$maint:dev-maintain-formal-verification-skill"; do
  s=${pair%%:*}; n=${pair##*:}
  ok "$n is explicit-only and named $n"              "grep -q '^name: $n\$' $s && grep -q '^disable-model-invocation: true\$' $s"
  ok "$n description is one line starting Use when"  "grep -q '^description: Use when' $s && [ \$(grep -c '^description:' $s) -eq 1 ]"
  ok "$n has the five required sections"             "for h in 'When to Use' Checklist Rationalizations 'Red Flags' Verification; do grep -q \"^## \$h\" $s || exit 1; done"
  ok "$n opens the host todo list"                   "grep -q 'host todo list' $s"
  ok "$n mentions bin/ledger"                        "grep -q 'bin/ledger' $s"
  ok "$n names library/state for closeout"           "grep -q 'library/state' $s"
  ok "$n has no outside references"                  "! grep -Eq '\.\./|references/' $s"
done
ok "entry reads principles and the model-check deep file" "grep -q 'always library/principles' $entry && grep -q 'library/deep/model-check' $entry"
ok "entry triage sends no model to the create skill" "grep -qi 'no model' $entry && grep -q 'dev-create-formal-verification-skill' $entry"
ok "entry triage sends covered code drift to maintain" "grep -qi 'covered code' $entry && grep -q 'dev-maintain-formal-verification-skill' $entry"
ok "entry triage renders a chart only with TLC and tlachart" "grep -qi 'chart' $entry && grep -q 'TLC' $entry && grep -qi 'tlachart' $entry"
ok "entry hands off to both skills and dev-debug"   "l=\$(grep '^\*\*Hand off to:\*\*' $entry); printf '%s' \"\$l\" | grep -q dev-create-formal-verification-skill && printf '%s' \"\$l\" | grep -q dev-maintain-formal-verification-skill && printf '%s' \"\$l\" | grep -q dev-debug"
ok "create reads model-check and keeps the model in <task>/model" "grep -q 'library/deep/model-check' $create && grep -q '<task>/model' $create"
ok "create names timers, expiry and stalls in the bound and the reply" "grep -qi 'timer' $create && grep -qi 'expiry' $create && grep -qi 'stall' $create && grep -qi 'timing' $create"
ok "create hands off to maintain and dev-debug"      "l=\$(grep '^\*\*Hand off to:\*\*' $create); printf '%s' \"\$l\" | grep -q dev-maintain-formal-verification-skill && printf '%s' \"\$l\" | grep -q dev-debug"
ok "maintain reads verify-sync and the diff command" "grep -q 'library/deep/verify-sync' $maint && grep -q 'git diff <sync>..HEAD' $maint"
ok "maintain lists the four outcomes"                "for w in 'in sync' updated bug blocked; do grep -q -- \"- \$w:\" $maint || exit 1; done"
ok "maintain updates from the code and break-tests before advancing" "grep -qi 'update from the code' $maint && grep -qi 'break' $maint && grep -qi 'advance' $maint"
ok "maintain hands off to dev-debug on a real bug"   "l=\$(grep '^\*\*Hand off to:\*\*' $maint); printf '%s' \"\$l\" | grep -q dev-debug && printf '%s' \"\$l\" | grep -q dev-create-formal-verification-skill"
ok "the three descriptions differ"                   "[ \$(grep -h '^description:' $entry $create $maint | sort -u | wc -l) -eq 3 ]"

# R4: wiring, no new route, install links, the old name is gone
ok "README lists all three skills"                   "grep -q dev-formal-verification-skill README.md && grep -q dev-create-formal-verification-skill README.md && grep -q dev-maintain-formal-verification-skill README.md"
ok "README marks each as a support skill, not a route" "miss=; for s in dev-formal-verification-skill dev-create-formal-verification-skill dev-maintain-formal-verification-skill; do grep \"\$s\" README.md | grep -qi 'support' || miss=\"\$miss \$s\"; done; [ -z \"\$miss\" ]"
ok "CONTRIBUTING mentions the create skill"          "grep -q 'dev-create-formal-verification-skill' CONTRIBUTING.md"
ok "ARCHITECTURE mentions the entry skill"           "grep -q 'dev-formal-verification-skill' ARCHITECTURE.md"
ok "AGENTS.md and CLAUDE.md mention the entry skill" "grep -q 'dev-formal-verification-skill' AGENTS.md && grep -q 'dev-formal-verification-skill' CLAUDE.md"
ok "dev-feature Reads points at the entry skill"     "grep -q 'dev-formal-verification-skill' skills/dev-feature/SKILL.md"
ok "no new route: dev-mode stays unaware"            "! grep -q 'formal-verification' skills/dev-mode/SKILL.md"
ok "principles points at model-check and verify-sync" "grep -q 'deep/model-check' library/principles.md && grep -q 'deep/verify-sync' library/principles.md"
old="dev-model-""check"
ok "the old skill folder is gone"                    "[ ! -e skills/$old ]"
ok "the old name is gone outside .devkit"            "! grep -rq \"\$old\" --exclude-dir=.devkit --exclude-dir=.git --exclude-dir=wt ."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
HOME="$t" ./install.sh >/dev/null 2>&1
ok "install.sh links all three skills for every CLI" 'miss=; for s in dev-formal-verification-skill dev-create-formal-verification-skill dev-maintain-formal-verification-skill; do for r in .claude/skills .codex/skills .agents/skills; do [ -f "$t/$r/$s/SKILL.md" ] || miss="$miss $s/$r"; done; done; [ -z "$miss" ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
