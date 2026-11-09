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
# changing a running worker: the updates file by default, a message only to interrupt
ok "dev-spawn: corrections go to updates/<id>.md, a message only interrupts" 'grep -q "updates/<id>.md" "$here/skills/dev-spawn/SKILL.md" && grep -qi "only to interrupt" "$here/skills/dev-spawn/SKILL.md"' # pitfall-ok: src-grep reads skill prose for doc-sync
# lead rule: rebase on the latest default branch before the handoff, and prove it in the handoff
sp="$here/skills/dev-spawn/SKILL.md"
lead_row() { grep '^| "give it a lead"' "$sp"; }
rules() { sed -n '/^## Worker rules/,/^\*\*Hand off to/p' "$sp"; }
ok "dev-spawn lead row: --lead alone, it implies the worktree"  'lead_row | grep -q -- "bin/spawn --lead --shape ship" && ! lead_row | grep -q -- "--lead --worktree"' # pitfall-ok: src-grep reads skill prose, not spawn source
ok "dev-spawn lead row: rebase onto the latest default branch"  'lead_row | grep -q "rebase" && lead_row | grep -qi "fetch"'
ok "dev-spawn lead row: rerun suite, lint and bin/verify"       'lead_row | grep -q "bin/verify" && lead_row | grep -qi "lint"'
ok "dev-spawn lead row: handoff carries base and behind: 0"     'lead_row | grep -q "base: <sha>" && lead_row | grep -q "behind: 0"'
ok "dev-spawn lead row: brief may carry an owns: line"          'lead_row | grep -q "owns:"'
ok "dev-spawn lead row: accept refuses a stale base"            'lead_row | grep -qi "accept" && lead_row | grep -qi "refuses"'
ok "dev-spawn: helpers share one pool, first come first served" 'grep -qi "share the one worker pool" "$sp" && grep -qi "first come first served" "$sp" && ! grep -qi "helpers (not enforced)" "$sp"'
ok "worker rules: the lead rule (fetch, rebase, base and behind)" 'rules | grep -q "rebase" && rules | grep -q "base: <sha>" && rules | grep -q "behind: 0"'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
