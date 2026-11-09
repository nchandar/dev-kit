#!/usr/bin/env bash
# Fixture tests for bin/lint-budget. Usage: tests/lint-budget.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); lint="$here/bin/lint-budget"
pass=0; fail=0
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

skill() { # root name description [extra-lines] [folder]
  local d=${5:-$2}; mkdir -p "$1/skills/$d"
  { printf -- '---\nname: %s\ndescription: %s\n---\n# T\nRun bin/ledger at each step. Read library/tdd. Closeout: library/state.\n' "$2" "$3"
    printf '## When to Use\n## Checklist\n## Rationalizations\n## Red Flags\n## Verification\n'
    [ -n "${4:-}" ] && seq 1 "$4" | sed 's/^/line /'; } > "$1/skills/$d/SKILL.md"
}
lib() { # root name [extra-lines]
  mkdir -p "$1/library"
  { printf '# %s\nRecord outcomes with bin/ledger.\n## When to Use\n## Steps\n## Red Flags\n## Verification\n' "$2"
    [ -n "${3:-}" ] && seq 1 "$3" | sed 's/^/line /'; } > "$1/library/$2.md"
}
good() {
  local r=$1; mkdir -p "$r"
  skill "$r" dev-feature "build features slice by slice"
  skill "$r" dev-debug "reproduce root cause regression"
  skill "$r" dev-research "investigate sources write report"
  skill "$r" dev-review "standards spec reviewers merged"
  skill "$r" dev-spawn "delegate headless worker briefs"
  lib "$r" tdd; lib "$r" verify; lib "$r" state
  echo "# router" > "$r/AGENTS.md"
}
mut() { rm -rf "$M"; cp -R "$t/good" "$M"; }


sec_core() {
  expect "good tree passes" 0 "$t/good"

  mut; head -c 7000 /dev/zero | tr '\0' x > "$M/AGENTS.md"
  expect "AGENTS.md over 6KB fails" 1 "$M"
  mut; skill "$M" dev-feature "build features slice by slice" 151
  expect "SKILL.md over 150 lines fails" 1 "$M"
  mut; skill "$M" dev-feature "$(head -c 4200 /dev/zero | tr '\0' a)"
  expect "descriptions over 4KB total fails" 1 "$M"
  mut; printf -- '---\nname: dev-feature\ndescription: >\n  folded\n---\n# T\n' > "$M/skills/dev-feature/SKILL.md"
  expect "multi-line description fails" 1 "$M"
  mut; skill "$M" dev-twin "standards spec reviewers merged plus"
  expect "colliding descriptions fail" 1 "$M"
  mut; rm -rf "$M/skills/dev-spawn" "$M/skills/dev-review"
  expect "fewer than 4 skills fails" 1 "$M"
  expect "fewer than 4 skills ok with --partial" 0 "$M" --partial
  mut; for n in a b c d e f g; do skill "$M" "dev-x$n" "unique$n alpha$n beta$n"; done
  expect "12 skills ok" 0 "$M"
  mut; for n in a b c d e f g h; do skill "$M" "dev-x$n" "unique$n alpha$n beta$n"; done
  expect "more than 12 skills fails" 1 "$M"
  mut; skill "$M" feature "build features slice by slice" "" dev-feature
  expect "name without dev- prefix fails" 1 "$M"
  mut; skill "$M" dev-other "build features slice by slice" "" dev-feature
  expect "name differing from folder fails" 1 "$M"
  mut; sed -i.bak 's/bin\/ledger/nothing/' "$M/skills/dev-debug/SKILL.md"; rm "$M/skills/dev-debug/SKILL.md.bak"
  expect "skill without ledger line fails" 1 "$M"
  mut; sed -i.bak 's/bin\/ledger/nothing/' "$M/library/tdd.md"; rm "$M/library/tdd.md.bak"
  expect "library file without ledger line fails" 1 "$M"
  mut; lib "$M" tdd 81
  expect "library file over 80 lines fails" 1 "$M"
  mut; rm "$M/library/tdd.md"
  expect "unresolved library reference fails" 1 "$M"
  mut; echo "see ../shared/ref.md" >> "$M/skills/dev-debug/SKILL.md"
  expect "escaping the skill dir fails" 1 "$M"
  mut; sed -i.bak '/Red Flags/d' "$M/skills/dev-debug/SKILL.md"; rm "$M/skills/dev-debug/SKILL.md.bak"
  expect "skill missing section fails" 1 "$M"
  mut; sed -i.bak '/## Steps/d' "$M/library/verify.md"; rm "$M/library/verify.md.bak"
  expect "library missing section fails" 1 "$M"
}

