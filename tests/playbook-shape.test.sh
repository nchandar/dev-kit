#!/usr/bin/env bash
# Shape checks for playbooks (route skills) and the thin dev-mode router. Usage: tests/playbook-shape.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); cd "$here" || exit 2
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
body() { awk 'NR==1&&$0!="---"{print;next} f{print} NR>1&&$0=="---"{f=1}' "$1"; }
desc() { grep -m1 '^description:' "$1" | sed 's/^description: *//'; }

routes="feature debug refactor research review spawn eval learn"
for r in $routes; do
  f=skills/dev-$r/SKILL.md
  reads=$(grep '^\*\*Reads:\*\*' $f); miss=""
  for p in $(awk '/^## Checklist/{c=1;next} /^\*\*Hand off to/{c=0} c' $f | grep -oE 'library/[a-z0-9/-]*[a-z0-9]' | sort -u); do
    [ -f "$p.md" ] || continue; printf '%s' "$reads" | grep -qF "$p" || miss="$miss $p"
  done
  ok "dev-$r Reads covers every library file its steps use" '[ -z "$miss" ] || { echo "     missing:$miss"; false; }'
  for h in 'You own' 'Reads' 'Hand off to' 'Reply'; do
    ok "dev-$r has **$h:**"                     "grep -q '^\*\*$h:\*\*' $f"
  done
  ok "dev-$r description starts with Use when"  "desc $f | grep -q '^Use when'"
  ok "dev-$r Reads comes before the Checklist"  "[ \$(grep -n '^\*\*Reads:\*\*' $f | head -1 | cut -d: -f1) -lt \$(grep -n '^## Checklist' $f | cut -d: -f1) ]"
  ok "dev-$r Hand off to comes after the Checklist" "[ \$(grep -n '^\*\*Hand off to:\*\*' $f | head -1 | cut -d: -f1) -gt \$(grep -n '^## Checklist' $f | cut -d: -f1) ]"
done
ok "feature hands off to dev-review"            'grep -q "^\*\*Hand off to:\*\*.*dev-review" skills/dev-feature/SKILL.md'
ok "refactor hands off to dev-review"           'grep -q "^\*\*Hand off to:\*\*.*dev-review" skills/dev-refactor/SKILL.md'
ok "debug hands off to dev-review and dev-research" 'grep "^\*\*Hand off to:\*\*" skills/dev-debug/SKILL.md | grep -q dev-review && grep "^\*\*Hand off to:\*\*" skills/dev-debug/SKILL.md | grep -q dev-research'
ok "research hands off to dev-feature"          'grep -q "^\*\*Hand off to:\*\*.*dev-feature" skills/dev-research/SKILL.md'

m=skills/dev-mode/SKILL.md
ok "dev-mode holds no chain rules"              '! body $m | grep -q "research -> dev-feature" && ! body $m | grep -q "debug -> dev-review"'
ok "dev-mode reads the playbook by path"        'body $m | grep -q "skills/dev-<route>/SKILL.md"'
ok "dev-mode follows the playbook Hand off to and Reply" 'body $m | grep -q "Hand off to" && body $m | grep -q "Reply"'
ok "dev-mode closes via ketchup and writing"    'body $m | grep -q "deep/ketchup" && body $m | grep -q "deep/writing"'
ok "dev-mode does not say invoke its skill"     '! body $m | grep -qi "invoke its skill"'

for r in $routes; do
  ok "dev-$r is explicit-only"                  "grep -q '^disable-model-invocation: true' skills/dev-$r/SKILL.md"
done
# OpenCode hides flagged skills from its skill tool and loads dev-mode through that tool (opencode routing 15/31 when flagged)
ok "dev-mode stays model-visible"               '! grep -q "^disable-model-invocation" skills/dev-mode/SKILL.md'
ok "no playbook tells the model to run a skill by tool" '! grep -n -E "\brun dev-(research|review|spawn|feature|debug|eval|learn|refactor)\b" skills/dev-*/SKILL.md'
ok "lint-budget passes"                         'bin/lint-budget >/dev/null 2>&1'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
