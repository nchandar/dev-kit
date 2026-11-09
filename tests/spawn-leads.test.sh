#!/usr/bin/env bash
# Tests for running several leads at once: frozen spawn, lead worktree, caps, base check, owned paths. Fake agent, no tokens.
# Usage: tests/spawn-leads.test.sh
set -u
unset DEVKIT_DEPTH CLAUDE_CODE_SESSION_ID
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_LEADS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
export DEVKIT_MODE=headless DEVKIT_VIEW=off DEVKIT_VIEW_CLOSE_DELAY=0
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# a private copy of bin and skills: a test may edit the copy's spawn while it runs
mkdir "$t/kit"; cp -R "$here/bin" "$here/skills" "$t/kit/"
spawn="$t/kit/bin/spawn"; ledger="$t/kit/bin/ledger"
mkdir "$t/repo"; cd "$t/repo" && git init -q -b main && echo base > f.txt
printf '/fake\n/brief*.md\n' > .gitignore
git add -A && git -c user.name=t -c user.email=t@t commit -qm init
export DEVKIT_DIR="$t/repo/.devkit"
TA=$("$ledger" start leads x); TD="$DEVKIT_DIR/tasks/$TA"; export DEVKIT_TASK=$TA
cat > "$t/fake" <<'F'
#!/usr/bin/env bash
# $1=prompt $2=handoff path. FAKE_EDIT_SPAWN=<file> rewrites that spawn script while this worker runs.
if [ -n "${FAKE_EDIT_SPAWN:-}" ]; then
  # in place (same inode), as an editor that truncates and rewrites does; a rename would leave the running shell its old file
  { for i in $(seq 1 200); do echo 'echo EDITED-SPAWN-RAN >&2; exit 77'; done; cat "$FAKE_EDIT_SPAWN"; } > "$FAKE_EDIT_SPAWN.new" && cat "$FAKE_EDIT_SPAWN.new" > "$FAKE_EDIT_SPAWN"
fi
[ -z "${FAKE_HOLD:-}" ] || while [ -e "$FAKE_HOLD" ]; do sleep 0.1; done # sleep-ok: bounded by the test, which removes the hold file
printf 'ok cwd=%s\n\n## Checklist\n- [x] done\n' "$PWD" > "$2"
F
chmod +x "$t/fake"; export DEVKIT_FAKE="$t/fake"
echo "do the thing" > "$t/brief.md"

# --- 0. spawn runs from a frozen copy: editing the script mid-run must not crash it
# a private TMPDIR: other suites run at the same time and a copy of theirs, alive or stranded by a kill -9, must not count here
mkdir -p "$t/tmp"; export TMPDIR="$t/tmp"
nfroz() { ls "$TMPDIR"/dk-spawn.* 2>/dev/null | wc -l | tr -d " "; }
# an unfrozen spawn can loop or crash once its file moves under it, so the run gets a watchdog
FAKE_EDIT_SPAWN="$spawn" "$spawn" fz fake "$t/brief.md" >"$t/fz.out" 2>"$t/fz.err" & sp=$!
( sleep 30; kill -9 $sp 2>/dev/null ) >/dev/null 2>&1 & wd=$! # sleep-ok: watchdog, killed below
wait $sp; rc=$?; kill $wd 2>/dev/null; wait $wd 2>/dev/null
ok "editing bin/spawn while a worker runs does not crash the spawn" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/fz.status && ! grep -q EDITED-SPAWN-RAN "$t/fz.err"'
ok "the spawn really was edited during that run"                      'grep -q EDITED-SPAWN-RAN "$spawn"' # pitfall-ok: src-grep proves the fixture edit landed in the scratch copy
cp "$here/bin/spawn" "$spawn"
ok "no frozen copy is left behind"                                    '[ "$(nfroz)" -eq 0 ]'

# --- 1. --lead implies its own worktree and branch, and records the base commit
head=$(git rev-parse HEAD)
FAKE_ID=l1 "$spawn" --lead l1 fake "$t/brief.md"; rc=$?
ok "--lead alone runs in a worktree"                    '[ $rc -eq 0 ] && grep -q "cwd=.*/wt/l1" $TD/handoffs/l1.md'
ok "--lead creates its branch"                          'git rev-parse --verify -q devkit/$TA-l1 >/dev/null'
ok "--lead records run/<id>.base as the base commit"    '[ "$(cat $TD/run/l1.base)" = "$head" ]'
FAKE_ID=l1b "$spawn" l1b fake "$t/brief.md"
ok "a non-lead spawn without --worktree keeps the main checkout and writes no base" '! grep -q "/wt/l1b" $TD/handoffs/l1b.md && [ ! -e $TD/run/l1b.base ]'
git -C "$t/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m later
FAKE_ID=l1 "$spawn" --lead l1 fake "$t/brief.md"
ok "a respawn reuses the worktree and keeps its original base" '[ "$(cat $TD/run/l1.base)" = "$head" ]'
DEVKIT_DRYRUN=1 "$spawn" --lead l9 fake "$t/brief.md" >/dev/null
ok "dry-run creates no worktree and no base"            '[ ! -e $TD/wt/l9 ] && [ ! -e $TD/run/l9.base ]'

