#!/usr/bin/env bash
# Guards the sync discovery cost in bin/setup: one repo walk per run, reused by --check, --apply and
# the final --apply check; a foreign installer that can add links forces a fresh walk.
# Usage: tests/setup-discover.test.sh
set -u
unset TLA2TOOLS
unset DEVKIT_DIR DEVKIT_TASK DEVKIT_DEPTH CLAUDE_CODE_SESSION_ID
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
unset GIT_CONFIG_COUNT
base_path=/usr/bin:/bin:/usr/sbin:/sbin

# --- a private dev-kit copy: its own git repo with no upstream, so no fetch and no prompt
kit="$t/dev-kit"
mkdir -p "$kit/bin" "$kit/skills/dev-sync"
cp "$here/bin/setup" "$kit/bin/setup"
printf '# dev-sync\n' > "$kit/skills/dev-sync/SKILL.md"
git -C "$kit" init -q -b main
git -C "$kit" add -A
git -C "$kit" commit -qm base
setup="$kit/bin/setup"

# --- fake CLIs: every section is enabled and nothing real is probed or installed
fb="$t/bin"; mkdir -p "$fb"
fake() { { printf '#!/bin/bash\n'; printf '%s\n' "$2"; } > "$fb/$1"; chmod +x "$fb/$1"; }
fake bash 'case "${1:-}" in --version) echo "GNU bash, version 5.2.15(1)-release (test)";; *) exec /bin/bash "$@";; esac'
fake git 'case "${1:-}" in --version) echo "git version 2.43.0";; *) exec /usr/bin/git "$@";; esac'
fake perl 'echo "This is perl 5, version 34, subversion 1 (v5.34.1)"'
for n in claude codex opencode bun java; do fake "$n" ':'; done

base_home() { # dest: every skills root linked, so --apply offers no installer of its own
  h=$1
  mkdir -p "$h/.claude/skills" "$h/.codex/skills" "$h/.agents/skills" "$t/foreign/skills/dev-foreign"
  printf '# dev-foreign\n' > "$t/foreign/skills/dev-foreign/SKILL.md"
  [ -d "$t/foreign/.git" ] || { git -C "$t/foreign" init -q -b main; git -C "$t/foreign" add -A; git -C "$t/foreign" commit -qm base; }
  ln -s "$kit" "$h/.agents/dev-kit"
  for d in "$kit"/skills/dev-*; do
    ln -s "$d" "$h/.claude/skills/${d##*/}"
    ln -s "$d" "$h/.codex/skills/${d##*/}"
    ln -s "$d" "$h/.agents/skills/${d##*/}"
  done
  ln -s "$t/foreign/skills/dev-foreign" "$h/.agents/skills/dev-foreign"
}
count() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else printf 0; fi; }
check() { HOME="$1" PATH="$fb:$base_path" DEVKIT_SETUP_DISCOVER_LOG="$2" /bin/bash "$setup" --check > "$3" 2>&1; }
apply_n() { yes n | HOME="$1" PATH="$fb:$base_path" DEVKIT_SETUP_DISCOVER_LOG="$2" /bin/bash "$setup" --apply > "$3" 2>&1; }

# --- one walk per run: --check and --apply (whose final check reuses it) each discover once
H="$t/home-once"; base_home "$H"
check "$H" "$t/check1.log" "$t/check1.out"
ok "check: discovers once" '[ "$(count "$t/check1.log")" = 1 ]'
apply_n "$H" "$t/apply1.log" "$t/apply1.out"
ok "apply: discovers once (start and final check share it)" '[ "$(count "$t/apply1.log")" = 1 ]'
apply_n "$H" "$t/apply2.log" "$t/apply2.out"
ok "second apply: still one walk" '[ "$(count "$t/apply2.log")" = 1 ]'
ok "apply: the sync section still reports the foreign repo" 'grep -qx "skipped  sync:foreign  no upstream" "$t/apply1.out"'
ok "apply: the final check keeps its verdict" 'grep -qx "verdict: 1 missing" "$t/apply1.out"'

# --- a skills installer may add a link mid-apply, so the final check walks again and sees it
seed() { # name -> seed worktree path
  r="$t/remotes/$1.git"; w="$t/seed/$1"
  git init -q --bare -b main "$r"
  git init -q -b main "$w"
  mkdir -p "$w/skills/dev-$1"
  printf '# dev-%s\n' "$1" > "$w/skills/dev-$1/SKILL.md"
  git -C "$w" remote add origin "$r"
  git -C "$w" add -A
  git -C "$w" commit -qm base
  git -C "$w" push -q -u origin main
}
second="$t/second"
mkdir -p "$second/skills/dev-second"
printf '# dev-second\n' > "$second/skills/dev-second/SKILL.md"
git -C "$second" init -q -b main
git -C "$second" add -A
git -C "$second" commit -qm second
seed skillsx
w="$t/seed/skillsx"
cat > "$w/install.sh" <<S
#!/usr/bin/env bash
ln -sfn "$second/skills/dev-second" "\$HOME/.agents/skills/dev-second"
S
chmod +x "$w/install.sh"
git -C "$w" add -A; git -C "$w" commit -qm installer; git -C "$w" push -q origin HEAD
repo="$t/local/skillsx"; git clone -q "$t/remotes/skillsx.git" "$repo"
printf 'work\n' > "$w/skills/dev-skillsx/NOTE"
git -C "$w" add -A; git -C "$w" commit -qm "remote work"; git -C "$w" push -q origin HEAD
git -C "$repo" fetch -q
H2="$t/home-relink"; base_home "$H2"
ln -s "$repo/skills/dev-skillsx" "$H2/.agents/skills/dev-skillsx"
before=$(git -C "$repo" rev-parse HEAD)
printf 'y\ny\ny\n' | HOME="$H2" PATH="$fb:$base_path" DEVKIT_SETUP_DISCOVER_LOG="$t/relink.log" /bin/bash "$setup" --apply > "$t/relink.out" 2>&1
ok "relink: the pulled installer ran" '[ "$(git -C "$repo" rev-parse HEAD)" != "$before" ] && [ -L "$H2/.agents/skills/dev-second" ]'
ok "relink: the start walk and the final check each walk once" '[ "$(count "$t/relink.log")" = 2 ]'
ok "relink: the final check sees the repo the installer linked" 'grep -qx "skipped  sync:second  no upstream" "$t/relink.out"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
