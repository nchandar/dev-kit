#!/usr/bin/env bash
# Tests for bin/spawn using a fake agent CLI (no tokens). Usage: tests/spawn.test.sh
set -u
unset DEVKIT_DEPTH  # these suites must pass when run from inside a worker too
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
# a worker also inherits its model, tunables and the push guard; none may change what this suite measures
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
export DEVKIT_MODE=headless  # this suite pins the headless path; tests/spawn-interactive.test.sh covers the tab path
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"; ledger="$here/bin/ledger"; verify="$here/bin/verify"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
# a verify-gate pass row for the current tree, the shape bin/verify writes (scratch repos cannot run the real gate)
gate_pass() { local d; d=$("$ledger" -t "$1" path) && mkdir -p "$d/runs" && echo gate > "$d/runs/gate.log" \
  && "$ledger" -t "$1" gate-row full "tree $("$verify" tree) 1s" "$d/runs/gate.log" pass; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && echo base > f.txt
# the harness's own artifacts must not reach the worker snapshot: bin/spawn hashes every
# untracked file twice per run, so a growing pile of .out/.err files dominates the suite
cat > .gitignore <<'I'
/tripwire/
/stubs/
/herdr-stub/
/oc-stub/
/cvbin/
/stat-stub/
/slowps/
/hm/
/remote.git/
/*.out
/*.err
/*.log
/brief*.md
/fake
/fake-env
I
git add -A && git -c user.name=t -c user.email=t@t commit -qm init
export DEVKIT_DIR="$t/.devkit"
export DEVKIT_VIEW=off DEVKIT_VIEW_CLOSE_DELAY=0
# tripwire: a herdr stub first on PATH for the whole suite, so a machine with
# real herdr installed still runs headless (spawn probes with `herdr tab list`).
# It appends its argv to a log and exits 1. The herdr-stub subshells below
# prepend their own stub, so they keep working (they shadow this one).
tripwire="$t/tripwire"; mkdir -p "$tripwire"
export HERDR_TRIPWIRE_LOG="$t/herdr-tripwire.log"; : > "$HERDR_TRIPWIRE_LOG"
cat > "$tripwire/herdr" <<'S'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_TRIPWIRE_LOG"
exit 1
S
chmod +x "$tripwire/herdr"
export PATH="$tripwire:$PATH"
TA=$("$ledger" start task-a x); TB=$("$ledger" start task-b y)
TD="$DEVKIT_DIR/tasks/$TA"; export DEVKIT_TASK=$TA

cat > "$t/fake" <<'F'
#!/usr/bin/env bash
# $1=prompt $2=handoff path. Behaviour via FAKE_* env.
if [ /dev/stdin -ef /dev/null ]; then stdin_state=null; else stdin_state=open; fi
echo "$(date +%s) start $FAKE_ID" >> "$DEVKIT_DIR/events"
echo $$ > "$DEVKIT_DIR/fakepid.${FAKE_ID:-x}"
[ -n "${FAKE_SPAWN:-}" ] && "$FAKE_SPAWN" x${DEVKIT_DEPTH:-} fake /dev/null > "$DEVKIT_DIR/nested.out" 2>&1; echo $? > "$DEVKIT_DIR/nested.rc"
[ -n "${FAKE_PUSH:-}" ] && { git push origin HEAD >/dev/null 2>&1; echo $? > "$DEVKIT_DIR/push.rc"; }
[ -n "${FAKE_EDIT:-}" ] && echo changed >> f.txt
[ -n "${FAKE_COMMIT:-}" ] && { echo c >> f.txt; git add f.txt; git -c user.name=t -c user.email=t@t commit -qm scoutcommit; }
[ -n "${FAKE_GIT:-}" ] && { git config --get remote.origin.pushurl > "$DEVKIT_DIR/pushurl.out" 2>&1; echo $? > "$DEVKIT_DIR/git.rc"; }
[ -n "${FAKE_GRAND:-}" ] && { ( sleep 60 & echo $! > "$DEVKIT_DIR/grand.${FAKE_ID}"; wait ) & } # sleep-ok: grandchild outlives the fake; the harness kills it
[ -n "${FAKE_DEEP:-}" ] && { ( ( sleep 60 & echo $! > "$DEVKIT_DIR/deep.${FAKE_ID}"; wait ) & wait ) & } # sleep-ok: two-level grandchild outlives the fake; the test checks it dies
[ -z "${FAKE_HOLD:-}" ] || while [ -e "$FAKE_HOLD" ]; do sleep 0.1; done # sleep-ok: bounded by the test, which removes the hold file after its poll
sleep "${FAKE_SLEEP:-0}"
[ -n "${FAKE_NOHANDOFF:-}" ] || printf 'depth=%s cwd=%s stdin=%s\n' "${DEVKIT_DEPTH:-}" "$PWD" "$stdin_state" > "$2"
[ -n "${FAKE_CHECKLIST:-}" ] && printf '\n## Checklist\n%b\n' "$FAKE_CHECKLIST" >> "$2"
echo "$(date +%s) end $FAKE_ID" >> "$DEVKIT_DIR/events"
F
chmod +x "$t/fake"; export DEVKIT_FAKE="$t/fake"
echo "do the thing" > "$t/brief.md"

FAKE_ID=a "$spawn" a fake "$t/brief.md"
ok "ship run writes handoff"       '[ -s $TD/handoffs/a.md ]'
ok "status is done"                'grep -q "^done 0" $TD/run/a.status'
ok "worker sees DEVKIT_DEPTH=1"   'grep -q "depth=1" $TD/handoffs/a.md'

FAKE_ID=d2 DEVKIT_DEPTH=1 "$spawn" d2 fake "$t/brief.md"; rc=$?
ok "a depth-1 worker may spawn; its child sees depth 2" '[ $rc -eq 0 ] && grep -q "depth=2" $TD/handoffs/d2.md'
DEVKIT_DEPTH=3 "$spawn" z fake "$t/brief.md" 2>/dev/null; rc=$?
ok "spawn refuses at the depth limit (3)" '[ $rc -eq 3 ]'
DEVKIT_MAX_DEPTH=1 DEVKIT_DEPTH=1 "$spawn" z fake "$t/brief.md" 2>/dev/null; rc=$?
ok "DEVKIT_MAX_DEPTH=1 restores the no-nesting rule" '[ $rc -eq 3 ]'
FAKE_ID=n FAKE_SPAWN="$spawn" "$spawn" n fake "$t/brief.md"
ok "a worker can spawn a child, down to the limit" '[ "$(cat $DEVKIT_DIR/nested.rc)" = 0 ] && [ -s $TD/handoffs/x1.md ] && [ -s $TD/handoffs/x2.md ]'
FAKE_ID=n2 DEVKIT_MAX_DEPTH=1 FAKE_SPAWN="$spawn" "$spawn" n2 fake "$t/brief.md"
ok "nested spawn blocked when the limit is 1" '[ "$(cat $DEVKIT_DIR/nested.rc)" = 3 ]'

"$spawn" q nosuchcli "$t/brief.md" 2>/dev/null; rc=$?
ok "unknown cli exits 2"           '[ $rc -eq 2 ]'

FAKE_ID=m FAKE_NOHANDOFF=1 "$spawn" m fake "$t/brief.md"
ok "missing handoff -> fallback + failed" 'grep -q "no handoff written" $TD/handoffs/m.md && grep -q "^failed" $TD/run/m.status'

git checkout -q f.txt
FAKE_ID=s FAKE_EDIT=1 "$spawn" --shape scout s fake "$t/brief.md"
ok "scout that edits code is flagged" 'grep -q "^violation" $TD/run/s.status'
git checkout -q f.txt

FAKE_ID=w "$spawn" --worktree w fake "$t/brief.md"
ok "worktree created on branch"    'git rev-parse --verify -q devkit/$TA-w >/dev/null'
ok "worker ran inside worktree"    'grep -q "cwd=.*/wt/w" $TD/handoffs/w.md'

: > $DEVKIT_DIR/events
for i in 1 2 3; do FAKE_ID=c$i FAKE_SLEEP=1 DEVKIT_MAX_WORKERS=2 "$spawn" c$i fake "$t/brief.md" & done; wait
third=$(awk '$2=="start"{print $1}' $DEVKIT_DIR/events | sort -n | tail -1)
firstend=$(awk '$2=="end"{print $1}' $DEVKIT_DIR/events | sort -n | head -1)
ok "cap=2: third starts after a slot frees" '[ "$third" -ge "$firstend" ]'
ok "slots released afterwards"     '[ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'

DEVKIT_TASK=$TB FAKE_ID=a "$spawn" a fake "$t/brief.md"
ok "same worker id in another task does not collide" '[ -s "$DEVKIT_DIR/tasks/$TB/handoffs/a.md" ] && [ -s $TD/handoffs/a.md ] && ! cmp -s "$DEVKIT_DIR/tasks/$TB/handoffs/a.md" /dev/null'
env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$spawn" q fake "$t/brief.md" 2>/dev/null; rc=$?
ok "spawn without a task exits 2"  '[ $rc -eq 2 ]'
# --- session pointer fallback: $DEVKIT_TASK, then `ledger current`
SP=sess-spawn; PT=$(CLAUDE_CODE_SESSION_ID=$SP "$ledger" start ptr-spawn "x"); PTD=$DEVKIT_DIR/tasks/$PT
env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SP FAKE_ID=ps "$spawn" ps fake "$t/brief.md"; rc=$?
ok "no DEVKIT_TASK: the pointer supplies the task" '[ $rc -eq 0 ] && [ -s "$PTD/handoffs/ps.md" ] && grep -q "ps done" "$PTD/ledger.tsv"'
DEVKIT_TASK=$TB CLAUDE_CODE_SESSION_ID=$SP FAKE_ID=ex "$spawn" ex fake "$t/brief.md"; rc=$?
ok "DEVKIT_TASK wins over the pointer"             '[ $rc -eq 0 ] && [ -s "$DEVKIT_DIR/tasks/$TB/handoffs/ex.md" ] && [ ! -e "$PTD/handoffs/ex.md" ]'
gate_pass "$PT"; "$ledger" -t "$PT" done "closed" >/dev/null 2>&1
env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SP "$spawn" q2 fake "$t/brief.md" >/dev/null 2>"$t/sp-closed.err"; rc=$?ok "closed pointer: the clear error names the task" '[ $rc -eq 2 ] && grep -q "last task $PT is closed (or gone)" "$t/sp-closed.err"'
DEVKIT_TASK=$TB FAKE_ID=iso "$spawn" iso fake "$t/brief.md"
ok "spawn logs only to its own task's ledger" 'grep -q "iso done" "$DEVKIT_DIR/tasks/$TB/ledger.tsv" && ! grep -q "iso" $TD/ledger.tsv'

: > $DEVKIT_DIR/events
for i in 1 2 3; do tk=$TA; [ $i = 2 ] && tk=$TB; DEVKIT_TASK=$tk FAKE_ID=x$i FAKE_SLEEP=1 DEVKIT_MAX_WORKERS=2 "$spawn" x$i fake "$t/brief.md" & done; wait
third=$(awk '$2=="start"{print $1}' $DEVKIT_DIR/events | sort -n | tail -1)
firstend=$(awk '$2=="end"{print $1}' $DEVKIT_DIR/events | sort -n | head -1)
ok "cap=2 holds across different tasks" '[ "$third" -ge "$firstend" ]'

# a killed spawner's slot stays counted while its worker runs: six claimers, two slots, kill -9 both holders
: > $DEVKIT_DIR/events
hold="$t/k.hold"; : > "$hold"; spids=()
for i in 1 2 3 4 5 6; do FAKE_HOLD=$hold FAKE_ID=ck$i DEVKIT_MAX_WORKERS=2 "$spawn" ck$i fake "$t/brief.md" & spids+=($!); done
n=0; while [ "$(awk '$2=="start"' $DEVKIT_DIR/events | wc -l | tr -d ' ')" -lt 2 ] && [ $n -lt 100 ]; do sleep 0.05; n=$((n+1)); done # sleep-ok: bounded poll until both slots are held
n=0; while [ "$(ls "$DEVKIT_DIR"/run/slot.*/wpid 2>/dev/null | wc -l | tr -d ' ')" -lt 2 ] && [ $n -lt 100 ]; do sleep 0.05; n=$((n+1)); done # sleep-ok: bounded poll until the held slots record their workers
for id in $(awk '$2=="start"{print $3}' $DEVKIT_DIR/events | head -2); do kill -9 "${spids[$(( ${id#ck} - 1 ))]}" 2>/dev/null; done
sleep 0.3 # sleep-ok: a wrongly freed live slot would let a third worker start in this window
starts=$(awk '$2=="start"' $DEVKIT_DIR/events | wc -l | tr -d ' ')
held=0; for d in "$DEVKIT_DIR"/run/slot.*; do case $d in *.lock) continue;; esac; [ -d "$d" ] || continue
  wp=$(cat "$d/wpid" 2>/dev/null); [ -n "$wp" ] && kill -0 "$wp" 2>/dev/null && held=$((held+1)); done