# --- 2. caps: DEVKIT_MAX_LEADS bounds live leads, repo-wide
hold1="$t/hold1"; : > "$hold1"
FAKE_ID=cap1 FAKE_HOLD="$hold1" DEVKIT_MAX_LEADS=1 "$spawn" --lead cap1 fake "$t/brief.md" & cp1=$!
for i in $(seq 1 50); do grep -q "^running" $TD/run/cap1.status 2>/dev/null && break; sleep 0.1; done # sleep-ok: bounded poll for the lead to start
DEVKIT_MAX_LEADS=1 "$spawn" --lead cap2 fake "$t/brief.md" 2>"$t/cap2.err"; rc=$?
ok "a --lead spawn past DEVKIT_MAX_LEADS exits non-zero"  '[ $rc -ne 0 ]'
ok "the refusal names the knob and the count"            'grep -q "DEVKIT_MAX_LEADS" "$t/cap2.err" && grep -q "1 live" "$t/cap2.err"'
ok "the refused lead made no worktree"                   '[ ! -e $TD/wt/cap2 ]'
DEVKIT_MAX_LEADS=1 FAKE_ID=nl "$spawn" nl fake "$t/brief.md"; rc=$?
ok "a non-lead spawn is not bound by the lead cap"       '[ $rc -eq 0 ]'
TB=$("$ledger" start other x)
DEVKIT_TASK=$TB DEVKIT_MAX_LEADS=1 "$spawn" --lead cap3 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "the lead count is repo-wide, across tasks"           '[ $rc -ne 0 ]'
DEVKIT_MAX_LEADS=2 FAKE_ID=cap4 "$spawn" --lead cap4 fake "$t/brief.md"; rc=$?
ok "a higher DEVKIT_MAX_LEADS admits another lead"       '[ $rc -eq 0 ]'
rm -f "$hold1"; wait $cp1
FAKE_ID=cap5 DEVKIT_MAX_LEADS=1 "$spawn" --lead cap5 fake "$t/brief.md"; rc=$?
ok "a finished lead frees its place"                     '[ $rc -eq 0 ]'
DEVKIT_MAX_LEADS=0 "$spawn" --lead cap6 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "DEVKIT_MAX_LEADS must be at least 1"                 '[ $rc -eq 2 ]'
DEVKIT_MAX_LEADS=x "$spawn" --lead cap6 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "DEVKIT_MAX_LEADS must be a whole number"             '[ $rc -eq 2 ]'
ok "defaults: a 10-core 64 GB machine gets 10 leads and 30 workers" '[ "$(env -i DEVKIT_CORES=10 DEVKIT_RAM_GB=64 "$BASH" -c ". \"$here/bin/defaults\"; echo \$DEVKIT_MAX_LEADS \$DEVKIT_MAX_WORKERS")" = "10 30" ]'

