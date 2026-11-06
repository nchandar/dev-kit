#!/usr/bin/env bash
# Pins the rule text that tells agents to run workers interactive; the behavior is tested in spawn-interactive.test.sh.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
for f in AGENTS.md skills/dev-spawn/SKILL.md; do
  ok "$f: workers run interactive (DEVKIT_MODE=auto)" 'grep -q "DEVKIT_MODE=auto" "$here/$f" && grep -qi "interactive" "$here/$f"'
  ok "$f: headless is only the fallback when herdr is down" 'grep -i "headless" "$here/$f" | grep -qi "herdr is down"'
  ok "$f: never pick -p/exec/run by hand" 'grep -q -- "-p/exec/run" "$here/$f"'
done
ok "AGENTS.md: the rule sits under Always" 'sed -n "/^## Always/,/^## Library/p" "$here/AGENTS.md" | grep -q "DEVKIT_MODE=auto"'
ok "dev-spawn: the stale headless-one-shots line is gone" '! grep -q "headless one-shots" "$here/skills/dev-spawn/SKILL.md"'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