rm -f "$hold"; wait
ok "a killed spawner keeps its live worker's slot counted (no third start)" '[ "$starts" -eq 2 ] && [ "$held" -eq 2 ]'
ok "the freed slots are reclaimed and all six workers finish" '[ -s $TD/handoffs/ck6.md ] && [ "$(cd $TD/handoffs && ls ck1.md ck2.md ck3.md ck4.md ck5.md ck6.md | wc -l | tr -d " ")" -eq 6 ]'

: > $DEVKIT_DIR/events
hold="$t/m.hold"; : > "$hold"
for i in $(seq 1 10); do FAKE_HOLD=$hold FAKE_ID=m$i FAKE_SLEEP=1 DEVKIT_MAX_WORKERS=10 "$spawn" m$i fake "$t/brief.md" & done
n=0; while [ $n -lt 150 ]; do [ "$(grep -c " start" $DEVKIT_DIR/events)" -ge 10 ] && break; sleep 0.2; n=$((n+1)); done # sleep-ok: bounded poll (150 tries) for ten start events
FAKE_ID=m11 FAKE_SLEEP=1 DEVKIT_MAX_WORKERS=10 "$spawn" m11 fake "$t/brief.md" & sleep 1 # sleep-ok: give a wrongly uncapped eleventh time to start while the ten are held
rm -f "$hold"; wait
firstend=$(awk '$2=="end"{print $1}' $DEVKIT_DIR/events | sort -n | head -1)
before=$(awk -v f="$firstend" '$2=="start" && $1<f' $DEVKIT_DIR/events | wc -l | tr -d ' ')
ok "DEVKIT_MAX_WORKERS=10 caps: ten start together, the eleventh waits" '[ "$n" -lt 40 ] && [ "$before" -eq 10 ]'