# --- 3. accept-time base check: a lead's branch must sit on the current tip of the default branch
FAKE_ID=ab1 "$spawn" --lead ab1 fake "$t/brief.md"; FAKE_ID=ab2 "$spawn" ab2 fake "$t/brief.md"
"$ledger" accept "ab1 accepted" "fresh base" >"$t/ab1.out" 2>&1; rc=$?
ok "a lead on the current default tip can be accepted"       '[ $rc -eq 0 ] && grep -q "ab1 accepted" $TD/ledger.tsv'
git -C "$t/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m moved1
git -C "$t/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m moved2
n=$(grep -c "ab1 accepted" $TD/ledger.tsv)
"$ledger" accept "ab1 accepted" "stale base" >"$t/ab1.out" 2>&1; rc=$?
ok "a lead behind the default branch is refused"             '[ $rc -ne 0 ] && [ "$(grep -c "ab1 accepted" $TD/ledger.tsv)" = "$n" ]'
ok "the message says how far behind and to rebase"           'grep -q "2 commit" "$t/ab1.out" && grep -q "rebase" "$t/ab1.out" && grep -q "ab1" "$t/ab1.out"'
"$ledger" accept "ab1 rejected" "stale base" >/dev/null 2>&1; rc=$?
ok "a rejection row is always allowed"                       '[ $rc -eq 0 ] && grep -q "ab1 rejected" $TD/ledger.tsv'
"$ledger" accept "ab2 accepted" "not a lead" >/dev/null 2>&1; rc=$?
ok "a non-lead worker is unchanged (no base check)"          '[ $rc -eq 0 ] && grep -q "ab2 accepted" $TD/ledger.tsv'
git -C "$t/repo/.devkit/tasks/$TA/wt/ab1" -c user.name=t -c user.email=t@t rebase -q main >/dev/null 2>&1
"$ledger" accept "ab1 accepted" "rebased" >/dev/null 2>&1; rc=$?
ok "after a rebase the lead is accepted"                     '[ $rc -eq 0 ] && [ "$(grep -c "ab1 accepted" $TD/ledger.tsv)" = "$((n+1))" ]'
"$ledger" accept ghost "no such worker" >/dev/null 2>&1; rc=$?
ok "an accept row of another shape is untouched"             '[ $rc -eq 0 ]'
# a remote's default branch counts as the tip once it exists
git init -q --bare "$t/remote.git"; git -C "$t/remote.git" symbolic-ref HEAD refs/heads/main; git -C "$t/repo" remote add origin "$t/remote.git"; git -C "$t/repo" push -q origin main 2>/dev/null
git -C "$t/repo" remote set-head origin main >/dev/null 2>&1
FAKE_ID=ab3 "$spawn" --lead ab3 fake "$t/brief.md"
git clone -q "$t/remote.git" "$t/other"; git -C "$t/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m remote-moved; git -C "$t/other" push -q origin HEAD:main 2>/dev/null
git -C "$t/repo" fetch -q origin
"$ledger" accept "ab3 accepted" "behind origin" >"$t/ab3.out" 2>&1; rc=$?
ok "behind the fetched remote default branch is refused"     '[ $rc -ne 0 ] && grep -q "1 commit" "$t/ab3.out"'

# --- 5. owned paths: a brief's column-0 `owns:` line is recorded; an overlap with a live lead warns, never refuses
hold2="$t/hold2"; : > "$hold2"
printf 'route: dev-feature\nowns: bin/spawn docs/\n' > "$t/own1.md"
FAKE_ID=ow1 FAKE_HOLD="$hold2" "$spawn" --lead ow1 fake "$t/own1.md" & op1=$!
for i in $(seq 1 50); do grep -q "^running" $TD/run/ow1.status 2>/dev/null && break; sleep 0.1; done # sleep-ok: bounded poll for the lead to start
ok "spawn records run/<id>.owns"                          '[ "$(cat $TD/run/ow1.owns)" = "bin/spawn docs" ]'
printf 'owns: bin/spawn/x.sh\n' > "$t/own2.md"
FAKE_ID=ow2 "$spawn" ow2 fake "$t/own2.md" 2>"$t/ow2.err"; rc=$?
ok "a path under a live lead's path warns, and the worker still runs" '[ $rc -eq 0 ] && grep -q "WARN" "$t/ow2.err" && grep -q "ow1" "$t/ow2.err" && grep -q "bin/spawn" "$t/ow2.err"' # pitfall-ok: src-grep matches captured stderr text, not spawn source
printf 'owns: bin\n' > "$t/own3.md"
FAKE_ID=ow3 "$spawn" ow3 fake "$t/own3.md" 2>"$t/ow3.err"
ok "a parent path overlaps too"                           'grep -q "WARN" "$t/ow3.err"'
printf 'owns: bin/spawnx tests\n' > "$t/own4.md"
FAKE_ID=ow4 "$spawn" ow4 fake "$t/own4.md" 2>"$t/ow4.err"
ok "a sibling that merely shares a name prefix does not overlap" '! grep -q "WARN" "$t/ow4.err"'
printf '  owns: bin/spawn\n```\nowns: bin/spawn\n```\n' > "$t/own5.md"
FAKE_ID=ow5 "$spawn" ow5 fake "$t/own5.md" 2>"$t/ow5.err"
ok "only a column-0 line outside a code fence counts"     '! grep -q "WARN" "$t/ow5.err" && [ ! -e $TD/run/ow5.owns ]'
ok "an overlap leaves a ledger row"                       'grep -q "ow2 owns-overlap" $TD/ledger.tsv'
rm -f "$hold2"; wait $op1
FAKE_ID=ow6 "$spawn" ow6 fake "$t/own2.md" 2>"$t/ow6.err"
ok "no warning once that lead has finished"               '! grep -q "WARN" "$t/ow6.err"'
DEVKIT_DRYRUN=1 "$spawn" ow7 fake "$t/own2.md" >/dev/null 2>&1
ok "dry-run records nothing"                              '[ ! -e $TD/run/ow7.owns ]'
FAKE_ID=ow2 "$spawn" ow2 fake "$t/brief.md"
ok "a respawn without owns drops the stale record"        '[ ! -e $TD/run/ow2.owns ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
