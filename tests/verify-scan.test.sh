#!/usr/bin/env bash
# Fixture tests for bin/verify-scan: each finding kind has a bad and a good fixture, plus a mutation check.
# Fixtures are scratch git repos built here; their file bodies live in tests/fixtures/verify/*.txt.
# Usage: tests/verify-scan.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); scan="$here/bin/verify-scan"; fx="$here/tests/fixtures/verify"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

fresh() { # scratch repo on main with two test files and the gate files, committed as the base
  rm -rf "$R"; mkdir -p "$R/tests/fixtures/verify" "$R/bin"; cd "$R" || exit 2
  git init -q -b main . && git config user.email t@t && git config user.name t
  cp "$fx/base-a.txt" tests/a.test.sh; cp "$fx/base-b.txt" tests/b.test.sh
  printf 'gate v1\n' > bin/verify; printf 'gate v1\n' > bin/verify-scan; printf 'suite_file_s=9\n' > bin/verify.budget
  printf 'gate v1\n' > tests/verify.test.sh; printf 'data\n' > tests/fixtures/verify/x.txt
  printf 'echo plain\n# done gate: verify-gate row\n' > bin/ledger; printf 'echo other\n' > bin/other
  git add -A && git commit -qm base
}
scanned() { out=$("$scan" "${1:-main}" 2>&1); rc=$?; }
only() { # kind: exactly one finding line and it starts with kind
  [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ] && printf '%s\n' "$out" | grep -q "^$1 "
}
clean() { [ "$rc" -eq 0 ] && [ -z "$out" ]; }


sec_weakened() {
  # --- weakened
  fresh; cp "$fx/bad-weakened.txt" tests/a.test.sh; scanned
  ok "bad: removed assertion is weakened" 'only weakened'
  fresh; cp "$fx/good-reworded.txt" tests/a.test.sh; scanned
  ok "good: reworded assertion kept passes" 'clean'
  fresh; cp "$fx/good-added.txt" tests/a.test.sh; scanned
  ok "good: added assertion passes" 'clean'
  fresh; cp "$fx/bad-weakened.txt" tests/a.test.sh; cp "$fx/good-moved-b.txt" tests/b.test.sh; scanned
  ok "good: assertion moved to another file passes" 'clean'
  fresh; cp "$fx/good-newfile.txt" tests/c.test.sh; scanned
  ok "good: new untracked test file passes" 'clean'
  fresh; git rm -q tests/a.test.sh; scanned
  ok "bad: deleted test file is weakened" 'only weakened'
  fresh; git mv tests/a.test.sh tests/a2.test.sh; scanned
  ok "good: renamed test file passes" 'clean'
  fresh; git mv tests/a.test.sh tests/a2.test.sh; cp "$fx/bad-weakened.txt" tests/a2.test.sh; scanned
  ok "bad: renamed and weakened is weakened" 'only weakened'
  fresh; git checkout -qb feat; cp "$fx/bad-weakened.txt" tests/a.test.sh; git commit -qam weaken; scanned
  ok "bad: committed weakening is found against base" 'only weakened'
}

sec_escape() {
  # --- test-escape
  fresh; cp "$fx/bad-escape-true.txt" tests/a.test.sh; scanned
  ok "bad: added or-true is test-escape" 'only test-escape'
  fresh; cp "$fx/bad-escape-exit.txt" tests/a.test.sh; scanned
  ok "bad: added early exit is test-escape" 'only test-escape'
  fresh; cp "$fx/bad-escape-skip.txt" tests/a.test.sh; scanned
  ok "bad: added skipping marker is test-escape" 'only test-escape'
  fresh; cp "$fx/bad-escape-true.txt" tests/c.test.sh; scanned
  ok "bad: escape in an untracked new test is found" 'only test-escape'
  fresh; cp "$fx/good-comment.txt" tests/a.test.sh; scanned
  ok "good: comment naming an escape passes" 'clean'
  # the assertion name is text, not code: only the part after it can carry an escape
  fresh; cp "$fx/bad-escape-body.txt" tests/a.test.sh; scanned
  ok "bad: an escape after the assertion name is test-escape" 'only test-escape'
  fresh; cp "$fx/bad-escape-body-exit.txt" tests/a.test.sh; scanned
  ok "bad: exit 0 after the assertion name is test-escape" 'only test-escape'
  fresh; cp "$fx/good-escape-name.txt" tests/a.test.sh; scanned
  ok "good: escape words only in the assertion name pass" 'clean'
  # an existing escape that only moves with its line is not a new escape
  fresh; cp "$fx/base-escape.txt" tests/a.test.sh; git add -A; git commit -qm esc
  cp "$fx/good-edited-escape.txt" tests/a.test.sh; scanned
  ok "good: editing a line that already held an escape passes" 'clean'
  fresh; cp "$fx/base-escape.txt" tests/a.test.sh; git add -A; git commit -qm esc
  line=$(sed -n '3p' tests/a.test.sh); printf '%s\n' "$line" >> tests/a.test.sh; scanned
  ok "good: a verbatim copy of a base line is a move, not an escape" 'clean'
  fresh; cp "$fx/base-escape.txt" tests/a.test.sh; git add -A; git commit -qm esc
  printf 'exit 0\n' >> tests/a.test.sh; scanned
  ok "bad: a different escape added beside an existing one is flagged" 'only test-escape'
  # a removed line's name must not hide a new escape: the same exit-0 word moved from name to code
  fresh; cp "$fx/base-name-escape.txt" tests/a.test.sh; git add -A; git commit -qm esc
  cp "$fx/bad-escape-after-name.txt" tests/a.test.sh; scanned
  ok "bad: an escape added beside a name that says exit 0 is flagged" 'only test-escape'
}

