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

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