FAKE_ID=hold FAKE_SLEEP=2 DEVKIT_MAX_WORKERS=1 "$spawn" hold fake "$t/brief.md" & n=0; while [ ! -s "$DEVKIT_DIR/fakepid.hold" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll until the holder claimed its slot
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" nest fake "$t/brief.md" 2>"$t/nest.err"; rc=$?
ok "a nested spawn that finds no free slot fails fast (exit 4)" '[ $rc -eq 4 ] && grep -q "no free" "$t/nest.err"'
wait

DEVKIT_DRYRUN=1 "$spawn" p1 fake "$t/brief.md" > "$t/p1.out"
ok "prompt tells a worker below the limit it may spawn"  'grep -q "may spawn" "$t/p1.out"'
DEVKIT_MAX_DEPTH=1 DEVKIT_DRYRUN=1 "$spawn" p2 fake "$t/brief.md" > "$t/p2.out"
ok "prompt tells a worker at the limit not to spawn"      'grep -q "Do not spawn" "$t/p2.out" && ! grep -q "may spawn" "$t/p2.out"'

# worker playbook: a route line in the brief sends the worker to that playbook; it loads the playbook's checklist itself (any CLI)
DEVKIT_DRYRUN=1 "$spawn" c1 fake "$t/brief.md" > "$t/c1.out"
ok "prompt tells the worker to open the playbook checklist in its host todo list"  'grep -q "host todo list" "$t/c1.out" && grep -q "Checklist" "$t/c1.out"'
ok "no route in the brief: ship workers follow dev-feature by path"  'grep -q "skills/dev-feature/SKILL.md" "$t/c1.out"'
ok "the prompt does not inline a checklist"  '! sed "/--- BRIEF ---/,\$d" "$t/c1.out" | grep -q -- "- \[ \]"'
ok "the checklist is the FIRST thing the prompt asks for, before any other tool call"  'sed -n 2p "$t/c1.out" | grep -q "^FIRST ACTION, before any other tool call" && sed -n 2p "$t/c1.out" | grep -q "host todo list" && sed -n 2p "$t/c1.out" | grep -q "skills/dev-feature/SKILL.md"'
ok "the first line names the todo tools and the deferred-tool load"  'sed -n 2p "$t/c1.out" | grep -q "TaskCreate" && sed -n 2p "$t/c1.out" | grep -q "TodoWrite" && sed -n 2p "$t/c1.out" | grep -q "update_plan" && sed -n 2p "$t/c1.out" | grep -q "ToolSearch"'
ok "prompt asks the handoff to end with ## Checklist, ticked"  'grep -q "## Checklist" "$t/c1.out"'
printf 'do it\nroute: dev-debug\n' > "$t/brief-rt.md"
DEVKIT_DRYRUN=1 "$spawn" c6 fake "$t/brief-rt.md" > "$t/c6.out"
DEVKIT_DRYRUN=1 "$spawn" c6c claude "$t/brief-rt.md" > "$t/c6c.out"; DEVKIT_DRYRUN=1 "$spawn" c6x codex "$t/brief-rt.md" > "$t/c6x.out"; DEVKIT_DRYRUN=1 "$spawn" c6o opencode "$t/brief-rt.md" > "$t/c6o.out"
ok "a brief naming a route sends the worker to that playbook, on every CLI"  'grep -q "skills/dev-debug/SKILL.md" "$t/c6.out" "$t/c6c.out" "$t/c6x.out" "$t/c6o.out" && ! grep -q "skills/dev-feature" "$t/c6.out"\'
FAKE_ID=c3 FAKE_CHECKLIST='- [x] 1. a\n- [-] 2. b (skipped: n/a)' "$spawn" c3 fake "$t/brief.md" > "$t/c3.out" 2>"$t/c3.err"
ok "closed checklist is tallied 2/2"  'grep -q "checklist: 2/2" "$t/c3.out" && grep -q "^2/2" $TD/run/c3.checklist'
FAKE_ID=c4 FAKE_CHECKLIST='- [x] 1. a\n- [ ] 2. b' "$spawn" c4 fake "$t/brief.md" > "$t/c4.out" 2>"$t/c4.err"
ok "an open item is tallied 1/2 and warned about"  'grep -q "checklist: 1/2" "$t/c4.out" && grep -qi "checklist.*open" "$t/c4.err"'
FAKE_ID=c5 "$spawn" c5 fake "$t/brief.md" > "$t/c5.out" 2>"$t/c5.err"
ok "a handoff with no checklist is flagged missing"  'grep -q "^missing" $TD/run/c5.checklist && grep -qi "checklist.*missing" "$t/c5.err"'

FAKE_ID=c7 FAKE_CHECKLIST='  * [X] 1. a\n- [x] 2. b' "$spawn" c7 fake "$t/brief.md" > "$t/c7.out" 2>/dev/null
ok "tally accepts [X], * bullets and indentation"  'grep -q "checklist: 2/2" "$t/c7.out"'
printf 'see "route: dev-nope" in prose\n' > "$t/brief-bad.md"; printf 'x\nroute: dev-nope\n' > "$t/brief-bad2.md"
DEVKIT_DRYRUN=1 "$spawn" c8 fake "$t/brief-bad.md" > "$t/c8.out"; DEVKIT_DRYRUN=1 "$spawn" c9 fake "$t/brief-bad2.md" > "$t/c9.out"
ok "a route line that is prose or names no playbook falls back to the shape default"  '! grep -q "skills/dev-nope" "$t/c8.out" "$t/c9.out" && grep -q "skills/dev-feature" "$t/c8.out" "$t/c9.out"'
DEVKIT_DRYRUN=1 "$spawn" --shape scout c10 fake "$t/brief.md" > "$t/c10.out"
ok "default playbook: ship follows dev-feature, scout follows dev-research"  'grep -q "skills/dev-feature/SKILL.md" "$t/c1.out" && grep -q "skills/dev-research/SKILL.md" "$t/c10.out"'

# a route line that cannot be used must be loud: one stderr warning and one ledger row per spawn, never on dry-run
printf 'do it\nroute: dev-review (extra words)\n' > "$t/brief-rw1.md"
FAKE_ID=rw1 "$spawn" rw1 fake "$t/brief-rw1.md" 2>"$t/rw1.err"
ok "an unusable route line warns once and falls back" 'grep -q "spawn: WARN brief route line not usable (.route: dev-review (extra words).); using dev-feature" "$t/rw1.err" && [ "$(grep -c "route line not usable" "$t/rw1.err")" -eq 1 ]'
ok "the route warning appends exactly one ledger row" '[ "$(grep -c "rw1 route-warning" $TD/ledger.tsv)" -eq 1 ]'
DEVKIT_DRYRUN=1 "$spawn" rw1d fake "$t/brief-rw1.md" > "$t/rw1d.out" 2>"$t/rw1d.err"
ok "an unusable route line falls back to the ship default" 'grep -q "skills/dev-feature/SKILL.md" "$t/rw1d.out" && ! grep -q "skills/dev-review" "$t/rw1d.out"'
ok "dry-run skips the route warning and its ledger row" '! grep -q "route line not usable" "$t/rw1d.err" && [ "$(grep -c "rw1d route-warning" $TD/ledger.tsv)" -eq 0 ]'
printf 'do it\nroute: dev-mode\n' > "$t/brief-rw2.md"
FAKE_ID=rw2 "$spawn" rw2 fake "$t/brief-rw2.md" 2>"$t/rw2.err"
ok "route: dev-mode is not a worker playbook, so it warns" 'grep -q "route line not usable (.route: dev-mode.)" "$t/rw2.err" && grep -q "using dev-feature" "$t/rw2.err"'
printf 'do it\nroute: dev-nosuch\n' > "$t/brief-rw3.md"
FAKE_ID=rw3 "$spawn" rw3 fake "$t/brief-rw3.md" 2>"$t/rw3.err"
ok "route: naming a missing playbook warns" 'grep -q "route line not usable (.route: dev-nosuch.)" "$t/rw3.err" && grep -q "using dev-feature" "$t/rw3.err"'
printf 'do it\nroute: dev-review\n' > "$t/brief-rw4.md"
FAKE_ID=rw4 "$spawn" rw4 fake "$t/brief-rw4.md" 2>"$t/rw4.err"
ok "a clean route line does not warn" '! grep -q "route line not usable" "$t/rw4.err"'
FAKE_ID=rw5 "$spawn" rw5 fake "$t/brief.md" 2>"$t/rw5.err"
ok "no route line does not warn" '! grep -q "route line not usable" "$t/rw5.err"'
DEVKIT_DRYRUN=1 "$spawn" rw6 fake "$t/brief.md" > "$t/rw6.out"
ok "worker prompt forbids ledger done: the parent closes the task" 'grep -q "never run .bin/ledger done" "$t/rw6.out" && grep -q "the parent closes the task" "$t/rw6.out"'
FAKE_ID=c11 FAKE_NOHANDOFF=1 FAKE_SLEEP=0 "$spawn" c11 fake "$t/brief.md" > "$t/c11.out" 2>"$t/c11.err"
ok "no checklist noise when the worker wrote no handoff"  '! grep -qi "checklist" "$t/c11.err"'

FAKE_ID=in "$spawn" in fake "$t/brief.md" < "$t/brief.md"
ok "worker stdin is closed (no hang on stdin)" 'grep -q "stdin=null$" $TD/handoffs/in.md'

echo dirty > "$t/predirty.txt"
FAKE_ID=pd "$spawn" --shape scout pd fake "$t/brief.md"
ok "scout not blamed for files dirty before the run" 'grep -q "^done" $TD/run/pd.status'

# --- dry-run: flag composition for the real adapters, without running them
d=$(DEVKIT_DRYRUN=1 "$spawn" --model m1 d1 claude "$t/brief.md" | tr '\n' ' ')
ok "dry-run claude: -p, --model m1, permissions skipped" 'echo "$d" | grep -q -- "-p " && echo "$d" | grep -q -- "--model m1" && echo "$d" | grep -q -- "--no-session-persistence" && echo "$d" | grep -q -- "--dangerously-skip-permissions"'
d=$(DEVKIT_DRYRUN=1 "$spawn" --model m2 d2 codex "$t/brief.md" | tr '\n' ' ')
ok "dry-run codex: exec, bypass approvals+sandbox, -m m2" 'echo "$d" | grep -q "exec" && echo "$d" | grep -q -- "--dangerously-bypass-approvals-and-sandbox" && ! echo "$d" | grep -q -- "workspace-write" && echo "$d" | grep -q -- "-m m2" && echo "$d" | grep -q -- "--ephemeral"'
d=$(DEVKIT_MODEL=prov/m3 DEVKIT_DRYRUN=1 "$spawn" d3 opencode "$t/brief.md" | tr '\n' ' ')
ok "dry-run opencode: run --auto, -m from DEVKIT_MODEL" 'echo "$d" | grep -q "run" && echo "$d" | grep -q -- "--auto" && echo "$d" | grep -q -- "-m prov/m3"'
ok "dry-run opencode: names its own session and title" 'echo "$d" | grep -q -- "-s ses_dk_" && echo "$d" | grep -q -- "--title d3"'
d=$(DEVKIT_DRYRUN=1 "$spawn" d4 claude "$t/brief.md" | tr '\n' ' ')
ok "worker prompt asks for learnings in the handoff" 'echo "$d" | grep -q "learnings"'
ok "worker prompt forbids pushing" 'echo "$d" | grep -q "Never git push"'
d=$(DEVKIT_SAFE=1 DEVKIT_DRYRUN=1 "$spawn" d5 claude "$t/brief.md" | tr '\n' ' '); d6=$(DEVKIT_SAFE=1 DEVKIT_DRYRUN=1 "$spawn" d6 codex "$t/brief.md" | tr '\n' ' ')
ok "DEVKIT_SAFE=1 restores restricted modes" 'echo "$d" | grep -q -- "--permission-mode acceptEdits" && ! echo "$d" | grep -q -- "--dangerously" && echo "$d6" | grep -q -- "-s workspace-write" && ! echo "$d6" | grep -q -- "--dangerously"'
d=$(DEVKIT_DRYRUN=1 "$spawn" d4 claude "$t/brief.md" | tr '\n' ' ')
ok "worker prompt forbids starting a new task" 'echo "$d" | grep -q "Do not start a new task"'
ok "no model flag unless asked"    '! echo "$d" | grep -q -- "--model"'
ok "dry-run leaves no status files" '[ ! -e $TD/run/d1.status ] && [ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'

# --- --prompt: no brief file needed
FAKE_ID=pp "$spawn" --prompt "inline ask" pp fake
ok "--prompt runs and saves the brief" '[ -s $TD/handoffs/pp.md ] && grep -q "inline ask" $TD/briefs/pp.md'

# --- watchdog
s0=$(date +%s); FAKE_ID=to FAKE_SLEEP=30 DEVKIT_TIMEOUT=1 "$spawn" to fake "$t/brief.md"; rc=$?; el=$(( $(date +%s)-s0 ))
FAKE_ID=td FAKE_DEEP=1 FAKE_SLEEP=30 DEVKIT_TIMEOUT=1 "$spawn" td fake "$t/brief.md" 2>/dev/null; n=0; while kill -0 "$(cat $DEVKIT_DIR/deep.td 2>/dev/null)" 2>/dev/null && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll for the group kill to land
ok "timeout kills a grandchild two levels down" '[ -s $DEVKIT_DIR/deep.td ] && ! kill -0 "$(cat $DEVKIT_DIR/deep.td)" 2>/dev/null'
( FAKE_ID=ti FAKE_DEEP=1 FAKE_SLEEP=30 exec "$spawn" ti fake "$t/brief.md" ) 2>/dev/null &
sp=$!; n=0; while [ ! -s $DEVKIT_DIR/deep.ti ] && [ $n -lt 50 ]; do sleep 0.2; n=$((n+1)); done; kill -TERM $sp; wait $sp 2>/dev/null # sleep-ok: bounded poll for the grandchild
n=0; while kill -0 "$(cat $DEVKIT_DIR/deep.ti 2>/dev/null)" 2>/dev/null && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll for the group kill to land
ok "interrupt kills a grandchild two levels down" '[ -s $DEVKIT_DIR/deep.ti ] && ! kill -0 "$(cat $DEVKIT_DIR/deep.ti)" 2>/dev/null'
ok "DEVKIT_TIMEOUT kills a hung worker quickly" '[ $rc -ne 0 ] && [ $el -lt 15 ]'
ok "timeout is its own status + noted in handoff" 'grep -q "^timeout" $TD/run/to.status && grep -qi "timed out" $TD/handoffs/to.md'
ok "slot released after timeout"    '[ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'

# --- doctor, with stub CLIs on PATH
mkdir -p "$t/hm/.config/opencode"; echo '{"experimental":{"todo":true}}' > "$t/hm/.config/opencode/opencode.jsonc"; export HOME="$t/hm" # hermetic: the doctor reads the global opencode config
stubs="$t/stubs"; mkdir -p "$stubs"
cat > "$stubs/claude" <<'S'
#!/usr/bin/env bash
case "$1" in --version) echo "claude 9.9";; *) echo "-p --permission-mode --allowedTools --add-dir --no-session-persistence --model --dangerously-skip-permissions";; esac
S
cat > "$stubs/codex" <<'S'
#!/usr/bin/env bash
case "$1" in --version) echo "WARNING: could not create PATH aliases" >&2; echo "codex 8.8";; *) echo "-C -s --add-dir --skip-git-repo-check -o -m --dangerously-bypass-approvals-and-sandbox $CODEX_STUB_EXTRA";; esac
S
cat > "$stubs/opencode" <<'S'
#!/usr/bin/env bash
case "$1" in --version) echo "opencode 7.7";; service) echo "${OC_SERVICE:-http://127.0.0.1:49374}";; *) echo "--auto -m -s --title";; esac
S
chmod +x "$stubs"/*
out=$(PATH="$stubs:/usr/bin:/bin" CODEX_STUB_EXTRA="--ephemeral" "$spawn" --doctor 2>&1); rc=$?
ok "doctor: service up -> no warning" '! echo "$out" | grep -q WARN'
ok "doctor: all flags present -> ok, exit 0" '[ $rc -eq 0 ] && echo "$out" | grep -q "claude.*9.9.*ok" && echo "$out" | grep -q "codex.*8.8.*ok" && echo "$out" | grep -q "opencode.*7.7.*ok"'
out=$(PATH="$stubs:/usr/bin:/bin" CODEX_STUB_EXTRA="" "$spawn" --doctor 2>&1); rc=$?
ok "doctor: missing flag named, exit 1" '[ $rc -ne 0 ] && echo "$out" | grep -q "codex.*MISSING.*--ephemeral"'
out=$(PATH="$stubs:/usr/bin:/bin" CODEX_STUB_EXTRA="--ephemeral" OC_SERVICE="stopped" "$spawn" --doctor 2>&1)
ok "doctor: opencode service down -> hint" 'echo "$out" | grep -q "opencode service start"'
out=$(PATH="/usr/bin:/bin" "$spawn" --doctor 2>&1)
ok "doctor: absent CLI reported, not an error" 'echo "$out" | grep -q "claude.*not installed"'

# --- push guard: a worker cannot push to an existing remote, whatever CLI it runs
git init -q --bare "$t/remote.git"; git remote add origin "$t/remote.git"
FAKE_ID=pg FAKE_PUSH=1 "$spawn" pg fake "$t/brief.md"
ok "worker push is blocked" '[ "$(cat $DEVKIT_DIR/push.rc)" != 0 ] && [ "$(git -C "$t/remote.git" rev-list --all 2>/dev/null | wc -l)" -eq 0 ]'
ok "the main agent can still push" 'git push -q origin HEAD 2>/dev/null && [ "$(git -C "$t/remote.git" rev-list --all | wc -l)" -ge 1 ]'

# --- herdr view: a tab tails the worker log and the pane is reported as an agent (stub herdr, never the real one)
hs="$t/herdr-stub"; mkdir -p "$hs"; export HERDR_LOG="$t/herdr.log"
cat > "$hs/herdr" <<'S'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_LOG"
case "$1 $2" in
  "tab list") exit "${HERDR_DOWN:-0}";;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"X:p9","tab_id":"X:t9"},"tab":{"tab_id":"X:t9"}}}';;
esac
S
chmod +x "$hs/herdr"
vrun() { : > "$HERDR_LOG"; ( export PATH="$hs:$PATH"; "$@" ); }

DEVKIT_VIEW=herdr FAKE_ID=v1 vrun "$spawn" v1 fake "$t/brief.md"
ok "view: tab labelled '<id> · <cli> · <shape>', no focus steal" 'grep -q "tab create --label v1 · fake · ship --cwd .* --no-focus" "$HERDR_LOG"'
ok "view: pane tails the worker log"            'grep -q "pane run X:p9 tail -n +1 -f .*v1.log" "$HERDR_LOG"'
ok "view: reported working, then idle"          'grep -n "report-agent" "$HERDR_LOG" | head -1 | grep -q "working" && grep "report-agent" "$HERDR_LOG" | tail -1 | grep -q "idle"'
ok "view: Agents panel gets title and display name" 'grep "report-metadata" "$HERDR_LOG" | grep -q -- "--display-agent fake ship" && grep "report-metadata" "$HERDR_LOG" | grep -q -- "--title v1"'
ok "view: no notification when all is well"      '! grep -q "notification show" "$HERDR_LOG"'
ok "view: tab closed after a successful run"    'grep -q "tab close X:t9" "$HERDR_LOG"'
ok "view: worker itself unchanged (done + handoff)" 'grep -q "^done" $TD/run/v1.status && [ -s $TD/handoffs/v1.md ]'

# opencode names its session, so its tab must attach to that live session rather than tail a log
oc="$t/oc-stub"; mkdir -p "$oc"; export OC_LOG="$t/oc.log"
cat > "$oc/opencode" <<'S'
#!/usr/bin/env bash
echo "$*" >> "$OC_LOG"
case "$1" in
  run) p="${@: -1}"; hf=$(printf '%s' "$p" | grep -o '/[^ ]*handoffs/[A-Za-z0-9_-]*\.md' | head -1)
       [ -n "$hf" ] && echo "handoff from the opencode stub" > "$hf";;
esac
exit 0
S
chmod +x "$oc/opencode"
: > "$OC_LOG"; : > "$HERDR_LOG"
( export PATH="$oc:$hs:$PATH"; DEVKIT_VIEW=herdr "$spawn" oc1 opencode "$t/brief.md" )
runline=$(grep '^run ' "$OC_LOG" | head -1)
sid_run=$(printf '%s' "$runline" | grep -o 'ses_[A-Za-z0-9_]*' | head -1)
pcmd=$(grep "pane run" "$HERDR_LOG" | head -1)
ok "view: opencode run names its session"              '[ -n "$sid_run" ] && grep -q "^done" $TD/run/oc1.status && [ -s $TD/handoffs/oc1.md ]'
ok "view: opencode tab attaches to that same session"  'echo "$pcmd" | grep -q "exec opencode -s" && echo "$pcmd" | grep -q "$sid_run"'
ok "view: opencode tab falls back to the log only if the session never appears" 'echo "$pcmd" | grep -q "exec opencode -s" && [ "${pcmd#*tail -n}" != "$pcmd" ]'
ok "view: opencode tab still closes if the spawner dies" 'echo "$pcmd" | grep -q "kill -0" && echo "$pcmd" | grep -q "tab close"'

DEVKIT_VIEW_KEEP=1 DEVKIT_VIEW=herdr FAKE_ID=v2 vrun "$spawn" v2 fake "$t/brief.md"
ok "view: DEVKIT_VIEW_KEEP=1 leaves the tab open" '! grep -q "tab close" "$HERDR_LOG" && grep "report-agent" "$HERDR_LOG" | tail -1 | grep -q "idle"'

DEVKIT_VIEW=herdr FAKE_ID=v3 FAKE_NOHANDOFF=1 vrun "$spawn" v3 fake "$t/brief.md" 2> "$t/v3.err"
ok "view: a failed worker is reported blocked, then its tab is closed" 'grep "report-agent" "$HERDR_LOG" | tail -1 | grep -q "blocked" && grep -q "tab close X:t9" "$HERDR_LOG"'
ok "view: failure raises a notification with the request sound" 'grep "notification show" "$HERDR_LOG" | grep -q "v3" && grep "notification show" "$HERDR_LOG" | grep -q -- "--sound request"'
ok "view: a closed failed tab is not remembered" '[ ! -e $TD/run/v3.tab ]'
ok "view: failure is reported to the caller on stderr" 'grep -q "spawn: v3 failed" "$t/v3.err" && grep -q "v3.md" "$t/v3.err"'

DEVKIT_VIEW_KEEP=1 DEVKIT_VIEW=herdr FAKE_ID=v8 FAKE_NOHANDOFF=1 vrun "$spawn" v8 fake "$t/brief.md" 2>/dev/null
ok "view: DEVKIT_VIEW_KEEP=1 keeps a failed tab and remembers it" '! grep -q "tab close" "$HERDR_LOG" && [ -s $TD/run/v8.tab ]'
: > "$HERDR_LOG"; ( export PATH="$hs:$PATH"; "$spawn" --close-views )
ok "view: --close-views closes kept tabs and forgets them" 'grep -q "tab close X:t9" "$HERDR_LOG" && [ ! -e $TD/run/v8.tab ]'
# --close-views falls back through the session pointer too
CS=sess-cv; CT=$(CLAUDE_CODE_SESSION_ID=$CS "$ledger" start ptr-cv "x"); CTD=$DEVKIT_DIR/tasks/$CT; mkdir -p "$CTD/run"
echo X:t9 > "$CTD/run/cv.tab"
: > "$HERDR_LOG"
( export PATH="$hs:$PATH"; env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$CS "$spawn" --close-views ); rc=$?
ok "--close-views: no DEVKIT_TASK, the pointer supplies the task" '[ $rc -eq 0 ] && [ ! -e "$CTD/run/cv.tab" ] && grep -q "tab close X:t9" "$HERDR_LOG"'
gate_pass "$CT"; "$ledger" -t "$CT" done "closed" >/dev/null 2>&1
( export PATH="$hs:$PATH"; env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$CS "$spawn" --close-views 2>"$t/cv-closed.err" ); rc=$?
ok "--close-views: closed pointer errors clearly" '[ $rc -eq 2 ] && grep -q "last task $CT is closed (or gone)" "$t/cv-closed.err"'
# an interrupted spawn must not leave its tab, an orphan worker, a held slot or a stale "running" status
: > "$HERDR_LOG"
( export PATH="$hs:$PATH"; DEVKIT_VIEW=herdr FAKE_ID=k1 FAKE_SLEEP=20 exec "$spawn" k1 fake "$t/brief.md" ) 2>/dev/null &
sp=$!; n=0; while [ ! -s "$DEVKIT_DIR/fakepid.k1" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done; kill -TERM $sp; wait $sp 2>/dev/null # sleep-ok: bounded poll until the worker claimed tab and slot
n=0; while [ -e "$DEVKIT_DIR/run/slot.1" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll for cleanup to settle
ok "interrupted spawn closes its herdr tab"          'grep -q "tab close X:t9" "$HERDR_LOG"'
ok "interrupted spawn stops its worker"              '! kill -0 "$(cat $DEVKIT_DIR/fakepid.k1)" 2>/dev/null'
ok "interrupted spawn records killed, not running"   'grep -q "^killed" $TD/run/k1.status && grep -q "k1 killed" $TD/ledger.tsv'
ok "interrupted spawn frees its slot"                '[ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'
kill "$(cat $DEVKIT_DIR/fakepid.k1)" 2>/dev/null; true

# a hard-killed spawn runs no EXIT trap, so the pane itself must close the tab once the spawn pid is gone
: > "$HERDR_LOG"
DEVKIT_VIEW=herdr FAKE_ID=v9 vrun "$spawn" v9 fake "$t/brief.md"
pcmd=$(grep "pane run" "$HERDR_LOG" | head -1 | sed 's/^pane run [^ ]* //')
ok "view: pane command watches the spawn pid" 'echo "$pcmd" | grep -q "kill -0" && echo "$pcmd" | grep -q "tab close"'
: > "$HERDR_LOG"
if echo "$pcmd" | grep -q "kill -0"; then ( export PATH="$hs:$PATH"; eval "$pcmd" ) & ev=$!; n=0; while ! grep -q "tab close X:t9" "$HERDR_LOG" && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done; kill -0 $ev 2>/dev/null && kill $ev 2>/dev/null; wait $ev 2>/dev/null || true; fi # sleep-ok: bounded poll for the pane watchdog to see the dead spawn pid
ok "view: watchdog closes the tab once the spawn pid is gone" 'grep -q "tab close X:t9" "$HERDR_LOG"'
: > "$HERDR_LOG"
DEVKIT_VIEW_KEEP=1 DEVKIT_VIEW=herdr FAKE_ID=v10 vrun "$spawn" v10 fake "$t/brief.md"
pcmd=$(grep "pane run" "$HERDR_LOG" | head -1 | sed 's/^pane run [^ ]* //')
ok "view: watchdog keeps the tab when DEVKIT_VIEW_KEEP=1" '! echo "$pcmd" | grep -q "tab close"'

DEVKIT_VIEW_NOTIFY=all DEVKIT_VIEW=herdr FAKE_ID=v7 vrun "$spawn" v7 fake "$t/brief.md"
ok "view: DEVKIT_VIEW_NOTIFY=all also notifies on success" 'grep "notification show" "$HERDR_LOG" | grep -q -- "--sound done"'

DEVKIT_VIEW=off FAKE_ID=v4 vrun "$spawn" v4 fake "$t/brief.md"
ok "view: DEVKIT_VIEW=off makes no herdr calls" '[ ! -s "$HERDR_LOG" ] && grep -q "^done" $TD/run/v4.status'

HERDR_DOWN=1 DEVKIT_VIEW=herdr FAKE_ID=v5 vrun "$spawn" v5 fake "$t/brief.md"
ok "view: herdr server down falls back to headless" '! grep -q "tab create" "$HERDR_LOG" && grep -q "^done" $TD/run/v5.status'

( export PATH="/usr/bin:/bin"; export DEVKIT_VIEW=herdr; FAKE_ID=v6 "$spawn" v6 fake "$t/brief.md" )
ok "view: no herdr installed falls back to headless" 'grep -q "^done" $TD/run/v6.status'

# --- hardening 1: numeric knobs fail closed with exit 2 naming the knob
DEVKIT_DRYRUN=1 DEVKIT_MAX_WORKERS=0 "$spawn" e1 fake "$t/brief.md" 2>"$t/e1.err"; rc=$?
ok "DEVKIT_MAX_WORKERS=0 exits 2 naming the knob" '[ $rc -eq 2 ] && grep -q "DEVKIT_MAX_WORKERS" "$t/e1.err"'
DEVKIT_DRYRUN=1 DEVKIT_MAX_WORKERS=many "$spawn" e2 fake "$t/brief.md" 2>"$t/e2.err"; rc=$?
ok "DEVKIT_MAX_WORKERS=many exits 2 naming the knob" '[ $rc -eq 2 ] && grep -q "DEVKIT_MAX_WORKERS" "$t/e2.err"'
DEVKIT_DRYRUN=1 DEVKIT_CHILD_WAIT=1.5 "$spawn" e3 fake "$t/brief.md" 2>"$t/e3.err"; rc=$?
ok "DEVKIT_CHILD_WAIT=1.5 exits 2 naming the knob" '[ $rc -eq 2 ] && grep -q "DEVKIT_CHILD_WAIT" "$t/e3.err"'
DEVKIT_DRYRUN=1 DEVKIT_TIMEOUT=soon "$spawn" e4 fake "$t/brief.md" 2>"$t/e4.err"; rc=$?
ok "DEVKIT_TIMEOUT=soon exits 2 naming the knob" '[ $rc -eq 2 ] && grep -q "DEVKIT_TIMEOUT" "$t/e4.err"'
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=0 DEVKIT_MAX_WORKERS=2x "$spawn" e5 fake "$t/brief.md" 2>"$t/e5.err"; rc=$?
ok "a non-numeric cap fails closed (exit 2) instead of misclaiming" '[ $rc -eq 2 ] && grep -q "DEVKIT_MAX_WORKERS" "$t/e5.err"'

# --- hardening 3: the reaped pid is cleared so cleanup cannot signal a reused pid (behavior: interrupted-spawn test above frees its slot with no orphan worker)

# --- hardening 4: the reclaim lock names its owner (pid + start); only a dead or reused owner is stolen
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
FAKE_ID=lk0 DEVKIT_MAX_WORKERS=1 "$spawn" lk0 fake "$t/brief.md"
ok "a stale slot is reclaimed, no lock left" '[ -s $TD/handoffs/lk0.md ] && [ -z "$(ls -d $DEVKIT_DIR/run/slot.*.lock 2>/dev/null)" ]'
# the regression: a live owner's lock is never taken, however old it is (the old 5s mtime expiry did take it)
sleep 30 & live=$! # sleep-ok: live lock-owner fixture, killed right after
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
ln -s "$live $(LC_ALL=C TZ=UTC ps -o lstart= -p "$live")" "$DEVKIT_DIR/run/slot.1.lock"
touch -h -t 200001010000 "$DEVKIT_DIR/run/slot.1.lock"
s0=$(date +%s); DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" lkl fake "$t/brief.md" 2>/dev/null; rc=$?; el=$(( $(date +%s)-s0 ))
ok "a live lock owner is not stolen however old the lock is" '[ $rc -eq 4 ] && [ "$el" -ge 1 ] && [ -L "$DEVKIT_DIR/run/slot.1.lock" ] && [ "$(cat "$DEVKIT_DIR/run/slot.1/pid")" = 99999999 ]'
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# a live owner whose start record is missing is still not stolen (same rule as an empty slot start)
sleep 30 & live=$! # sleep-ok: live lock-owner fixture, killed right after
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
ln -s "$live " "$DEVKIT_DIR/run/slot.1.lock"
touch -h -t 200001010000 "$DEVKIT_DIR/run/slot.1.lock" # only the owner rule can keep it: the old age rule would steal it
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" lke fake "$t/brief.md" 2>/dev/null; rc=$?
ok "a live lock owner without a start record is not stolen" '[ $rc -eq 4 ] && [ -L "$DEVKIT_DIR/run/slot.1.lock" ]'
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"
# a legacy directory lock (the pre-owner format) has no record; it must not wedge the slot
mkdir -p "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
FAKE_ID=lkg DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 DEVKIT_MAX_WORKERS=1 "$spawn" lkg fake "$t/brief.md" 2>/dev/null; rc=$?
ok "a legacy directory lock is reclaimed, not fatal" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lkg.md ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- hardening 5: a slot dir without a pid file gets a 1s grace, then counts as stale
mkdir -p "$DEVKIT_DIR/run/slot.1"
s0=$(date +%s); DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 FAKE_ID=lk2 DEVKIT_MAX_WORKERS=1 "$spawn" lk2 fake "$t/brief.md" 2>/dev/null; rc=$?; el=$(( $(date +%s)-s0 ))
ok "a slot dir without a pid file is reclaimed after a grace" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lk2.md ] && [ "$el" -ge 1 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- hardening 6: a dead or reused owner's lock is reclaimed at once; its age plays no part
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
ln -s "99999998 Mon Jan  1 00:00:00 2001" "$DEVKIT_DIR/run/slot.1.lock"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 FAKE_ID=lkd DEVKIT_MAX_WORKERS=1 "$spawn" lkd fake "$t/brief.md" 2>/dev/null; rc=$?
ok "a dead lock owner's fresh lock is reclaimed" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lkd.md ] && [ ! -e "$DEVKIT_DIR/run/slot.1.lock" ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"
sleep 30 & live=$! # sleep-ok: live-pid fixture, killed right after
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
ln -s "$live bogus start" "$DEVKIT_DIR/run/slot.1.lock"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 FAKE_ID=lkr DEVKIT_MAX_WORKERS=1 "$spawn" lkr fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "a lock whose owner pid was reused is reclaimed" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lkr.md ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- hardening 7: pid reuse is guarded by a start-time record
sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; echo "bogus" > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 FAKE_ID=lk4 DEVKIT_MAX_WORKERS=1 "$spawn" lk4 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "a slot with a live pid but mismatched start is reclaimed" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lk4.md ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"
sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$live" > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" lk5 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "a slot with a live pid and matching start is kept" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# a stalled claimer (slow ps in its live scan) must keep its slot: the pid is written before the scan
sleep 30 & live=$! # sleep-ok: live-pid fixture, killed right after
mkdir -p "$DEVKIT_DIR/run/slot.2"; echo "$live" > "$DEVKIT_DIR/run/slot.2/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$live" > "$DEVKIT_DIR/run/slot.2/start"
slowps="$t/slowps"; mkdir -p "$slowps"; real_ps=$(command -v ps)
printf '#!/bin/sh\ncase "$*" in *"-p %s"*) sleep 1;; esac\nexec %s "$@"\n' "$live" "$real_ps" > "$slowps/ps"; chmod +x "$slowps/ps" # sleep-ok: the stall under test
( export PATH="$slowps:$PATH"; FAKE_ID=st1 FAKE_SLEEP=3 DEVKIT_MAX_WORKERS=2 "$spawn" st1 fake "$t/brief.md" 2>/dev/null ) & sa=$!
n=0; while [ ! -d "$DEVKIT_DIR/run/slot.1" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done # sleep-ok: bounded poll until A is mid-claim
( export PATH="$slowps:$PATH"; DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 FAKE_ID=st2 DEVKIT_MAX_WORKERS=2 "$spawn" st2 fake "$t/brief.md" 2>"$t/st2.err" ); rc=$?
wait $sa; kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "a stalled claimer keeps its slot (a second spawn finds none free)" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.2" "$DEVKIT_DIR/run/slot.2.lock"

# --- hardening 8: a claim takes the same owner lock as a reclaim, so a reclaimer cannot move a fresh pid aside
ps_stall() { # $1=pid to stall on $2=entered marker $3=release marker: ps blocks inside the reclaimer's liveness check and then reports a 2001 start
  local d=$t/psstall; mkdir -p "$d"
  printf '#!/bin/sh\ncase "$*" in *"-p %s"*) : > %s; n=0; while [ ! -e %s ] && [ $n -lt 200 ]; do sleep 0.02; n=$((n+1)); done; echo "Mon Jan  1 00:00:00 2001"; exit;; esac\nexec %s "$@"\n' "$1" "$2" "$3" "$real_ps" > "$d/ps" # sleep-ok: bounded poll inside the stub, released by the test
  chmod +x "$d/ps"; echo "$d"
}
sleep 30 & owner=$! # sleep-ok: owner fixture the reclaimer judges dead by its start record
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$owner" > "$DEVKIT_DIR/run/slot.1/pid"; echo bogus > "$DEVKIT_DIR/run/slot.1/start"
rm -f "$t/ps.in" "$t/ps.out"; pd=$(ps_stall "$owner" "$t/ps.in" "$t/ps.out")
: > "$DEVKIT_DIR/events"
PATH="$pd:$PATH" DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 FAKE_ID=sr1 DEVKIT_MAX_WORKERS=1 "$spawn" sr1 fake "$t/brief.md" 2>/dev/null & ra=$!
n=0; while [ ! -e "$t/ps.in" ] && [ $n -lt 100 ]; do sleep 0.05; n=$((n+1)); done # sleep-ok: bounded poll until the reclaimer is in its liveness check
rm -rf "$DEVKIT_DIR/run/slot.1" # the owner's exit trap removes its dir
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 FAKE_ID=sr2 DEVKIT_MAX_WORKERS=1 "$spawn" sr2 fake "$t/brief.md" 2>/dev/null & rb=$!
n=0; while [ $n -lt 10 ] && [ "$(awk '/ start/{n++} END{print n+0}' "$DEVKIT_DIR/events")" -eq 0 ]; do sleep 0.05; n=$((n+1)); done # sleep-ok: bounded window for a wrongly admitted claim to start its worker
started=$(awk '/ start/{n++} END{print n+0}' "$DEVKIT_DIR/events")
: > "$t/ps.out"; kill -TERM "$ra" "$rb" 2>/dev/null; wait "$ra" 2>/dev/null; wait "$rb" 2>/dev/null
ok "a stalled reclaimer's lock keeps a fresh claim out of its slot" '[ "$started" -eq 0 ]'
kill "$owner" 2>/dev/null; wait "$owner" 2>/dev/null
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# the fence: a reclaim that judged a pid dead must not free a slot a fresh claim has taken.
# claim() is executed from an extracted copy (not grepped): slot_live is stubbed to swap the dir at the read.
claim_src="$t/claim.fn"; sed -n '/^slot_lock() {/,/^}/p; /^claim() {/,/^  done; return 1; }/p' "$spawn" > "$claim_src"
ok "claim() and slot_lock() are extractable for the fence unit test" '[ "$(grep -c "^slot_lock() {" "$claim_src")" -eq 1 ] && [ "$(grep -c "^claim() {" "$claim_src")" -eq 1 ] && [ "$(grep -c "done; return 1; }" "$claim_src")" -eq 1 ]'
sleep 30 & fresh=$! # sleep-ok: the fresh claim's live pid, killed right after
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
( H="$DEVKIT_DIR"; CAP=1; slot=
  . "$claim_src"
  slot_live() { # the reclaimer reads a dead pid, then a fresh claim replaces the dir in the same window
    if [ -z "${swapped:-}" ]; then swapped=1; rm -rf "$1"; mkdir -p "$1"; echo "$fresh" > "$1/pid"
      LC_ALL=C TZ=UTC ps -o lstart= -p "$fresh" > "$1/start"; fi
    return 1; }
  claim
  echo "slot=${slot:-none} pid=$(cat "$H/run/slot.1/pid" 2>/dev/null)" > "$t/fence.out" )
ok "the fence restores a fresh pid it moved aside" 'grep -qx "slot=none pid=$fresh" "$t/fence.out"'
kill "$fresh" 2>/dev/null; wait "$fresh" 2>/dev/null
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# kill -9 of spawn frees no slot while its worker still runs
sleep 30 & live=$! # sleep-ok: live worker fixture, killed right after
sleep 0 & dead=$!; wait $dead 2>/dev/null # sleep-ok: exits at once, gives a dead pid
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$dead" > "$DEVKIT_DIR/run/slot.1/pid"; echo "$live" > "$DEVKIT_DIR/run/slot.1/wpid"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" wk1 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "a slot whose spawner died but whose worker lives stays counted" '[ $rc -eq 4 ]'
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 FAKE_ID=wk2 DEVKIT_MAX_WORKERS=1 "$spawn" wk2 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "once the worker is gone too, the slot is reclaimed" '[ $rc -eq 0 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- ship fixes: empty start, TZ-normalized lstart, 08 depth, worktree reuse, cap counts slots above CAP
sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; : > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" lk6 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "an empty start file is treated as no record (live slot kept)" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$live" > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 TZ="Pacific/Kiritimati" "$spawn" lk7 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "lstart compared in UTC: a foreign-TZ spawner still matches the live pid" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

FAKE_ID=oct DEVKIT_DEPTH=08 DEVKIT_MAX_DEPTH=10 "$spawn" oct fake "$t/brief.md" 2>"$t/oct.err"; rc=$?
ok "DEVKIT_DEPTH=08 is decimal 8, child sees depth 9" '[ $rc -eq 0 ] && grep -q "depth=9" $TD/handoffs/oct.md'

FAKE_ID=w2 "$spawn" --worktree w2 fake "$t/brief.md"
FAKE_ID=w2 "$spawn" --worktree w2 fake "$t/brief.md" 2>"$t/w2.err"; rc=$?
ok "re-running an id with --worktree reuses the worktree" '[ $rc -eq 0 ] && [ -s $TD/handoffs/w2.md ]'

sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.3"; echo "$live" > "$DEVKIT_DIR/run/slot.3/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$live" > "$DEVKIT_DIR/run/slot.3/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" lk8 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "slots above a lowered CAP still count (cap=1, slot.3 live)" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.3" "$DEVKIT_DIR/run/slot.3.lock"

fresh=$(mktemp -d); (cd "$t" && DEVKIT_DIR="$fresh/.devkit" env -u DEVKIT_TASK "$spawn" q fake "$t/brief.md" 2>/dev/null); rc=$?
ok "no task creates no run dir" '[ $rc -eq 2 ] && [ ! -e "$fresh/.devkit/run" ]'
rm -rf "$fresh"

# --- audit fixes: arg validation, GIT_CONFIG_COUNT, duplicate ids
"$spawn" --shape foo sh1 fake "$t/brief.md" 2>/dev/null; rc=$?
"$spawn" --shape "" sh2 fake "$t/brief.md" 2>"$t/sh2.err"; rc2=$?
ok "--shape outside ship|scout exits 2 (also when empty, no shell error)" '[ $rc -eq 2 ] && [ $rc2 -eq 2 ] && ! grep -q "unary" "$t/sh2.err"'
sleep 30 & live=$! # sleep-ok: live-pid fixture, killed right after
echo "running $live 1" > "$TD/run/dup.status"
FAKE_ID=dup "$spawn" dup fake "$t/brief.md" 2>"$t/dup.err"; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "a second spawn of an id that is running with a live pid is refused (exit 2)" '[ $rc -eq 2 ] && grep -q "already running" "$t/dup.err"'
echo "running 99999999 1" > "$TD/run/dup.status"
FAKE_ID=dup "$spawn" dup fake "$t/brief.md"; rc=$?
ok "a stale running status (dead pid) does not block the id" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/dup.status'
rm -f "$DEVKIT_DIR/git.rc" "$DEVKIT_DIR/pushurl.out"
( export GIT_CONFIG_COUNT=08; for i in 0 1 2 3 4 5 6 7; do export "GIT_CONFIG_KEY_$i=test.k$i" "GIT_CONFIG_VALUE_$i=v"; done
  FAKE_ID=gc FAKE_GIT=1 "$spawn" gc fake "$t/brief.md" 2>/dev/null )
ok "GIT_CONFIG_COUNT=08 is read as decimal 8: git works in the worker and the push guard holds" '[ "$(cat $DEVKIT_DIR/git.rc 2>/dev/null)" = 0 ] && grep -q "push-blocked" $DEVKIT_DIR/pushurl.out'
GIT_CONFIG_COUNT=abc "$spawn" gc2 fake "$t/brief.md" 2>"$t/gc2.err"; rc=$?
ok "a non-numeric GIT_CONFIG_COUNT fails closed (exit 2)" '[ $rc -eq 2 ] && grep -q "GIT_CONFIG_COUNT" "$t/gc2.err"'

# --- audit fixes: scout violations (commits, repeat edits), process-group kill, slot tracking
git checkout -q f.txt
FAKE_ID=sc FAKE_COMMIT=1 "$spawn" --shape scout sc fake "$t/brief.md"
ok "a scout that commits is flagged" 'grep -q "^violation" $TD/run/sc.status'
git reset -q --hard HEAD~1
echo pre >> f.txt
FAKE_ID=sr FAKE_EDIT=1 "$spawn" --shape scout sr fake "$t/brief.md"
ok "a scout editing an already-dirty file is flagged" 'grep -q "^violation" $TD/run/sr.status'
git checkout -q f.txt

# --- run/<id>.session: the parent Stop hook matches workers to their parent session
CLAUDE_CODE_SESSION_ID=sess-one FAKE_ID=se1 "$spawn" se1 fake "$t/brief.md"
ok "session id is written to run/<id>.session" '[ "$(cat $TD/run/se1.session)" = sess-one ]'
env -u CLAUDE_CODE_SESSION_ID FAKE_ID=se2 "$spawn" se2 fake "$t/brief.md"; rc=$?
ok "no session file when the id is unset, spawn still succeeds" '[ $rc -eq 0 ] && [ ! -e $TD/run/se2.session ]'
CLAUDE_CODE_SESSION_ID=sess-two FAKE_ID=se1 "$spawn" se1 fake "$t/brief.md"
ok "respawn overwrites a stale session file" '[ "$(cat $TD/run/se1.session)" = sess-two ]'
env -u CLAUDE_CODE_SESSION_ID FAKE_ID=se1 "$spawn" se1 fake "$t/brief.md"
ok "respawn without an id removes a stale session file" '[ ! -e $TD/run/se1.session ]'
CLAUDE_CODE_SESSION_ID=sess-dry DEVKIT_DRYRUN=1 "$spawn" se3 fake "$t/brief.md" >/dev/null
ok "dry-run leaves no session file" '[ ! -e $TD/run/se3.session ]'

# --- --lead marks a long-lived lead worker so the parent Stop hook does not hold on it while it runs
FAKE_ID=ow1 "$spawn" --lead ow1 fake "$t/brief.md"; rc=$?
ok "--lead writes run/<id>.detached and the worker still finishes" '[ $rc -eq 0 ] && [ -e $TD/run/ow1.detached ] && grep -q "^done" $TD/run/ow1.status'
FAKE_ID=ow2 "$spawn" ow2 fake "$t/brief.md"
ok "no marker without --lead"                          '[ ! -e $TD/run/ow2.detached ]'
FAKE_ID=ow1 "$spawn" ow1 fake "$t/brief.md"
ok "a respawn without --lead removes a stale marker"   '[ ! -e $TD/run/ow1.detached ]'
DEVKIT_DRYRUN=1 "$spawn" --lead ow3 fake "$t/brief.md" >/dev/null
ok "dry-run leaves no marker"                           '[ ! -e $TD/run/ow3.detached ]'

# --- session pointer fallback: -t/DEVKIT_TASK, then `ledger current` (main path and --close-views)
SPS=sess-spawn; SP=$(CLAUDE_CODE_SESSION_ID=$SPS "$ledger" start ptr-spawn x); SPD="$DEVKIT_DIR/tasks/$SP"
cat > "$t/fake-env" <<'F'
#!/usr/bin/env bash
printf 'task=%s\n' "${DEVKIT_TASK:-}" > "$DEVKIT_DIR/envtask.$FAKE_ID"
printf "ok\n\n## Checklist\n- [x] done\n" > "$2"
F
chmod +x "$t/fake-env"
env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID "$spawn" pn fake "$t/brief.md" >/dev/null 2>"$t/pn.err"; rc=$?
ok "spawn: no pointer and no DEVKIT_TASK keeps the old error and exit 2" '[ $rc -eq 2 ] && grep -q "spawn: no task. Run: ledger start <slug>; set DEVKIT_TASK" "$t/pn.err"'
env -u DEVKIT_TASK DEVKIT_DEPTH=1 CLAUDE_CODE_SESSION_ID=$SPS "$spawn" pw fake "$t/brief.md" >/dev/null 2>"$t/pw.err"; rc=$?
ok "spawn: a worker environment never uses the pointer" '[ $rc -eq 2 ] && grep -q "spawn: no task. Run: ledger start" "$t/pw.err"'
env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SPS FAKE_ID=sq1 DEVKIT_FAKE="$t/fake-env" "$spawn" sq1 fake "$t/brief.md"; rc=$?
ok "spawn: only the pointer: the worker runs in the pointed task" '[ $rc -eq 0 ] && [ -s "$SPD/handoffs/sq1.md" ] && grep -q "^done 0" "$SPD/run/sq1.status" && [ ! -e "$TD/handoffs/sq1.md" ]'
ok "spawn: the worker's own environment has DEVKIT_TASK set to the pointed task" '[ "$(cat "$DEVKIT_DIR/envtask.sq1")" = "task=$SP" ]'
DEVKIT_TASK=$TB CLAUDE_CODE_SESSION_ID=$SPS FAKE_ID=pe DEVKIT_FAKE="$t/fake-env" "$spawn" pe fake "$t/brief.md"; rc=$?
ok "spawn: DEVKIT_TASK wins over the pointer" '[ $rc -eq 0 ] && [ -s "$DEVKIT_DIR/tasks/$TB/handoffs/pe.md" ] && [ ! -e "$SPD/handoffs/pe.md" ] && [ "$(cat "$DEVKIT_DIR/envtask.pe")" = "task=$TB" ]'
gate_pass "$SP"; "$ledger" -t "$SP" done "closed" >/dev/null 2>&1
env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$SPS "$spawn" pc fake "$t/brief.md" >/dev/null 2>"$t/pc.err"; rc=$?
ok "spawn: a closed pointer errors clearly, naming the task, exit 2" '[ $rc -eq 2 ] && grep -q "last task $SP is closed (or gone)" "$t/pc.err" && [ ! -e "$SPD/handoffs/pc.md" ]'

# --close-views: a herdr stub records which tab it was told to close
cv="$t/cvbin"; mkdir -p "$cv"; export CV_LOG="$t/cv.log"; : > "$CV_LOG"
printf '#!/usr/bin/env bash\necho "$*" >> "$CV_LOG"\nexit 0\n' > "$cv/herdr"; chmod +x "$cv/herdr"
CVS=sess-cv; CVT=$(CLAUDE_CODE_SESSION_ID=$CVS "$ledger" start ptr-cv x); CVD="$DEVKIT_DIR/tasks/$CVT"; mkdir -p "$CVD/run" "$TD/run"
echo tab-ptr > "$CVD/run/v1.tab"; echo tab-exp > "$TD/run/v2.tab"
env -u DEVKIT_TASK -u CLAUDE_CODE_SESSION_ID PATH="$cv:$PATH" "$spawn" --close-views >/dev/null 2>"$t/cv0.err"; rc=$?
ok "close-views: no pointer keeps the old error" '[ $rc -eq 2 ] && grep -q "spawn: no task. Set DEVKIT_TASK" "$t/cv0.err" && [ ! -s "$CV_LOG" ]'
DEVKIT_TASK=$TA CLAUDE_CODE_SESSION_ID=$CVS PATH="$cv:$PATH" "$spawn" --close-views; rc=$?
ok "close-views: explicit DEVKIT_TASK wins over the pointer" '[ $rc -eq 0 ] && grep -q "tab close tab-exp" "$CV_LOG" && ! grep -q "tab-ptr" "$CV_LOG" && [ ! -e "$TD/run/v2.tab" ] && [ -f "$CVD/run/v1.tab" ]'
env -u DEVKIT_TASK CLAUDE_CODE_SESSION_ID=$CVS PATH="$cv:$PATH" "$spawn" --close-views; rc=$?
ok "close-views: only the pointer closes the pointed task's tab" '[ $rc -eq 0 ] && grep -q "tab close tab-ptr" "$CV_LOG" && [ ! -e "$CVD/run/v1.tab" ]'

ok "no call escaped to the tripwire herdr (real herdr never reached)" '[ ! -s "$HERDR_TRIPWIRE_LOG" ]'

# route line forms: indent is trimmed, a fenced or earlier unusable example never hides the real line
printf 'do it\n  route: dev-debug\n' > "$t/brief-ri1.md"
printf 'Example:\n  route: dev-nope\nwork\nroute: dev-debug\n' > "$t/brief-ri2.md"
printf 'Write a line like:\n```\nroute: dev-review\n```\nwork\n' > "$t/brief-ri3.md"
printf 'Write a line like:\n```\nroute: dev-review\n```\nroute: dev-debug\n' > "$t/brief-ri4.md"
for n in 1 2 3 4; do FAKE_ID=ri$n "$spawn" ri$n fake "$t/brief-ri$n.md" 2>"$t/ri$n.err"; DEVKIT_DRYRUN=1 "$spawn" ri${n}d fake "$t/brief-ri$n.md" > "$t/ri$n.out" 2>/dev/null; done
ok "an indented route line is used and does not warn" 'grep -q "skills/dev-debug/SKILL.md" "$t/ri1.out" && ! grep -q "route line not usable" "$t/ri1.err"'
ok "an unusable example before the real route line is skipped silently" 'grep -q "skills/dev-debug/SKILL.md" "$t/ri2.out" && ! grep -q "route line not usable" "$t/ri2.err"'
ok "a route line inside a code fence is ignored" 'grep -q "skills/dev-feature/SKILL.md" "$t/ri3.out" && ! grep -q "skills/dev-review" "$t/ri3.out" && ! grep -q "route line not usable" "$t/ri3.err"'
ok "a fenced example does not hide the real route line after it" 'grep -q "skills/dev-debug/SKILL.md" "$t/ri4.out"'
printf 'Brief says:\n  route: dev-review\nreal\nroute: dev-debug\n' > "$t/brief-ri5.md"
DEVKIT_DRYRUN=1 "$spawn" ri5 fake "$t/brief-ri5.md" > "$t/ri5.out" 2>/dev/null
ok "a column-0 route line beats an indented example before it" 'grep -q "skills/dev-debug/SKILL.md" "$t/ri5.out" && ! grep -q "skills/dev-review" "$t/ri5.out"'
DEVKIT_STOP_TIMEOUT=0 "$spawn" st0 fake "$t/brief.md" > "$t/st0.out" 2>&1; rc=$?
ok "DEVKIT_STOP_TIMEOUT=0 is refused (0 would kill the delete at once)" '[ $rc -eq 2 ] && grep -q "DEVKIT_STOP_TIMEOUT must be at least 1" "$t/st0.out"'
DEVKIT_STOP_TIMEOUT=x "$spawn" st1 fake "$t/brief.md" > "$t/st1.out" 2>&1; rc=$?
ok "DEVKIT_STOP_TIMEOUT=x is refused as not a number" '[ $rc -eq 2 ] && grep -q "DEVKIT_STOP_TIMEOUT must be a whole number" "$t/st1.out"'

# --- worker id rule: lowercase start, [a-z0-9_-], 1-32 chars; checked before any side effect
idmsg() { printf "spawn: worker id '%s' must start with a lowercase letter and use only lowercase letters, digits, - or _ (1-32 characters)" "$1"; }
snap() { { find "$DEVKIT_DIR" -path "$DEVKIT_DIR/tasks/*/wt" -prune -o -type f -print 2>/dev/null; wc -l < "$TD/ledger.tsv"; } | sort | md5sum 2>/dev/null || cksum; }
long33=$(printf 'a%.0s' $(seq 33)); long32=$(printf 'a%.0s' $(seq 32))
for bad in vlA 1ab -ab _ab "" "a b" a.b a/b "$long33"; do
  before=$(snap); out=$("$spawn" "$bad" fake "$t/brief.md" 2>&1); rc=$?; after=$(snap)
  ok "bad id '$bad' exits 2 with the rule and the id" '[ $rc -eq 2 ] && [ "$out" = "$(idmsg "$bad")" ]'
  ok "bad id '$bad' leaves no ledger row, run file or brief" '[ "$before" = "$after" ]'
