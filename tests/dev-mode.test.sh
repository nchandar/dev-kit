#!/usr/bin/env bash
# Content checks for skills/dev-mode (the rules lint-budget cannot see). Usage: tests/dev-mode.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); f="$here/skills/dev-mode/SKILL.md"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
body() { awk 'NR==1&&$0!="---"{print;next} f{print} NR>1&&$0=="---"{f=1}' "$f"; }

ok "skill file exists"                         '[ -f "$f" ]'
ok "hard rules in the first 12 body lines"     '[ "$(body | head -12 | grep -c -i -E "stay on|gates|step N/M")" -ge 3 ]'
ok "footer rule covers off-topic answers, exact lowercase"  '[ "$(body | head -12 | grep -c -i -E "off-topic.*exact lowercase footer")" -ge 1 ]'
ok "triage covers type and size"               'body | grep -qi "size" && body | grep -q "trivial"'
ok "triage decides size first"                  'body | grep -qi "size first" && body | grep -qi "means type none"'
ok "delegation is never trivial"               'body | grep -qi "delegation is never trivial"'
ok "announce line format"                      'body | grep -q "route: <skill>"'
ok "no-route exit skips the ledger"            'body | grep -q "route: none" && body | grep -qi "no ledger"'
ok "mixed order stated"                        'body | grep -q "research, debug, feature"'
ok "chains live in the playbooks: research->feature, debug->review"  'grep -q "^\*\*Hand off to:\*\*.*dev-feature" "$here/skills/dev-research/SKILL.md" && grep -q "^\*\*Hand off to:\*\*.*dev-review" "$here/skills/dev-debug/SKILL.md"'
ok "dev-mode follows the playbook hand-off"    'body | grep -q "Hand off to"'
ok "closing answer"                            'body | grep -qi "open risks"'
ok "precedence and worker exemption"           'body | grep -qi "outrank" && body | grep -q "DEVKIT_DEPTH"'
ok "never copies a route checklist"            'body | grep -qi "do not copy" && ! body | grep -qi "copy the checklist verbatim"'
ok "light: at most 330 words"                  '[ -f "$f" ] && [ "$(body | wc -w)" -le 330 ]'
ok "footer rule has one home, the skill: AGENTS.md has none"  '! grep -q "Once a dev-mode route has started" "$here/AGENTS.md"'
ok "eval has no rule-injection switch"                  '! grep -q "EVAL_RULE" "$here/evals/route.sh"'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
