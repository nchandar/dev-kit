#!/usr/bin/env bash
# Tests for install.sh under a fake HOME, so a new machine's first run is covered. Usage: tests/install.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); inst="$here/install.sh"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
skills="dev-debug dev-feature dev-research dev-review dev-spawn dev-mode"

HOME="$t" "$inst" >/dev/null 2>&1; rc=$?
ok "fresh machine: exits 0"                     '[ $rc -eq 0 ]'
ok "dev-kit dir linked to the repo"             '[ "$(readlink "$t/.agents/dev-kit")" = "$here" ]'
allok=1; for r in .claude/skills .codex/skills .agents/skills; do for n in $skills; do [ -f "$t/$r/$n/SKILL.md" ] || allok=0; done; done
ok "6 skills resolve in all 3 skill dirs"       '[ $allok -eq 1 ]'

HOME="$t" "$inst" >/dev/null 2>&1; rc=$?
ok "rerun is safe (exits 0)"                    '[ $rc -eq 0 ]'

rm "$t/.claude/skills/dev-debug"; mkdir "$t/.claude/skills/dev-debug"; echo mine > "$t/.claude/skills/dev-debug/own.txt"
HOME="$t" "$inst" >/dev/null 2>&1; rc=$?
ok "a real directory is never replaced"         '[ $rc -eq 0 ] && [ -f "$t/.claude/skills/dev-debug/own.txt" ] && [ ! -L "$t/.claude/skills/dev-debug" ]'

ln -sfn /tmp "$t/.codex/skills/dev-review"
HOME="$t" "$inst" >/dev/null 2>&1
ok "a stale symlink is re-pointed"              '[ "$(readlink "$t/.codex/skills/dev-review")" = "$here/skills/dev-review" ]'
# opencode: the todo side panel needs experimental.todo in the service config; additive, never overriding
oc() { echo "$t/oc/$1/.config/opencode/opencode.jsonc"; }
mk() { mkdir -p "$t/oc/$1/.config/opencode"; }
todo() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("experimental",{}).get("todo"))' "$1" 2>/dev/null; }
mk fresh; HOME="$t/oc/fresh" "$inst" >"$t/o1.out" 2>&1
ok "opencode dir without a config: todo is enabled"   '[ "$(todo "$(oc fresh)")" = True ]'
ok "installer tells the user to restart the service"  'grep -q "opencode service restart" "$t/o1.out"'
mk keep; echo '{"plugin": ["x"], "experimental": {"other": 1}}' > "$(oc keep)"; HOME="$t/oc/keep" "$inst" >/dev/null 2>&1
ok "existing keys are kept, todo added"  '[ "$(todo "$(oc keep)")" = True ] && grep -q "\"plugin\"" "$(oc keep)" && grep -q "\"other\"" "$(oc keep)"'
mk off; echo '{"experimental": {"todo": false}}' > "$(oc off)"; HOME="$t/oc/off" "$inst" >/dev/null 2>&1
ok "an explicit todo=false is respected"  '[ "$(todo "$(oc off)")" = False ]'
mk cm; printf '{\n  // mine\n  "plugin": []\n}\n' > "$(oc cm)"; cp "$(oc cm)" "$t/cm.before"; HOME="$t/oc/cm" "$inst" >"$t/o2.out" 2>&1
ok "a commented config is left untouched and the user is told how"  'cmp -s "$(oc cm)" "$t/cm.before" && grep -q "experimental" "$t/o2.out"'
HOME="$t/oc/keep" "$inst" >/dev/null 2>&1; cp "$(oc keep)" "$t/keep.1"; HOME="$t/oc/keep" "$inst" >/dev/null 2>&1
ok "rerun leaves the config unchanged"  'cmp -s "$(oc keep)" "$t/keep.1"'
mkdir -p "$t/nooc"; HOME="$t/nooc" PATH=/usr/bin:/bin "$inst" >/dev/null 2>&1
ok "no opencode, no config dir: nothing is created"  '[ ! -e "$t/nooc/.config/opencode" ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