done
before=$(snap); out=$(DEVKIT_DRYRUN=1 "$spawn" vlA fake "$t/brief.md" 2>&1); rc=$?
ok "dry run validates the id too" '[ $rc -eq 2 ] && [ "$out" = "$(idmsg vlA)" ] && [ "$before" = "$(snap)" ]'
before=$(snap); out=$("$spawn" --prompt "hi" vlA fake 2>&1); rc=$?
ok "a bad id with --prompt saves no brief" '[ $rc -eq 2 ] && [ "$before" = "$(snap)" ] && [ ! -e "$TD/briefs/vlA.md" ]'
out=$(DEVKIT_MODE=interactive "$spawn" vlA claude "$t/brief.md" 2>&1); rc=$?
ok "a bad id fails before any herdr call (no tab, no slot)" '[ $rc -eq 2 ] && [ ! -s "$HERDR_TRIPWIRE_LOG" ] && [ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'
for good in a a1 a-b a_b c6c ri1d "$long32"; do
  out=$(DEVKIT_DRYRUN=1 "$spawn" "$good" fake "$t/brief.md" 2>&1); rc=$?
  ok "valid id '$good' passes the id check" '[ $rc -eq 0 ]'
done

# --- hardening 9: a failed start or exit ledger row fails closed (the gate trusts those rows)
BIN="$t/bin"; mkdir -p "$BIN"; cp -R "$here/bin/." "$BIN"/
cat > "$BIN/ledger" <<'L'
#!/usr/bin/env bash
if [ -n "${FAIL_ROW:-}" ] && printf '%s' "$*" | grep -qF -- " $FAIL_ROW "; then exit 1; fi
exec "$REAL_LEDGER" "$@"
L
chmod +x "$BIN/ledger"
FAIL_ROW="spawn fr1 running" REAL_LEDGER="$here/bin/ledger" FAKE_ID=fr1 "$BIN/spawn" fr1 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "a failed start row fails the spawn before the worker starts" '[ $rc -eq 2 ] && [ ! -e "$DEVKIT_DIR/fakepid.fr1" ]'
FAIL_ROW="spawn fr2 done" REAL_LEDGER="$here/bin/ledger" FAKE_ID=fr2 "$BIN/spawn" fr2 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "a failed exit row is not reported done" '[ $rc -ne 0 ] && [ "$(cut -d" " -f1 $TD/run/fr2.status)" = failed ] && [ -s $TD/handoffs/fr2.md ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
