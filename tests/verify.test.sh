#!/usr/bin/env bash
# Tests for bin/verify (tiered gate) in scratch git repos with fake suites. Usage: tests/verify.test.sh
set -u
unset DEVKIT_DEPTH  # a worker running this suite must still be able to start fixture tasks
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
here=$(cd "$(dirname "$0")/.." && pwd); verify="$here/bin/verify"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
unset DEVKIT_DIR
export VERIFY_BUDGET="$root/budget"; printf 'suite_file_s=100\nsuite_total_s=200\n' > "$VERIFY_BUDGET"
export VERIFY_TICK=0.02 # watchdog poll resolution: bounds unchanged, the idle wait after an instant run shrinks

# fresh scratch repo on branch main with fake gate tools; prints nothing, cds into it
mkrepo() { local d; d=$(mktemp -d "$root/r.XXXXXX"); cd "$d" || exit 2
  git init -q -b main . && git config user.email t@t && git config user.name t
  mkdir -p bin tests docs skills/dev-x
  printf '#!/usr/bin/env bash\necho lint-ok\n' > bin/lint-budget
  printf '#!/usr/bin/env bash\necho "x   1 passed, 0 failed"\n' > tests/pitfalls.test.sh
  printf '#!/usr/bin/env bash\necho "alpha.test.sh   3 passed, 0 failed   1s"\necho "beta.test.sh   2 passed, 0 failed   2s"\n' > tests/run-all.sh
  chmod +x bin/lint-budget tests/*.sh; echo base > README.md; echo s > skills/dev-x/SKILL.md; echo d > docs/a.md
  git add -A && git commit -qm base
  export DEVKIT_TASK=$("$ledger" start vt x); TD=".devkit/tasks/$DEVKIT_TASK"; }
row() { awk -F'\t' '$2=="verify-gate"{l=$0} END{print l}' "$TD/ledger.tsv"; }
field() { row | cut -f"$1"; }
setrun() { printf '#!/usr/bin/env bash\n%s\n' "$1" > tests/run-all.sh; chmod +x tests/run-all.sh; git add -A; git commit -qm fake; restart; }
restart() { DEVKIT_TASK=$("$ledger" start vt x); export DEVKIT_TASK; TD=".devkit/tasks/$DEVKIT_TASK"; }
legacy() { awk -F'\t' -v OFS='\t' '$2=="start"{$5=""} {print}' "$TD/ledger.tsv" > "$TD/legacy.tsv" && mv "$TD/legacy.tsv" "$TD/ledger.tsv"; }

mkrepo
a=$("$verify" tree); b=$("$verify" tree)
ok "tree id is a 40-hex sha"                 'echo "$a" | grep -qE "^[0-9a-f]{40}$"'
ok "tree id is stable across runs"           '[ "$a" = "$b" ]'
"$ledger" note x y >/dev/null; echo more >> "$TD/state.md"; c=$("$verify" tree)
ok "ledger and state writes do not move it"  '[ "$a" = "$c" ]'
echo e >> README.md; d=$("$verify" tree)
ok "a tracked edit changes it"               '[ "$a" != "$d" ]'
git checkout -q README.md; echo n > newfile; e=$("$verify" tree)
ok "an untracked file changes it"            '[ "$a" != "$e" ]'
echo ignored > .gitignore; echo n2 > ignored; f1=$("$verify" tree); echo n3 > ignored; f2=$("$verify" tree)
ok "gitignored files do not count"           '[ "$f1" = "$f2" ]'
ok "the real index is untouched"             '[ -z "$(git diff --cached --name-only)" ]'

mkrepo; setrun 'echo ran >> "$VT_MARK"; echo "a.test.sh   1 passed, 0 failed   1s"'
export VT_MARK="$root/mark"; : > "$VT_MARK"
out=$("$verify"); rc=$?
ok "nodiff: exit 0, runs nothing"            '[ $rc -eq 0 ] && [ ! -s "$VT_MARK" ]'
ok "nodiff row: tier, pass"                  '[ "$(field 3)" = nodiff ] && [ "$(field 6)" = pass ]'
ok "row reason carries tree id and seconds"  'field 4 | grep -qE "^tree [0-9a-f]{40} [0-9]+s"'
ok "phase is verify-gate" '[ "$(field 2)" = verify-gate ]'

echo more >> docs/a.md; : > "$VT_MARK"
out=$("$verify"); rc=$?
ok "docs-only: light tier, pass"             '[ $rc -eq 0 ] && [ "$(field 3)" = light ] && [ "$(field 6)" = pass ]'
ok "docs-only: full suite not run"           '[ ! -s "$VT_MARK" ]'
echo more >> README.md; "$verify" >/dev/null; ok "README.md alone is light" '[ "$(field 3)" = light ]'
git checkout -q .; echo '<p>r</p>' > docs/report.html; "$verify" >/dev/null
ok "a docs report .html is light"            '[ "$(field 3)" = light ]'
mkrepo; printf '#!/usr/bin/env bash\necho bad; exit 1\n' > bin/lint-budget; git add -A; git commit -qm badlint; restart; echo more >> docs/a.md
"$verify" >/dev/null; rc=$?
ok "light tier: failing lint-budget is exit 1, fail" '[ $rc -eq 1 ] && [ "$(field 3)" = light ] && [ "$(field 6)" = fail ]'
mkrepo; printf '#!/usr/bin/env bash\nherdr x\n' > bin/lint-budget; mkdir "$root/trip"; printf '#!/usr/bin/env bash\nexit 0\n' > "$root/trip/herdr"; chmod +x "$root/trip/herdr"
git add -A; git commit -qm herdr; restart; echo more >> docs/a.md; PATH="$root/trip:$PATH" "$verify" >/dev/null; rc=$?
ok "light tier: a herdr call trips the tripwire" '[ $rc -eq 1 ] && field 4 | grep -q tripwire'

mkrepo; setrun 'echo ran >> "$VT_MARK"; echo "a.test.sh   1 passed, 0 failed   1s"'; : > "$VT_MARK"
echo more >> skills/dev-x/SKILL.md
out=$("$verify"); rc=$?
ok "A7: SKILL.md edit runs the full suite"   '[ $rc -eq 0 ] && [ "$(field 3)" = full ] && [ -s "$VT_MARK" ]'
ok "full pass row: result pass, evidence is a non-empty log" '[ "$(field 6)" = pass ] && [ -s "$(field 5)" ]'
ok "full pass row: reason names the start base" 'field 4 | grep -q "; base start"'
ok "--task ID selects the ledger"            'out=$(env -u DEVKIT_TASK "$verify" --task "$DEVKIT_TASK"); [ $? -eq 0 ]'

mkrepo; echo more >> AGENTS.md; "$verify" >/dev/null
ok "AGENTS.md counts as code: full"          '[ "$(field 3)" = full ]'
git checkout -q . ; rm -f AGENTS.md; mkdir -p library; echo l > library/x.md; "$verify" >/dev/null
ok "library/** counts as code: full"         '[ "$(field 3)" = full ]'

# --- s5b: the base copy of the scanner runs, so a neutered working copy cannot pass itself
mkrepo
cp "$here/bin/verify-scan" bin/verify-scan; chmod +x bin/verify-scan
printf '#!/usr/bin/env bash\nok "a1" true\nok "a2" true\nok "a3" true\n' > tests/a.test.sh; chmod +x tests/a.test.sh
git add -A && git commit -qm scanner-base
export DEVKIT_TASK=$("$ledger" start vt2 x); TD=".devkit/tasks/$DEVKIT_TASK" # base must hold the scanner, so start the task here
printf '#!/usr/bin/env bash\nexit 0\n' > bin/verify-scan # neuter the working copy
printf '#!/usr/bin/env bash\nok "a1" true\nok "a2" true\n' > tests/a.test.sh
echo more >> skills/dev-x/SKILL.md
"$verify" >/dev/null 2>&1; rc=$?
ok "base scanner: a neutered working scanner cannot hide findings" '[ $rc -eq 1 ] && [ "$(field 6)" = fail ] && field 4 | grep -q "scan found problems"'
ok "base scanner: reports the gate edit and the weakened test" 'grep -q "gate-edit bin/verify-scan" "$(field 5)" && grep -q "weakened tests/a.test.sh" "$(field 5)"'

mkrepo; setrun 'echo "a.test.sh   1 passed, 0 failed   1s"; echo "b.test.sh   0 passed, 1 failed   1s"; echo "FAIL b"; exit 1'
echo more >> skills/dev-x/SKILL.md
out=$("$verify"); rc=$?
ok "failing suite: exit 1, result fail"      '[ $rc -eq 1 ] && [ "$(field 6)" = fail ]'
ok "hard fail reason is not flaky or slow"   '! field 4 | grep -qE "flaky|slow"'

mkrepo; setrun 'echo "flap.test.sh   1 passed, 0 failed   1s"; tests/flap.test.sh >/dev/null || { echo "flap.test.sh   0 passed, 1 failed   1s"; exit 1; }'
printf '#!/usr/bin/env bash\nf="$VT_MARK.n"; n=$(cat "$f" 2>/dev/null || echo 0); echo $((n+1)) > "$f"\n[ "$n" -ne 0 ]\n' > tests/flap.test.sh
chmod +x tests/flap.test.sh; git add -A; git commit -qm flap
rm -f "$VT_MARK.n"; echo more >> skills/dev-x/SKILL.md
out=$("$verify"); rc=$?
ok "flaky: fails even though the rerun passed" '[ $rc -eq 1 ] && [ "$(field 6)" = fail ]'
ok "flaky reason names the suite"            'field 4 | grep -q "flaky: flap.test.sh"'
ok "flaky: the suite ran exactly twice"      '[ "$(cat "$VT_MARK.n")" -eq 2 ]'

mkrepo; setrun 'echo "big.test.sh   1 passed, 0 failed   150s"'; echo more >> skills/dev-x/SKILL.md
out=$("$verify"); rc=$?
ok "slow file: exit 1, reason slow"          '[ $rc -eq 1 ] && field 4 | grep -q "slow: big.test.sh 150s > 100s"'
setrun 'echo "a.test.sh   1 passed, 0 failed   90s"; echo "b.test.sh   1 passed, 0 failed   90s"; echo "c.test.sh   1 passed, 0 failed   90s"'
echo more2 >> skills/dev-x/SKILL.md; out=$("$verify"); rc=$?
ok "slow total: exit 1, reason slow"         '[ $rc -eq 1 ] && field 4 | grep -q "slow: total 270s > 200s"'
VERIFY_BUDGET="$root/missing" "$verify" >/dev/null 2>"$root/err"; rc=$?
ok "missing budget file: skipped with a note, not an error" '[ $rc -eq 0 ] && grep -qi budget "$root/err"'

mkrepo; setrun 'echo "garbage"'; echo more >> skills/dev-x/SKILL.md
"$verify" >/dev/null 2>&1; rc=$?
ok "unparsable run-all output: exit 2, not-run" '[ $rc -eq 2 ] && [ "$(field 6)" = not-run ]'
setrun 'kill -9 $$'; echo more2 >> skills/dev-x/SKILL.md
"$verify" >/dev/null 2>&1; rc=$?
ok "crashed suite: exit 2, not-run"          '[ $rc -eq 2 ] && [ "$(field 6)" = not-run ]'
rm tests/run-all.sh; git add -A; git commit -qm rm; echo more3 >> skills/dev-x/SKILL.md
"$verify" >/dev/null 2>&1; rc=$?
ok "run-all missing: exit 2, not-run"        '[ $rc -eq 2 ] && [ "$(field 6)" = not-run ]'
mkrepo; chmod -x bin/lint-budget; git add -A; git commit -qm noexec; restart; echo more >> docs/a.md
"$verify" >/dev/null 2>&1; rc=$?
ok "light tier tool missing: exit 2, not-run" '[ $rc -eq 2 ] && [ "$(field 6)" = not-run ]'
mkrepo; git checkout -q -b feat; git branch -D main -q; legacy; git update-ref -d refs/heads/main 2>/dev/null
"$verify" >/dev/null 2>&1; rc=$?
ok "no main or origin/main and no start commit: exit 2" '[ $rc -eq 2 ]'

mkrepo; echo more >> skills/dev-x/SKILL.md; "$ledger" verify pass "hand written" >/dev/null
ok "hand-written ledger verify row is not a gate row" '[ -z "$(row)" ]'
mkrepo; ( cd "$root" && mkdir -p nogit && cd nogit && "$verify" >/dev/null 2>&1 ); rc=$?
ok "outside a git repo: exit 2"              '[ $rc -eq 2 ]'

# --- s1b: the watchdog bounds the gate run
mkrepo; export VERIFY_TIMEOUT=1
setrun 'echo "slow.test.sh   1 passed, 0 failed   1s"; sleep 3917' # sleep-ok: the fake run must outlive the 1s limit so the watchdog fires
echo more >> skills/dev-x/SKILL.md; : > "$VT_MARK"; out=$("$verify" >/dev/null 2>&1); rc=$?
ok "hung suite: exit 2, row not-run"         '[ $rc -eq 2 ] && [ "$(field 6)" = not-run ]'
ok "row reason names the timeout"            'field 4 | grep -q "timeout after 1s"'
# a generic "sleep 30" also matches other sessions' processes, so match this run's own 3917 marker only
ok "nothing is left behind"                  '[ -z "$(pgrep -f "sleep 3917" 2>/dev/null)" ]'
unset VERIFY_TIMEOUT # back to the budget-derived default for the next runs

# --- s1b: verify base, the tree the gate diffs against; s5a: the task's start commit wins
mkrepo; a=$("$verify" tree); b=$("$verify" base); sc=$("$verify" base-commit)
ok "verify base equals the tree in a no-diff repo" '[ "$a" = "$b" ]'
ok "verify base-commit is the task's start commit" '[ "$sc" = "$(git rev-parse HEAD)" ] && [ "$b" = "$(git rev-parse "$sc^{tree}")" ]'
ok "--task selects the base" '[ "$("$verify" --task "$DEVKIT_TASK" base-commit)" = "$sc" ]'
SC=sess-base; CLAUDE_CODE_SESSION_ID=$SC "$ledger" start vsc x >/dev/null
ok "base-commit resolves the session pointer" '[ "$(env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SC "$verify" base-commit)" = "$sc" ]'
echo e >> README.md
ok "verify base does not move after an edit" '[ "$("$verify" base)" = "$b" ] && [ "$("$verify" tree)" != "$b" ]'
echo more >> skills/dev-x/SKILL.md; git add -A; git commit -qm later
ok "a commit after start leaves the base at the start tree" '[ "$("$verify" base)" = "$b" ] && [ "$("$verify" tree)" != "$b" ]'
mkrepo; git checkout -q -b nobase; git branch -D main -q; legacy; git update-ref -d refs/remotes/origin/main 2>/dev/null
"$verify" base >/dev/null 2>"$root/eb"; rc=$?
ok "verify base without a base ref: exit 2"  '[ $rc -eq 2 ] && grep -qi base "$root/eb"'
mkrepo; git checkout -q -b master; git branch -D main -q; legacy; git update-ref -d refs/remotes/origin/main 2>/dev/null
ok "m4: a master-only repo, no start head, uses master" '[ "$("$verify" base-commit)" = "$(git rev-parse HEAD)" ] && [ "$("$verify" base-kind)" = merge-base ]'

# --- s5b: TERM and INT stop the run, record not-run and leave nothing behind
mkrepo; setrun 'echo "slow.test.sh   1 passed, 0 failed   1s"; echo started > "$VT_START"; sleep 3918' # sleep-ok: the fake run must outlive the TERM below
echo more >> skills/dev-x/SKILL.md; export VT_START="$root/int-term"; : > "$VT_START"; mkdir -p "$root/tmp-term"
TMPDIR="$root/tmp-term" "$verify" >/dev/null 2>"$root/term.err" & vpid=$!
n=0; while [ ! -s "$VT_START" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll for the fake run to start
kill -TERM "$vpid" 2>/dev/null; wait "$vpid"; rc=$?
ok "TERM: exit 143"                          '[ $rc -eq 143 ]'
ok "TERM: row not-run, reason interrupted"   '[ "$(field 6)" = not-run ] && field 4 | grep -q interrupted'
ok "TERM: no process of the run is left"     '[ -z "$(pgrep -f "sleep 3918" 2>/dev/null)" ]'
ok "TERM: the temp dir is removed"           '[ -z "$(ls -A "$root/tmp-term")" ]'
ok "m6: TERM leaves no bash 'Terminated' job message" '! grep -q "Terminated" "$root/term.err"'
pkill -KILL -f "sleep 3918" 2>/dev/null # teardown only: a failed run must not leak the fake hang

mkrepo; setrun 'echo "slow.test.sh   1 passed, 0 failed   1s"; echo started > "$VT_START"; sleep 3919' # sleep-ok: the fake run must outlive the INT below
echo more >> skills/dev-x/SKILL.md; export VT_START="$root/int-int"; : > "$VT_START"; mkdir -p "$root/tmp-int"
# launch through a resetting exec: bin/verify starts a run in the background of a non-interactive
# shell, where bash ignores INT on entry and a child cannot re-enable it, so the test must not depend
# on how this suite itself was started
TMPDIR="$root/tmp-int" perl -e '$SIG{INT}="DEFAULT"; exec @ARGV' -- "$verify" >/dev/null 2>&1 & vpid=$!
n=0; while [ ! -s "$VT_START" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll for the fake run to start
kill -INT "$vpid" 2>/dev/null
( sleep 10; kill -KILL "$vpid" 2>/dev/null ) 2>/dev/null & guard=$! # sleep-ok: bound the wait so a missed INT fails in seconds, not at the 400s watchdog
wait "$vpid" 2>/dev/null; rc=$?
kill "$guard" 2>/dev/null; wait "$guard" 2>/dev/null
ok "INT: exit 130"                           '[ $rc -eq 130 ]'
ok "INT: row not-run, reason interrupted"    '[ "$(field 6)" = not-run ] && field 4 | grep -q interrupted'
ok "INT: no process of the run is left"      '[ -z "$(pgrep -f "sleep 3919" 2>/dev/null)" ]'
ok "INT: the temp dir is removed"            '[ -z "$(ls -A "$root/tmp-int")" ]'
pkill -KILL -f "sleep 3919" 2>/dev/null # teardown only: a failed run must not leak the fake hang

# --- s5b: a tree edited during the run cannot pass
mkrepo; setrun 'echo "a.test.sh   1 passed, 0 failed   1s"; echo mid-run >> README.md'
echo more >> skills/dev-x/SKILL.md
"$verify" >/dev/null 2>&1; rc=$?
ok "an edit during the run: exit 2, not-run" '[ $rc -eq 2 ] && [ "$(field 6)" = not-run ]'
ok "an edit during the run: reason names the tree change" 'field 4 | grep -q "tree changed during the run"'

echo; echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
