#!/usr/bin/env bash
# A main session must be told to load a deferred todo tool (TaskCreate is deferred in Claude Code). Usage: tests/todo-hint.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
rule() { grep -E "host todo list" "$here/AGENTS.md"; }

ok "AGENTS.md says to ToolSearch a deferred TaskCreate"  'rule | grep -qF "TaskCreate (deferred, load it with ToolSearch first)"'
ok "CLAUDE.md carries it (symlink or copy)"        'grep -qF "TaskCreate (deferred, load it with ToolSearch first)" "$here/CLAUDE.md"'
for t in TaskCreate TodoWrite update_plan todowrite; do
  ok "AGENTS.md rule names $t"                     'rule | grep -qF "$t"'
done
ok "the old contradictory order is gone"          '! rule | grep -qF "before reading the playbook"'
ok "the rule reads the playbook, then opens the todo list"  'rule | grep -qF "First action of any route: read its playbook, then open the host todo list with its checklist verbatim"'
ok "dev-mode step 4 reads the playbook before the todo list"  'grep -E "^- \[ \] 4\." "$here/skills/dev-mode/SKILL.md" | grep -qE "Read .*then.*todo list"'
ok "the tool-optional wording is gone"             '! grep -qF "whichever exists" "$here/AGENTS.md"'
ok "the rule keeps tick-as-you-go and skipped steps"  'rule | grep -qiF "tick items as steps finish" && rule | grep -qF "skipped steps stay"'
ok "dev-mode step 4 opens the todo list first"     'grep -E "^- \[ \] 4\." "$here/skills/dev-mode/SKILL.md" | grep -qi "todo list"'
ok "bin/spawn worker prompt names all four tools"  'for t in TaskCreate TodoWrite update_plan todowrite; do grep -q "$t" "$here/bin/spawn" || exit 1; done'  # pitfall-ok: src-grep the brief requires pinning the worker prompt text
ok "worker prompt in bin/spawn still carries the ToolSearch hint"  'grep -q "if the tool is deferred, load it with ToolSearch first" "$here/bin/spawn"'  # pitfall-ok: src-grep the brief requires pinning the worker prompt text
ok "the eight playbooks stay free of the hint (one home)"  '! grep -l "ToolSearch" "$here"/skills/dev-{feature,refactor,debug,research,review,spawn,eval,learn}/SKILL.md | grep -q .'
ok "opencode /dev-mode command points at the AGENTS.md todo rule"  'grep -q "AGENTS.md" "$here/opencode/commands/dev-mode.md" && grep -qi "todo" "$here/opencode/commands/dev-mode.md"'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
