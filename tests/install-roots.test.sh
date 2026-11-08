#!/usr/bin/env bash
# Reinstall safety: one entry per skill per root, no dangling or nested links. Fake HOME only. Usage: tests/install-roots.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
roots=".claude/skills .codex/skills .agents/skills"
want=$(ls -d "$here"/skills/dev-* | wc -l | tr -d ' ')

snap() { # home: every root's entries as "root name target", sorted
  for r in $roots; do for e in "$1/$r"/*; do [ -L "$e" ] || [ -e "$e" ] || continue; echo "$r $(basename "$e") $(readlink "$e")"; done; done | sort
}

# suite <label> <installer> <repo dir the links must point into>; prints "label: check" lines, returns the number failed
suite() {
  local lbl=$1 inst=$2 repo=$3 h f=0 r e n i
  c() { if eval "$2"; then :; else f=$((f+1)); echo "$lbl: $1"; fi; }
  h=$(mktemp -d "$t/h.XXXXXX")
  for i in 1 2 3; do HOME="$h" "$inst" >/dev/null 2>&1; snap "$h" > "$h/snap.$i"; done
  c "run 2 equals run 1" 'cmp -s "$h/snap.1" "$h/snap.2"'
  c "run 3 equals run 1" 'cmp -s "$h/snap.1" "$h/snap.3"'
  for r in $roots; do
    c "$r: one entry per dev-* skill dir" '[ "$(ls -d "$h/$r"/dev-* 2>/dev/null | wc -l | tr -d " ")" = "$want" ]'
    c "$r: no duplicate names" '[ -z "$(ls "$h/$r" | sort | uniq -d)" ]'
    for e in "$repo"/skills/dev-*; do n=$(basename "$e")
      c "$r/$n: links into the repo and resolves" '[ "$(readlink "$h/$r/$n")" = "$repo/skills/$n" ] && [ -f "$h/$r/$n/SKILL.md" ]'
      c "$r/$n: no nested link" '[ ! -e "$repo/skills/$n/$n" ] && [ ! -L "$repo/skills/$n/$n" ]'
      c "$r/$n: same target as .claude" '[ "$(readlink "$h/$r/$n")" = "$(readlink "$h/.claude/skills/$n")" ]'
    done
  done
  # a real dir and a real file are skipped, the other roots still link
  rm "$h/.codex/skills/dev-mode" "$h/.agents/skills/dev-debug"
  mkdir "$h/.codex/skills/dev-mode"; echo mine > "$h/.codex/skills/dev-mode/own.txt"; echo keep > "$h/.agents/skills/dev-debug"
  HOME="$h" "$inst" > "$h/real.out" 2>&1
  c "real dir reported as skipped" 'grep -q "skip real file: $h/.codex/skills/dev-mode" "$h/real.out"'
  c "real file reported as skipped" 'grep -q "skip real file: $h/.agents/skills/dev-debug" "$h/real.out"'
  c "real dir untouched" '[ ! -L "$h/.codex/skills/dev-mode" ] && [ "$(ls "$h/.codex/skills/dev-mode")" = own.txt ] && grep -qx mine "$h/.codex/skills/dev-mode/own.txt"'
  c "real file byte-identical" '[ ! -L "$h/.agents/skills/dev-debug" ] && [ "$(cat "$h/.agents/skills/dev-debug")" = keep ]'
  c "other roots still link the skipped names" '[ "$(readlink "$h/.claude/skills/dev-mode")" = "$repo/skills/dev-mode" ] && [ "$(readlink "$h/.claude/skills/dev-debug")" = "$repo/skills/dev-debug" ] && [ "$(readlink "$h/.agents/skills/dev-mode")" = "$repo/skills/dev-mode" ] && [ "$(readlink "$h/.codex/skills/dev-debug")" = "$repo/skills/dev-debug" ]'
  return $f
}

out=$(suite real "$here/install.sh" "$here"); rc=$?
ok "3 reruns: identical entries and targets, one per skill per root, no dangling, no nested, same target across roots" '[ $rc -eq 0 ] && [ -z "$out" ]'
[ -z "$out" ] || echo "$out"
ok "the repo has dev-* skills to compare" '[ "$want" -ge 1 ]'

# prune: only a dangling dev-* symlink into this repo's skills dir goes; all else stays
h="$t/stale"; mkdir "$h"; HOME="$h" "$here/install.sh" >/dev/null 2>&1
for r in $roots; do
  ln -sfn "$here/skills/dev-oldname" "$h/$r/dev-oldname"
  ln -sfn "$t/gone/skills/dev-elsewhere" "$h/$r/dev-elsewhere"
  ln -sfn "$here/skills/dev-mode" "$h/$r/other-live"
  ln -sfn "$here/skills/dev-gone" "$h/$r/notdev-dangling"
  mkdir "$h/$r/dev-realdir"; echo mine > "$h/$r/dev-realdir/own.txt"
done
HOME="$h" "$here/install.sh" > "$h/prune.out" 2>&1
HOME="$h" "$here/install.sh" > "$h/rerun.out" 2>&1
gone=1; kept=1; real=1; nondev=1; live=1
for r in $roots; do
  [ ! -e "$h/$r/dev-oldname" ] && [ ! -L "$h/$r/dev-oldname" ] || gone=0
  [ -L "$h/$r/dev-elsewhere" ] || kept=0
  [ -d "$h/$r/dev-realdir" ] && [ ! -L "$h/$r/dev-realdir" ] && grep -qx mine "$h/$r/dev-realdir/own.txt" || real=0
  [ -L "$h/$r/notdev-dangling" ] && [ -L "$h/$r/other-live" ] || nondev=0
  [ "$(readlink "$h/$r/dev-mode")" = "$here/skills/dev-mode" ] || live=0
  grep -qx "pruned stale: $h/$r/dev-oldname" "$h/prune.out" || gone=0
done
ok "stale dev-oldname links are pruned and reported in every root" '[ $gone -eq 1 ]'
ok "a dangling dev-* link pointing outside the repo skills dir is kept" '[ $kept -eq 1 ]'
ok "a dev-* real dir is kept" '[ $real -eq 1 ]'
ok "non-dev links are kept, dangling or live" '[ $nondev -eq 1 ]'
ok "live dev-* links are kept" '[ $live -eq 1 ]'
ok "only the stale links were reported" '[ "$(grep -c "^pruned stale:" "$h/prune.out")" = 3 ]'
ok "rerun prints no pruned line" '! grep -q "^pruned" "$h/rerun.out"'

# ln -sfn over an existing symlink-to-dir must not nest (plain ln -sf would)
h="$t/nest"; mkdir "$h"; HOME="$h" "$here/install.sh" >/dev/null 2>&1; HOME="$h" "$here/install.sh" >/dev/null 2>&1
ok "two reruns create no dev-mode/dev-mode link in a root or in the repo" '[ ! -e "$h/.claude/skills/dev-mode/dev-mode" ] && [ ! -L "$here/skills/dev-mode/dev-mode" ] && [ ! -L "$h/.agents/dev-kit/dev-kit" ]'

# mutation: each broken installer, in a scratch repo copy, must fail the suite
mkrepo() { mkdir "$t/$1"; cp -R "$here/skills" "$t/$1/skills"; sed "$2" "$here/install.sh" > "$t/$1/install.sh"; chmod +x "$t/$1/install.sh"; }
mkrepo m_nest 's/ln -sfn/ln -sf/'
mkrepo m_real 's/if \[ -e "\$2" \] && \[ ! -L "\$2" \]; then/if false; then/'
mkrepo m_root 's# "\$HOME/.agents/skills"; do# ; do#'
mkrepo m_dup 's#link "\$d" "\$root/\$(basename "\$d")"#link "$d" "$root/$(basename "$d")"; link "$d" "$root/$(basename "$d")-copy"#'
for m in m_nest m_real m_root m_dup; do
  mo=$(suite "$m" "$t/$m/install.sh" "$t/$m" 2>/dev/null); mrc=$?
  ok "mutation $m is caught ($mrc checks failed)" '[ $mrc -gt 0 ]'
done
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
