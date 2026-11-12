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
mode_of() { if stat -f %Lp "$1" >/dev/null 2>&1; then stat -f %Lp "$1"; else stat -c %a "$1"; fi; }
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
# a symlinked config keeps its link and its 0600 mode: the write goes through to the target
mk link; mkdir -p "$t/oc/link/dotfiles"
printf '{"plugin":["x"]}\n' > "$t/oc/link/dotfiles/opencode.json"; chmod 600 "$t/oc/link/dotfiles/opencode.json"
ln -s ../../dotfiles/opencode.json "$t/oc/link/.config/opencode/opencode.json"
HOME="$t/oc/link" "$inst" >/dev/null 2>&1
ok "symlinked config: the link is kept"  '[ -L "$t/oc/link/.config/opencode/opencode.json" ] && [ "$(readlink "$t/oc/link/.config/opencode/opencode.json")" = ../../dotfiles/opencode.json ]'
ok "symlinked config: the target got todo"  '[ "$(todo "$t/oc/link/dotfiles/opencode.json")" = True ]'
ok "symlinked config: the 0600 mode is kept"  '[ "$(mode_of "$t/oc/link/dotfiles/opencode.json")" = 600 ]'
ok "symlinked config: no temp file is left"  '[ ! -e "$t/oc/link/dotfiles/opencode.json.tmp" ]'
# opencode command: one /dev-mode entry in the picker, linked to the repo's command file
cmd() { echo "$t/oc/$1/.config/opencode/commands/dev-mode.md"; }
old() { echo "$t/oc/$1/.config/opencode/commands/dev.md"; }
ok "the /dev-mode command links to the repo file"  '[ "$(readlink "$(cmd fresh)")" = "$here/opencode/commands/dev-mode.md" ] && [ -f "$(cmd fresh)" ]'
before=$(readlink "$(cmd fresh)"); HOME="$t/oc/fresh" "$inst" >/dev/null 2>&1
ok "rerun keeps the command link unchanged"  '[ -n "$before" ] && [ "$(readlink "$(cmd fresh)")" = "$before" ]'
mkdir -p "$t/oc/real/.config/opencode/commands"; echo mine > "$(cmd real)"; HOME="$t/oc/real" "$inst" >/dev/null 2>&1
ok "a real command file is never replaced"  '[ ! -L "$(cmd real)" ] && grep -qx mine "$(cmd real)"'
ok "the command file names dev-mode and \$ARGUMENTS"  'grep -q "^description: dev-kit:" "$(cmd fresh)" && grep -q "dev-mode" "$(cmd fresh)" && grep -q "\$ARGUMENTS" "$(cmd fresh)"'
mkdir -p "$t/oc/mig/.config/opencode/commands"; ln -s "$here/opencode/commands/dev.md" "$(old mig)"; HOME="$t/oc/mig" "$inst" >/dev/null 2>&1
ok "a repo-pointing old dev.md symlink is removed and replaced"  '[ ! -L "$(old mig)" ] && [ "$(readlink "$(cmd mig)")" = "$here/opencode/commands/dev-mode.md" ]'
mkdir -p "$t/oc/realold/.config/opencode/commands"; echo mine > "$(old realold)"; HOME="$t/oc/realold" "$inst" >/dev/null 2>&1
ok "a real old dev.md file is left alone"  '[ ! -L "$(old realold)" ] && grep -qx mine "$(old realold)"'
mkdir -p "$t/oc/ext/.config/opencode/commands"; ln -s /tmp "$(old ext)"; HOME="$t/oc/ext" "$inst" >/dev/null 2>&1
ok "a dev.md link pointing elsewhere is left alone"  '[ "$(readlink "$(old ext)")" = /tmp ]'
mkdir -p "$t/nooc"; HOME="$t/nooc" PATH=/usr/bin:/bin "$inst" >/dev/null 2>&1; rc=$?
ok "no opencode, no config dir: nothing is created"  '[ ! -e "$t/nooc/.config/opencode" ]'
ok "no opencode: no commands dir either"  '[ $rc -eq 0 ] && [ ! -e "$t/nooc/.config/opencode/commands" ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
