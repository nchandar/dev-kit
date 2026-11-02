#!/usr/bin/env bash
# Keeps bin/defaults, bin/spawn and the docs in step. Usage: tests/defaults.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); defaults="$here/bin/defaults"; arch="$here/ARCHITECTURE.md"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
knobs="DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW_CLOSE_DELAY DEVKIT_VIEW"
val() { env -i "$BASH" -c ". '$defaults' 2>/dev/null; printf %s \"\${$1:-}\""; } # a default, read in a clean environment

ok "bin/defaults exists"                                  '[ -f "$defaults" ]'
for k in $knobs; do
  v=$(val $k)
  cell=$(grep -E "^\| \`$k\` \|" "$arch" | head -1 | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}' | sed 's/ s$//')
  ok "$k: the ARCHITECTURE.md table row matches the default ($v)"  '[ -n "$v" ] && [ "$cell" = "$v" ]'
done

ok "an env var overrides a default"                       '[ "$(DEVKIT_MAX_WORKERS=2 "$BASH" -c ". \"$defaults\"; echo \$DEVKIT_MAX_WORKERS")" = 2 ]'
ok "an empty env var gets the default (as :- did)"         '[ "$(DEVKIT_MAX_WORKERS= "$BASH" -c ". \"$defaults\"; echo \$DEVKIT_MAX_WORKERS")" = "$(val DEVKIT_MAX_WORKERS)" ] && [ -n "$(val DEVKIT_MAX_WORKERS)" ]'
ok "0 survives (DEVKIT_TIMEOUT=0 disables the timeout)"    '[ "$(DEVKIT_TIMEOUT=0 "$BASH" -c ". \"$defaults\"; echo \$DEVKIT_TIMEOUT")" = 0 ]'

ok "bin/spawn keeps no literal fallback for these knobs"   '! grep -q -E "DEVKIT_(MAX_WORKERS|MAX_DEPTH|CHILD_WAIT|TIMEOUT|VIEW_CLOSE_DELAY|VIEW):-" "$here/bin/spawn"'
ok "bin/spawn fails loudly when bin/defaults is missing"   'grep -q "cannot load" "$here/bin/spawn"'

# one home per rule: outside the env table, no number may sit next to a numeric knob's name
# (DEVKIT_VIEW is a mode, not a number; code lines are covered by the no-literal check above)
nknobs="DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW_CLOSE_DELAY"
prose() { cat "$here/README.md" "$here/AGENTS.md" "$here"/skills/*/SKILL.md; grep '^#' "$here/bin/spawn"; }
for k in $nknobs; do
  ok "no number next to $k in README, AGENTS, skills or the spawn header" \
     '! prose | grep -q -E "$k[^|]{0,80}[0-9]|[0-9][^|]{0,80}$k"'
done
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
