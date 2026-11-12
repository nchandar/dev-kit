#!/usr/bin/env bash
# End-to-end gate test in a scratch repo: bin/verify -> bin/verify-scan -> ledger done.
# Each flow is a fixture; the mutation block neuters one gate and reruns its flow, which must fail.
# Usage: tests/verify-gate.test.sh
set -u
unset DEVKIT_DEPTH DEVKIT_TASK DEVKIT_DIR CLAUDE_CODE_SESSION_ID
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
HOME_BIN="$here/bin"; TOOLS="$HOME_BIN"
export VT_MARK="$root/mark"
export VERIFY_TICK=0.02 # watchdog poll resolution: bounds unchanged, each gate invocation stops waiting a full second

# scratch repo on main with copies of the gate tools; prints nothing, sets GT and TD, cds into it.
# RUNALL_BODY overrides the stub suite's output, so a flow can commit a runner it does not edit after start.
mkrepo() { local d t; d=$(mktemp -d "$root/r.XXXXXX") || return 2; cd "$d" || return 2
  git init -q -b main . && git config user.email t@t && git config user.name t || return 2
  mkdir -p bin tests docs skills/dev-x
  for t in verify verify-scan ledger run defaults; do cp "$TOOLS/$t" bin/ || return 2; done
  chmod +x bin/verify bin/verify-scan bin/ledger bin/run
  printf '#!/usr/bin/env bash\necho lint-ok\n' > bin/lint-budget
  printf '#!/usr/bin/env bash\necho "ok light"\n' > tests/pitfalls.test.sh
  printf '#!/usr/bin/env bash\necho ran >> "$VT_MARK"\n%s\n' "${RUNALL_BODY:-echo \"a.test.sh   3 passed, 0 failed   1s\"}" > tests/run-all.sh
  printf '#!/usr/bin/env bash\nok "a1" true\nok "a2" true\nok "a3" true\n' > tests/a.test.sh
  printf 'suite_file_s=100\nsuite_total_s=200\n' > bin/verify.budget
  echo base > README.md; echo s > skills/dev-x/SKILL.md; echo d > docs/a.md
  chmod +x bin/lint-budget tests/*.sh
  git add -A && git commit -qm base || return 2
  GT=$(bin/ledger start gate x) || return 2
  export DEVKIT_TASK=$GT; TD=".devkit/tasks/$GT"; }
row() { awk -F'\t' '$2=="verify-gate"{l=$0} END{print l}' "$TD/ledger.tsv"; }
legacy() { awk -F'\t' -v OFS='\t' '$2=="start"{$5=""} {print}' "$TD/ledger.tsv" > "$TD/l.tsv" && mv "$TD/l.tsv" "$TD/ledger.tsv"; }
field() { row | cut -f"$1"; }
grows() { awk -F'\t' '$2=="verify-gate"' "$TD/ledger.tsv" | wc -l | tr -d ' '; }
setrun() { printf '%s\n' '#!/usr/bin/env bash' "$1" > tests/run-all.sh; chmod +x tests/run-all.sh; }

# Each flow is self-contained (own scratch repo, own task), so they run in batches of 8 and
# their results merge in call order. Each gets its own VT_MARK: the run-all stub appends to it.
# 8 is a guess that keeps a 2-core box from thrashing on git forks; each flow is a few git calls, so it is not a tuned limit.
jobs="$root/jobs"; : > "$jobs"; batch=0
ok() { # name command: runs in the background, merged in call order by drain
  local d; d=$(mktemp -d "$root/b.XXXXXX")
  ( export VT_MARK="$d/mark"; cd "$root" || exit 2; eval "$2" >"$d/out" 2>"$d/err"; echo $? > "$d/rc" ) &
  printf '%s\t%s\t%s\t%s\n' "$!" "$1" "$d" "$2" >> "$jobs"
  batch=$((batch+1)); [ $batch -lt 8 ] || drain
}
drain() { # merge the batch in call order, same pass/fail bookkeeping a serial ok would do
  local pid name d cond rc
  while IFS=$'\t' read -r pid name d cond; do
    wait "$pid" 2>/dev/null; rc=$(cat "$d/rc" 2>/dev/null || echo 2)
    if [ "$rc" -eq 0 ]; then pass=$((pass+1)); echo "ok   $name"
    else fail=$((fail+1)); echo "FAIL $name   [$cond] (stderr: $d/err)"; fi
  done < "$jobs"
  : > "$jobs"; batch=0
}

# --- flows: each returns 0 when the gate behaved as specified
flow_no_row() { mkrepo || return 2; echo more >> skills/dev-x/SKILL.md; local n0 rc
  n0=$(wc -l < "$TD/ledger.tsv"); bin/ledger -t "$GT" done "no row" 2>"$root/no-row.err"; rc=$?
  [ $rc -eq 4 ] && [ "$(wc -l < "$TD/ledger.tsv")" = "$n0" ] && grep -q "no verify-gate row for tree" "$root/no-row.err" && grep -q -- "--waive" "$root/no-row.err"; }

flow_pass_close() { mkrepo || return 2; echo more >> skills/dev-x/SKILL.md; bin/verify >/dev/null 2>&1 || return 2
  [ "$(field 3)" = full ] && [ "$(field 6)" = pass ] || return 1
  bin/ledger -t "$GT" done "after a pass" >/dev/null 2>&1 && [ "$(tail -1 "$TD/ledger.tsv" | cut -f2)" = done ]; }

flow_edit_after_pass() { mkrepo || return 2; bin/verify >/dev/null 2>&1 || return 2
  echo more >> README.md; bin/ledger -t "$GT" done "edited" 2>"$root/after.err"; local rc=$?
  [ $rc -eq 4 ] && grep -q "another tree" "$root/after.err"; }

flow_removed_assertion() { mkrepo || return 2
  grep -v 'ok "a3" true' tests/a.test.sh > "$root/a.tmp" && cp "$root/a.tmp" tests/a.test.sh
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 1 ] && [ "$(field 6)" = fail ] && field 4 | grep -q "scan found problems" \
    && grep -q "weakened tests/a.test.sh has 2 ok assertions, base had 3" "$(field 5)"; }

flow_gate_edit() { mkrepo || return 2; echo '# touched' >> bin/verify.budget
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 1 ] && [ "$(field 6)" = fail ] && grep -q "gate-edit bin/verify.budget needs user approval" "$(field 5)"; }

# A1: the done gate and the suite runner are gate files too, even when the line names no gate word
flow_ledger_gate_edit() { mkrepo || return 2
  perl -i -pe 's/\[ "\$t" != "\$b" \]/[ "\$t" != "\$t" ]/' bin/ledger || return 2
  grep -q '\[ "\$t" != "\$t" \]' bin/ledger || return 2
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 1 ] && [ "$(field 6)" = fail ] && grep -q "gate-edit bin/ledger needs user approval" "$(field 5)"; }
flow_runner_gate_edit() { mkrepo || return 2; setrun 'echo "a.test.sh   1 passed, 0 failed   1s"'
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 1 ] && [ "$(field 6)" = fail ] && grep -q "gate-edit tests/run-all.sh needs user approval" "$(field 5)"; }

flow_waive() { mkrepo || return 2; echo more >> skills/dev-x/SKILL.md; local out rc
  out=$(bin/ledger -t "$GT" done --waive "verified by hand, the suite cannot run here" "w" 2>&1); rc=$?
  [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q "^waived: verified by hand, the suite cannot run here" \
    && [ "$(awk -F'\t' '$2=="waive"' "$TD/ledger.tsv" | wc -l | tr -d ' ')" -eq 1 ]; }

flow_not_run() { mkrepo || return 2; setrun 'echo garbage'
  bin/verify >/dev/null 2>&1; [ $? -eq 2 ] || return 1
  [ "$(field 6)" = not-run ] || return 1
  bin/ledger -t "$GT" done "not-run row" 2>"$root/not-run.err"; local rc=$?
  [ $rc -eq 4 ] && grep -q "not-run" "$root/not-run.err"; }

flow_flaky() { mkrepo || return 2
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > tests/flap.test.sh; chmod +x tests/flap.test.sh
  setrun 'echo "flap.test.sh   0 passed, 1 failed   1s"; exit 1'
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 1 ] && [ "$(field 6)" = fail ] && field 4 | grep -q "flaky: flap.test.sh"; }

# a slow suite: the stub is committed at start (a post-start runner edit is now a gate edit, which would mask it)
flow_slow() { RUNALL_BODY='echo "big.test.sh   1 passed, 0 failed   150s"' mkrepo || return 2
  echo more >> skills/dev-x/SKILL.md
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 1 ] && [ "$(field 6)" = fail ] && field 4 | grep -q "slow: big.test.sh 150s > 100s"; }

flow_docs_light() { mkrepo || return 2; echo more >> docs/a.md; : > "$VT_MARK"
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 0 ] && [ "$(field 3)" = light ] && [ ! -s "$VT_MARK" ]; }

flow_skills_full() { mkrepo || return 2; echo more >> skills/dev-x/SKILL.md; : > "$VT_MARK"
  bin/verify >/dev/null 2>&1; local rc=$?
  [ $rc -eq 0 ] && [ "$(field 3)" = full ] && [ -s "$VT_MARK" ]; }

flow_no_diff() { mkrepo || return 2; local err rc
  err=$(bin/ledger -t "$GT" done "clean tree" 2>&1 >/dev/null); rc=$?
  [ $rc -eq 0 ] && [ "$(grows)" -eq 0 ] && [ -z "$err" ]; }

# M1: the task started in a worktree must gate the worktree, not the main checkout
flow_worktree_gate() { mkrepo || return 2; local w wt err rc
  w=$(mktemp -d "$root/wt.XXXXXX") || return 2
  git worktree add -q "$w" -b wt-gate >/dev/null 2>&1 || return 2
  wt=$(cd "$w" && bin/ledger start wt x) || return 2
  echo '# w' >> "$w/README.md"
  err=$(cd "$w" && bin/ledger -t "$wt" done "worktree" 2>&1 >/dev/null); rc=$?
  [ $rc -eq 4 ] && printf '%s\n' "$err" | grep -q "no verify-gate row for tree"; }

# m3: a DEVKIT_DIR outside the repo must not skip the gate for the caller's repo
flow_devkit_outside_repo() { mkrepo || return 2; local x ext err rc
  x=$(mktemp -d "$root/dd.XXXXXX") || return 2
  ext=$(DEVKIT_DIR="$x/.devkit" bin/ledger start outside x) || return 2
  echo more >> README.md
  err=$(DEVKIT_DIR="$x/.devkit" bin/ledger -t "$ext" done "outside" 2>&1 >/dev/null); rc=$?
  [ $rc -eq 4 ] && printf '%s\n' "$err" | grep -q "no verify-gate row for tree"; }

# m2: a fallback to the merge-base is named at close, not silent
flow_old_no_head() { mkrepo || return 2; local out rc
  legacy
  git update-ref refs/remotes/origin/main HEAD
  out=$(bin/ledger -t "$GT" done "old task" 2>"$root/old.err"); rc=$?
  [ $rc -eq 0 ] && [ "$(grep -c . "$root/old.err")" -eq 1 ] && grep -q "merge-base" "$root/old.err" \
    && printf '%s\n' "$out" | grep -q "verified: nodiff .*(base: merge-base)"; }

flow_gc_start() { mkrepo || return 2; local w0 out rc
  echo wip > wip.txt; git add -A; git commit -qm wip
  w0=$(bin/ledger start gc x) || return 2
  git reset -q --hard HEAD~1
  git update-ref refs/remotes/origin/main HEAD
  git reflog expire --expire=now --all && git gc --prune=now -q
  out=$(bin/ledger -t "$w0" done "gc" 2>"$root/gc.err"); rc=$?
  [ $rc -eq 0 ] && [ "$(grep -c . "$root/gc.err")" -eq 1 ] && grep -q "merge-base" "$root/gc.err" \
    && printf '%s\n' "$out" | grep -q "verified: nodiff .*(base: merge-base)"; }

# --- end to end
ok "no verify row: done exits 4 and writes nothing" 'flow_no_row'
ok "bin/verify passes then done closes"             'flow_pass_close'
ok "an edit after the pass: done exits 4"           'flow_edit_after_pass'
ok "A1: a removed assertion makes verify exit 1"    'flow_removed_assertion'
ok "a gate-file edit is reported"                   'flow_gate_edit'
ok "A1: a bin/ledger edit with no gate word fails verify" 'flow_ledger_gate_edit'
ok "A1: a stubbed tests/run-all.sh fails verify"    'flow_runner_gate_edit'
ok "A8: --waive closes and prints the reason"       'flow_waive'
ok "A4: a not-run result never closes"              'flow_not_run'
ok "a flaky suite fails with flaky: <suite>"        'flow_flaky'
ok "a slow suite fails with slow:"                  'flow_slow'
ok "A7: docs-only runs the light tier only"         'flow_docs_light'
ok "A7: a SKILL.md edit runs the full suite"        'flow_skills_full'
ok "no diff closes with no row"                     'flow_no_diff'
ok "M1: a task started in a worktree gates the worktree" 'flow_worktree_gate'
ok "m3: a DEVKIT_DIR outside the repo still gates the caller's repo" 'flow_devkit_outside_repo'
ok "m2: no start head closes with one merge-base note" 'flow_old_no_head'
ok "m2: a gc'd start sha closes with the note, not silent nodiff" 'flow_gc_start'
drain

# --- mutation checks (A5): copy the tools, neuter one gate, the same flow must now fail
mutant_tool() { # name file perl-expr; prints a tools dir holding one mutation
  local d=$root/mut.$1 t
  rm -rf "$d"; mkdir -p "$d" || return 2
  for t in verify verify-scan ledger run defaults; do cp "$HOME_BIN/$t" "$d/$t" || return 2; done
  chmod +x "$d/verify" "$d/verify-scan" "$d/ledger" "$d/run"
  perl -i -pe "$3" "$d/$2" || return 2
  printf '%s' "$d"; }

D=$(mutant_tool flaky verify 's/if \[ \$rc -eq 0 \]; then flaky=/if false; then flaky=/')
MUT=$D
ok "mutation: no flaky rerun makes the flaky flow fail" '[ -n "$MUT" ] && grep -q "if false; then flaky=" "$MUT/verify" && export TOOLS="$MUT" && ! flow_flaky'

D=$(mutant_tool budget verify 's/\[ "\$secs" -le "\$file_max" \]/:/')
MUT=$D
ok "mutation: no budget check makes the slow flow fail" '[ -n "$MUT" ] && grep -q " : || finish fail 1 \"slow:" "$MUT/verify" && export TOOLS="$MUT" && ! flow_slow'

D=$(mutant_tool tier verify 's/tier=full; break;/:/')
MUT=$D
ok "mutation: no tier classification makes the full flow fail" '[ -n "$MUT" ] && ! grep -q "tier=full" "$MUT/verify" && export TOOLS="$MUT" && ! flow_skills_full'

D=$(mutant_tool scan verify 's/^if \[ -n "\$scanner" \]; then/if false; then/')
MUT=$D
ok "mutation: no scanner call makes the weakened flow fail" '[ -n "$MUT" ] && grep -q "if false; then" "$MUT/verify" && export TOOLS="$MUT" && ! flow_removed_assertion'

D=$(mutant_tool gate ledger 's/gate; grc=\$\?/grc=0/')
MUT=$D
ok "mutation: no done gate makes the no-row flow fail" '[ -n "$MUT" ] && grep -q "grc=0" "$MUT/ledger" && export TOOLS="$MUT" && ! flow_no_row'
drain

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