sec_safety() {
  # --- public-safety: nothing personal or secret may live in this repo
  # fixtures are assembled at runtime so this file holds no literal paths, addresses or key markers
  A="@"; U="/Use""rs"; HM="/ho""me"; DASH="-----"
  leak() { mut; printf '%s\n' "$1" > "$M/notes.txt"; }
  leak "see $U/bob/project/file";               expect "home path /Users/<name> fails" 1 "$M"
  leak "cd $HM/alice/src";                        expect "home path /home/<name> fails" 1 "$M"
  leak "mail me at someone${A}gmail.com";              expect "email address fails" 1 "$M"
  leak "contact: dev${A}example.com";                  expect "example.com address is allowed" 0 "$M"
  leak "token ghp_$(printf 'a%.0s' $(seq 1 36))";   expect "GitHub token shape fails" 1 "$M"
  leak "key sk-$(printf 'b%.0s' $(seq 1 30))";      expect "sk- key shape fails" 1 "$M"
  leak "aws AKIA$(printf 'C%.0s' $(seq 1 16))";     expect "AWS key id shape fails" 1 "$M"
  leak "${DASH}BEGIN RSA PRIV""ATE KEY${DASH}";           expect "private key header fails" 1 "$M"
  leak "use ~/.agents/dev-kit and \$HOME/x";        expect "tilde and \$HOME paths are fine" 0 "$M"
}