sec_gate() {
  # --- gate-edit
  for g in bin/verify bin/verify-scan bin/verify.budget bin/ledger bin/run bin/defaults \
           tests/run-all.sh tests/verify.test.sh tests/fixtures/verify/x.txt; do
    fresh; printf 'edited\n' >> "$g"; scanned
    ok "bad: edit of $g is gate-edit" 'only gate-edit && printf "%s\n" "$out" | grep -qF "gate-edit $g needs user approval"'
  done
  fresh; printf 'new\n' > tests/fixtures/verify/new.txt; scanned
  ok "bad: new file under fixtures/verify is gate-edit" 'only gate-edit'
  fresh; printf 'if verify-gate fails; then exit 4; fi\n' >> bin/ledger; scanned
  ok "bad: edit of the done gate in bin/ledger is gate-edit" 'only gate-edit && printf "%s\n" "$out" | grep -qF "gate-edit bin/ledger"'
  # the whole file is guarded: a line with none of the gate words still edits the done gate
  fresh; printf 'echo more\n' >> bin/ledger; scanned
  ok "bad: a bin/ledger edit with no gate word is gate-edit" 'only gate-edit && printf "%s\n" "$out" | grep -qF "gate-edit bin/ledger"'
  fresh; printf 'echo more\n' >> bin/other; scanned
  ok "good: an unrelated bin file passes" 'clean'
}

sec_clean() {
  # --- clean and could-not-run
  fresh; scanned
  ok "good: no change is clean" 'clean'
  fresh; out=$("$scan" 2>&1); rc=$?
  ok "default base: HEAD change against main merge-base works" '[ $rc -eq 0 ]'
  fresh; scanned nosuchref
  ok "unknown base exits 2" '[ $rc -eq 2 ]'
  cd "$t" && mkdir -p nogit && cd nogit && out=$("$scan" 2>&1); rc=$?
  ok "outside a git repo exits 2" '[ $rc -eq 2 ]'
}

sec_mutation() {
  # --- mutation: neuter each finding kind in a scratch copy, its bad fixture must go clean
  mutant() { # kind
    sed "s/^scan_$1\$/:/" "$scan" > "$t/mut"; chmod +x "$t/mut"; grep -qx ':' "$t/mut"
  }
  fresh; mutant weakened; mrc=$?; cp "$fx/bad-weakened.txt" tests/a.test.sh; out=$("$t/mut" main 2>&1); rc=$?
  ok "mutation: weakened off lets the weakened fixture through" '[ $mrc -eq 0 ] && [ $rc -eq 0 ]'
  fresh; mutant escape; mrc=$?; cp "$fx/bad-escape-true.txt" tests/a.test.sh; out=$("$t/mut" main 2>&1); rc=$?
  ok "mutation: escape off lets the test-escape fixture through" '[ $mrc -eq 0 ] && [ $rc -eq 0 ]'
  fresh; mutant gate; mrc=$?; printf 'edited\n' >> bin/verify; out=$("$t/mut" main 2>&1); rc=$?
  ok "mutation: gate off lets the gate-edit fixture through" '[ $mrc -eq 0 ] && [ $rc -eq 0 ]'
  # mutate only the name-stripping branch: body() keeps the whole line instead of the part after the name
  sed 's/return r }$/return s }/' "$scan" > "$t/mut2"; chmod +x "$t/mut2"; grep -q 'return s }' "$t/mut2"; mrc=$?
  fresh; cp "$fx/good-escape-name.txt" tests/a.test.sh; out=$("$t/mut2" main 2>&1); rc=$?
  ok "mutation: name stripping off flags the good name fixture" '[ $mrc -eq 0 ] && [ $rc -eq 1 ] && printf "%s\n" "$out" | grep -q "^test-escape "'
}


# Each section builds its own scratch repos, so the five run side by side and their logs merge in order.
section() { # name fn
  ( p=0; f=0
    ok() { if eval "$2"; then p=$((p+1)); echo "ok   $1"; else f=$((f+1)); echo "FAIL $1   [$2]"; fi; }
    export R="$t/r-$1"; eval "$2"
    echo "$p $f" > "$t/$1.cnt" ) > "$t/$1.log" 2>&1 &
}
for s in weakened escape gate clean mutation; do section "$s" "sec_$s"; done
wait
for s in weakened escape gate clean mutation; do
  cat "$t/$s.log"; if read -r p f < "$t/$s.cnt" 2>/dev/null; then pass=$((pass+p)); fail=$((fail+f)); else fail=$((fail+1)); echo "FAIL section $s crashed"; fi
done
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
