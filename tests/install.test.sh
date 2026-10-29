#!/usr/bin/env bash
# Tests for install.sh under a fake HOME, so a new machine's first run is covered. Usage: tests/install.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); inst="$here/install.sh"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
skills="dev-debug dev-feature dev-research dev-review dev-spawn"

HOME="$t" "$inst" >/dev/null 2>&1; rc=$?
ok "fresh machine: exits 0"                     '[ $rc -eq 0 ]'
ok "dev-kit dir linked to the repo"             '[ "$(readlink "$t/.agents/dev-kit")" = "$here" ]'
allok=1; for r in .claude/skills .codex/skills .agents/skills; do for n in $skills; do [ -f "$t/$r/$n/SKILL.md" ] || allok=0; done; done
ok "5 skills resolve in all 3 skill dirs"       '[ $allok -eq 1 ]'

HOME="$t" "$inst" >/dev/null 2>&1; rc=$?
ok "rerun is safe (exits 0)"                    '[ $rc -eq 0 ]'

rm "$t/.claude/skills/dev-debug"; mkdir "$t/.claude/skills/dev-debug"; echo mine > "$t/.claude/skills/dev-debug/own.txt"
HOME="$t" "$inst" >/dev/null 2>&1; rc=$?
ok "a real directory is never replaced"         '[ $rc -eq 0 ] && [ -f "$t/.claude/skills/dev-debug/own.txt" ] && [ ! -L "$t/.claude/skills/dev-debug" ]'

ln -sfn /tmp "$t/.codex/skills/dev-review"
HOME="$t" "$inst" >/dev/null 2>&1
ok "a stale symlink is re-pointed"              '[ "$(readlink "$t/.codex/skills/dev-review")" = "$here/skills/dev-review" ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