sec_budget() {
  # --- library total budget: tight, no context bloat
  mut; for n in a b c d e f g h; do { printf '# big%s\nRecord outcomes with bin/ledger.\n## When to Use\n## Steps\n## Red Flags\n## Verification\n' "$n"; for i in $(seq 1 70); do printf 'padding line %s %s xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$n" "$i"; done; } > "$M/library/big$n.md"; done
  expect "library over the total byte cap fails" 1 "$M"
}

sec_deep() {
  # --- library/deep: on-demand long tail, never auto-loaded
  deepf() { mkdir -p "$M/library/deep"; { printf '# %s\n## When to Load\n- trigger\n## Pattern\n1. step\n## Red Flags\n- flag\n' "$1"; [ -n "${2:-}" ] && seq 1 "$2" | sed 's/^/line /'; } > "$M/library/deep/$1.md"; }
  mut; deepf ok-one
  expect "a valid deep file passes" 0 "$M"
  mut; deepf too-long 45
  expect "deep file over 45 lines fails" 1 "$M"
  mut; mkdir -p "$M/library/deep"; printf '# x\n## Pattern\n1. a\n## Red Flags\n- b\n' > "$M/library/deep/nosec.md"
  expect "deep file missing When to Load fails" 1 "$M"
  mut; for n in $(seq 1 40); do deepf "big$n" 20; { printf '# big\n## When to Load\n- t\n## Pattern\n'; for i in $(seq 1 24); do printf 'padding %s %s xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$n" "$i"; done; printf '## Red Flags\n- f\n'; } > "$M/library/deep/big$n.md"; done
  expect "deep folder over its byte cap fails" 1 "$M"
  mut; deepf ok-two; echo "see library/deep/ok-two" >> "$M/skills/dev-debug/SKILL.md"
  expect "reference to an existing deep file resolves" 0 "$M"
  mut; echo "see library/deep/missing-one" >> "$M/skills/dev-debug/SKILL.md"
  expect "reference to a missing deep file fails" 1 "$M"
}

sec_recipes() {
  # --- library/recipes: reusable procedures learned in real work, loaded on demand, indexed
  recipe() { mkdir -p "$M/library/recipes"; { printf '# %s\n## When to Load\n- trigger\n## Steps\n1. do it\n## Gotchas\n- careful\n## Verified\n- 2026-01-01 tool 1.0\n' "$1"; [ -n "${2:-}" ] && seq 1 "$2" | sed 's/^/line /'; } > "$M/library/recipes/$1.md"; }
  index() { mkdir -p "$M/library/recipes"; : > "$M/library/recipes/index.md"; for n in "$@"; do printf '%s: when you need it\n' "$n" >> "$M/library/recipes/index.md"; done; }
  mut; recipe build-app; index build-app
  expect "a valid recipe with an index passes" 0 "$M"
  mut; recipe long-one 45; index long-one
  expect "recipe over 45 lines fails" 1 "$M"
  mut; mkdir -p "$M/library/recipes"; printf '# x\n## When to Load\n- t\n## Steps\n1. a\n## Verified\n- d\n' > "$M/library/recipes/nogot.md"; index nogot
  expect "recipe missing Gotchas fails" 1 "$M"
  mut; recipe unlisted; index
  expect "recipe missing from the index fails" 1 "$M"
  mut; recipe real-one; index real-one ghost-one
  expect "index entry with no file fails" 1 "$M"
  mut; mkdir -p "$M/library/recipes"; for n in $(seq 1 30); do { printf '# big%s\n## When to Load\n- t\n## Steps\n' "$n"; for i in $(seq 1 30); do printf 'padding %s %s xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$n" "$i"; done; printf '## Gotchas\n- g\n## Verified\n- v\n'; } > "$M/library/recipes/big$n.md"; done; index $(for n in $(seq 1 30); do echo big$n; done)
  expect_msg "recipes folder over its byte cap fails" 1 "library/recipes totals" "$M"
  mut; recipe good-one; index good-one; echo "see library/recipes/good-one" >> "$M/skills/dev-debug/SKILL.md"
  expect "reference to an existing recipe resolves" 0 "$M"
  mut; echo "see library/recipes/missing-one" >> "$M/skills/dev-debug/SKILL.md"
  expect "reference to a missing recipe fails" 1 "$M"
}

sec_naming() {
  # --- naming the deep or recipes folder in prose is not a reference to a file
  mut; echo "edit a library/deep/ file or add one to library/recipes/ when it fits" >> "$M/skills/dev-debug/SKILL.md"
  expect "mentioning the deep and recipes folders in prose is fine" 0 "$M"

  # --- every skill except dev-learn must carry the closeout reference to library/state
  mut; sed -i.bak 's/ Closeout: library\/state\.//' "$M/skills/dev-debug/SKILL.md"; rm "$M/skills/dev-debug/SKILL.md.bak"
  expect "a skill without a library/state reference fails" 1 "$M"
  mut; skill "$M" dev-learn "queued lessons become library edits after approval"; sed -i.bak 's/ Closeout: library\/state\.//' "$M/skills/dev-learn/SKILL.md"; rm "$M/skills/dev-learn/SKILL.md.bak"
  expect "dev-learn is exempt from the library/state reference" 0 "$M"

  # a linked worktree has a .git pointer FILE ("gitdir: /Users/..."); it must not trip the public-safety scan
  h="$t/Users/tester/repo"; mkdir -p "$h"; good "$h"
  ( cd "$h" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm i && git worktree add -q "$t/Users/tester/wt" -b wt )
  expect "lint passes inside a linked worktree" 0 "$t/Users/tester/wt"
}


# Each section mutates its own copy of the good tree, so all six run side by side; logs merge in order.
section() { # name fn
  ( p=0; f=0
    ok() { if eval "$2"; then p=$((p+1)); echo "ok   $1"; else f=$((f+1)); echo "FAIL $1   [$2]"; fi; }
    expect() { local n=$1 want=$2 r=$3; shift 3
      out=$("$lint" "$r" "$@" 2>&1); rc=$?; [ $rc -ne 0 ] && rc=1
      if [ $rc -eq $want ]; then p=$((p+1)); echo "ok   $n"
      else f=$((f+1)); echo "FAIL $n (rc=$rc want=$want)"; echo "$out" | sed 's/^/     /'; fi; }
    expect_msg() { local n=$1 want=$2 msg=$3 r=$4; shift 4
      out=$("$lint" "$r" "$@" 2>&1); rc=$?; [ $rc -ne 0 ] && rc=1
      if [ $rc -eq $want ] && printf '%s\n' "$out" | grep -qF "$msg"; then p=$((p+1)); echo "ok   $n"
      else f=$((f+1)); echo "FAIL $n (rc=$rc want=$want msg=$msg)"; echo "$out" | sed 's/^/     /'; fi; }
    M="$t/m-$1"; eval "$2"
    echo "$p $f" > "$t/$1.cnt" ) > "$t/$1.log" 2>&1 &
}
good "$t/good" # the base tree every section mutates
for s in core safety budget deep recipes naming; do section "$s" "sec_$s"; done
wait
for s in core safety budget deep recipes naming; do
  cat "$t/$s.log"; if read -r p f < "$t/$s.cnt" 2>/dev/null; then pass=$((pass+p)); fail=$((fail+f)); else fail=$((fail+1)); echo "FAIL section $s crashed"; fi
done
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
