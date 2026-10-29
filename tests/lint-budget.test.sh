#!/usr/bin/env bash
# Fixture tests for bin/lint-budget. Usage: tests/lint-budget.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); lint="$here/bin/lint-budget"
pass=0; fail=0
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

skill() { # root name description [extra-lines] [folder]
  local d=${5:-$2}; mkdir -p "$1/skills/$d"
  { printf -- '---\nname: %s\ndescription: %s\n---\n# T\nRun bin/ledger at each step. Read library/tdd.\n' "$2" "$3"
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
  lib "$r" tdd; lib "$r" verify
  echo "# router" > "$r/AGENTS.md"
}
expect() { # name want root [args]
  local n=$1 want=$2 r=$3; shift 3
  out=$("$lint" "$r" "$@" 2>&1); rc=$?; [ $rc -ne 0 ] && rc=1
  if [ $rc -eq $want ]; then pass=$((pass+1)); echo "ok   $n"
  else fail=$((fail+1)); echo "FAIL $n (rc=$rc want=$want)"; echo "$out" | sed 's/^/     /'; fi
}
mut() { rm -rf "$t/m"; cp -R "$t/good" "$t/m"; }

good "$t/good"
expect "good tree passes" 0 "$t/good"

mut; head -c 7000 /dev/zero | tr '\0' x > "$t/m/AGENTS.md"
expect "AGENTS.md over 6KB fails" 1 "$t/m"
mut; skill "$t/m" dev-feature "build features slice by slice" 151
expect "SKILL.md over 150 lines fails" 1 "$t/m"
mut; skill "$t/m" dev-feature "$(head -c 4200 /dev/zero | tr '\0' a)"
expect "descriptions over 4KB total fails" 1 "$t/m"
mut; printf -- '---\nname: dev-feature\ndescription: >\n  folded\n---\n# T\n' > "$t/m/skills/dev-feature/SKILL.md"
expect "multi-line description fails" 1 "$t/m"
mut; skill "$t/m" dev-twin "standards spec reviewers merged plus"
expect "colliding descriptions fail" 1 "$t/m"
mut; rm -rf "$t/m/skills/dev-spawn" "$t/m/skills/dev-review"
expect "fewer than 4 skills fails" 1 "$t/m"
expect "fewer than 4 skills ok with --partial" 0 "$t/m" --partial
mut; for n in a b; do skill "$t/m" "dev-x$n" "unique$n alpha$n beta$n"; done
expect "more than 6 skills fails" 1 "$t/m"
mut; skill "$t/m" feature "build features slice by slice" "" dev-feature
expect "name without dev- prefix fails" 1 "$t/m"
mut; skill "$t/m" dev-other "build features slice by slice" "" dev-feature
expect "name differing from folder fails" 1 "$t/m"
mut; sed -i.bak 's/bin\/ledger/nothing/' "$t/m/skills/dev-debug/SKILL.md"; rm "$t/m/skills/dev-debug/SKILL.md.bak"
expect "skill without ledger line fails" 1 "$t/m"
mut; sed -i.bak 's/bin\/ledger/nothing/' "$t/m/library/tdd.md"; rm "$t/m/library/tdd.md.bak"
expect "library file without ledger line fails" 1 "$t/m"
mut; lib "$t/m" tdd 81
expect "library file over 80 lines fails" 1 "$t/m"
mut; rm "$t/m/library/tdd.md"
expect "unresolved library reference fails" 1 "$t/m"
mut; echo "see ../shared/ref.md" >> "$t/m/skills/dev-debug/SKILL.md"
expect "escaping the skill dir fails" 1 "$t/m"
mut; sed -i.bak '/Red Flags/d' "$t/m/skills/dev-debug/SKILL.md"; rm "$t/m/skills/dev-debug/SKILL.md.bak"
expect "skill missing section fails" 1 "$t/m"
mut; sed -i.bak '/## Steps/d' "$t/m/library/verify.md"; rm "$t/m/library/verify.md.bak"
expect "library missing section fails" 1 "$t/m"

# --- public-safety: nothing personal or secret may live in this repo
# fixtures are assembled at runtime so this file holds no literal paths, addresses or key markers
A="@"; U="/Use""rs"; HM="/ho""me"; DASH="-----"
leak() { mut; printf '%s\n' "$1" > "$t/m/notes.txt"; }
leak "see $U/bob/project/file";               expect "home path /Users/<name> fails" 1 "$t/m"
leak "cd $HM/alice/src";                        expect "home path /home/<name> fails" 1 "$t/m"
leak "mail me at someone${A}gmail.com";              expect "email address fails" 1 "$t/m"
leak "contact: dev${A}example.com";                  expect "example.com address is allowed" 0 "$t/m"
leak "token ghp_$(printf 'a%.0s' $(seq 1 36))";   expect "GitHub token shape fails" 1 "$t/m"
leak "key sk-$(printf 'b%.0s' $(seq 1 30))";      expect "sk- key shape fails" 1 "$t/m"
leak "aws AKIA$(printf 'C%.0s' $(seq 1 16))";     expect "AWS key id shape fails" 1 "$t/m"
leak "${DASH}BEGIN RSA PRIV""ATE KEY${DASH}";           expect "private key header fails" 1 "$t/m"
leak "use ~/.agents/harness and \$HOME/x";        expect "tilde and \$HOME paths are fine" 0 "$t/m"

# --- library total budget: tight, no context bloat
mut; for n in a b c d e f g h; do { printf '# big%s\nRecord outcomes with bin/ledger.\n## When to Use\n## Steps\n## Red Flags\n## Verification\n' "$n"; for i in $(seq 1 70); do printf 'padding line %s %s xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$n" "$i"; done; } > "$t/m/library/big$n.md"; done
expect "library over the total byte cap fails" 1 "$t/m"

# --- library/deep: on-demand long tail, never auto-loaded
deepf() { mkdir -p "$t/m/library/deep"; { printf '# %s\n## When to Load\n- trigger\n## Pattern\n1. step\n## Red Flags\n- flag\n' "$1"; [ -n "${2:-}" ] && seq 1 "$2" | sed 's/^/line /'; } > "$t/m/library/deep/$1.md"; }
mut; deepf ok-one
expect "a valid deep file passes" 0 "$t/m"
mut; deepf too-long 45
expect "deep file over 45 lines fails" 1 "$t/m"
mut; mkdir -p "$t/m/library/deep"; printf '# x\n## Pattern\n1. a\n## Red Flags\n- b\n' > "$t/m/library/deep/nosec.md"
expect "deep file missing When to Load fails" 1 "$t/m"
mut; for n in $(seq 1 40); do deepf "big$n" 20; { printf '# big\n## When to Load\n- t\n## Pattern\n'; for i in $(seq 1 24); do printf 'padding %s %s xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' "$n" "$i"; done; printf '## Red Flags\n- f\n'; } > "$t/m/library/deep/big$n.md"; done
expect "deep folder over its byte cap fails" 1 "$t/m"
mut; deepf ok-two; echo "see library/deep/ok-two" >> "$t/m/skills/dev-debug/SKILL.md"
expect "reference to an existing deep file resolves" 0 "$t/m"
mut; echo "see library/deep/missing-one" >> "$t/m/skills/dev-debug/SKILL.md"
expect "reference to a missing deep file fails" 1 "$t/m"

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
