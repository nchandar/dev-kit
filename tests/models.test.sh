#!/usr/bin/env bash
# Content checks for the tracked formal-verification models in models/.
# No java: the model check lives in each models/<name>/run.sh and the maintain skill.
# This must NOT fail because covered code changed after the sync commit; that is
# bin/model-drift's report (and CI runs it informationally), not a build break.
# Usage: tests/models.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); cd "$here" || exit 2
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }

[ -d models ] || { echo "FAIL models/ is missing"; exit 1; }
ok "models/ has at least one tracked model" '[ -n "$(ls -d models/*/ 2>/dev/null)" ]'

for d in models/*/; do
  d=${d%/}; n=${d#models/}; rec=$d/coverage.env
  ok "$n: has coverage.env"                          "[ -f \"$rec\" ]"
  ok "$n: has README.md"                             "[ -f \"$d/README.md\" ]"
  ok "$n: has a run.sh"                              "[ -x \"$d/run.sh\" ]"
  ok "$n: has a replay.sh"                           "[ -x \"$d/replay.sh\" ]"
  ok "$n: has a .tla and a .cfg"                     "ls \"$d\"/*.tla >/dev/null 2>&1 && ls \"$d\"/*.cfg >/dev/null 2>&1"
  [ -f "$rec" ] || continue
  sync=$(sed -n 's/^sync=//p' "$rec" | head -1)
  files=$(sed -n 's/^files=//p' "$rec" | head -1)
  cmd=$(sed -n 's/^cmd=//p' "$rec" | head -1)
  ok "$n: sync= is a full 40-char sha"               "printf '%s' '$sync' | grep -Eq '^[0-9a-f]{40}\$'"
  ok "$n: sync commit exists in git history"         "[ -n '$sync' ] && git cat-file -e '$sync^{commit}' 2>/dev/null"
  ok "$n: files= is present"                         "[ -n '$files' ]"
  ok "$n: cmd= is present"                           "[ -n '$cmd' ]"
  ok "$n: README names the TLC command"              "grep -q 'tlc2.TLC' \"$d/README.md\""
  ok "$n: README states an expected verdict line"    "grep -q 'No error has been found' \"$d/README.md\""
  ok "$n: README states the timing exclusions"       "grep -qi 'timing exclusions' \"$d/README.md\""
  ok "$n: README says how to run the replay"         "grep -q 'bash replay.sh' \"$d/README.md\""
  for f in $files; do
    ok "$n: covered path exists: $f"                 "[ -e \"$f\" ]"
  done
  for c in $(grep -oE '[A-Za-z0-9_.-]+\.cfg' "$d/README.md" 2>/dev/null | sort -u); do
    ok "$n: README cfg exists: $c"                   "[ -f \"$d/$c\" ]"
  done
done

ok "no tracked states/ or *.log under models/"       '! git ls-files models | grep -Eq "(^|/)states/|\.log$"'
ok "no tracked replay, scratch or chart output"      '! git ls-files models | grep -Eq "(^|/)(replay-run|scratch)/|/chart-[^/]*/"'
ok "no absolute /Users path in tracked model files"  '! git grep -q -E "/Users/" -- models/'
for r in models/*/replay.sh; do
  ok "$r: HOME is a scratch dir, never the real one" 'grep -Eq "^[[:space:]]*(export )?HOME=" "'"$r"'"'
done
ok "no email or token-shaped string in tracked model files" '! git grep -q -E "[A-Za-z0-9._-]+@[A-Za-z0-9-]+[.][a-z]{2,}|ghp_[A-Za-z0-9]{10}|AKIA[A-Z0-9]{8}" -- models/ ":!models/*/*.cfg" '
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
