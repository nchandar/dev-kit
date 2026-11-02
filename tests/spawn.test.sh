#!/usr/bin/env bash
# Tests for bin/spawn using a fake agent CLI (no tokens). Usage: tests/spawn.test.sh
set -u
unset DEVKIT_DEPTH  # these suites must pass when run from inside a worker too
# a worker also inherits its model, tunables and the push guard; none may change what this suite measures
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && echo base > f.txt && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
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
ledger="$here/bin/ledger"
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
sleep "${FAKE_SLEEP:-0}"
[ -n "${FAKE_NOHANDOFF:-}" ] || printf 'depth=%s cwd=%s stdin=%s\n' "${DEVKIT_DEPTH:-}" "$PWD" "$stdin_state" > "$2"
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
for i in 1 2 3; do FAKE_ID=c$i FAKE_SLEEP=2 DEVKIT_MAX_WORKERS=2 "$spawn" c$i fake "$t/brief.md" & done; wait
third=$(awk '$2=="start"{print $1}' $DEVKIT_DIR/events | sort -n | tail -1)
firstend=$(awk '$2=="end"{print $1}' $DEVKIT_DIR/events | sort -n | head -1)
ok "cap=2: third starts after a slot frees" '[ "$third" -ge "$firstend" ]'
ok "slots released afterwards"     '[ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'

DEVKIT_TASK=$TB FAKE_ID=a "$spawn" a fake "$t/brief.md"
ok "same worker id in another task does not collide" '[ -s "$DEVKIT_DIR/tasks/$TB/handoffs/a.md" ] && [ -s $TD/handoffs/a.md ] && ! cmp -s "$DEVKIT_DIR/tasks/$TB/handoffs/a.md" /dev/null'
env -u DEVKIT_TASK "$spawn" q fake "$t/brief.md" 2>/dev/null; rc=$?
ok "spawn without a task exits 2"  '[ $rc -eq 2 ]'
DEVKIT_TASK=$TB FAKE_ID=iso "$spawn" iso fake "$t/brief.md"
ok "spawn logs only to its own task's ledger" 'grep -q "iso done" "$DEVKIT_DIR/tasks/$TB/ledger.tsv" && ! grep -q "iso" $TD/ledger.tsv'

: > $DEVKIT_DIR/events
for i in 1 2 3; do tk=$TA; [ $i = 2 ] && tk=$TB; DEVKIT_TASK=$tk FAKE_ID=x$i FAKE_SLEEP=2 DEVKIT_MAX_WORKERS=2 "$spawn" x$i fake "$t/brief.md" & done; wait
third=$(awk '$2=="start"{print $1}' $DEVKIT_DIR/events | sort -n | tail -1)
firstend=$(awk '$2=="end"{print $1}' $DEVKIT_DIR/events | sort -n | head -1)
ok "cap=2 holds across different tasks" '[ "$third" -ge "$firstend" ]'

: > $DEVKIT_DIR/events
for i in $(seq 1 10); do FAKE_ID=m$i FAKE_SLEEP=8 "$spawn" m$i fake "$t/brief.md" & done
n=0; while [ $n -lt 40 ]; do [ "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null | grep -cv '\.lock$')" -ge 10 ] && break; sleep 0.5; n=$((n+1)); done # sleep-ok: bounded poll (40 tries) for ten slots to be claimed
FAKE_ID=m11 FAKE_SLEEP=1 "$spawn" m11 fake "$t/brief.md" & wait
firstend=$(awk '$2=="end"{print $1}' $DEVKIT_DIR/events | sort -n | head -1)
before=$(awk -v f="$firstend" '$2=="start" && $1<f' $DEVKIT_DIR/events | wc -l | tr -d ' ')
ok "default cap is 10: ten start together, the eleventh waits" '[ "$n" -lt 40 ] && [ "$before" -eq 10 ]'

FAKE_ID=hold FAKE_SLEEP=4 DEVKIT_MAX_WORKERS=1 "$spawn" hold fake "$t/brief.md" & sleep 1 # sleep-ok: let the holder claim its slot before the nested attempt
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=1 DEVKIT_MAX_WORKERS=1 "$spawn" nest fake "$t/brief.md" 2>"$t/nest.err"; rc=$?
ok "a nested spawn that finds no free slot fails fast (exit 4)" '[ $rc -eq 4 ] && grep -q "no free" "$t/nest.err"'
wait

DEVKIT_DRYRUN=1 "$spawn" p1 fake "$t/brief.md" > "$t/p1.out"
ok "prompt tells a worker below the limit it may spawn"  'grep -q "may spawn" "$t/p1.out"'
DEVKIT_MAX_DEPTH=1 DEVKIT_DRYRUN=1 "$spawn" p2 fake "$t/brief.md" > "$t/p2.out"
ok "prompt tells a worker at the limit not to spawn"      'grep -q "Do not spawn" "$t/p2.out" && ! grep -q "may spawn" "$t/p2.out"'

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
s0=$(date +%s); FAKE_ID=to FAKE_SLEEP=30 DEVKIT_TIMEOUT=2 "$spawn" to fake "$t/brief.md"; rc=$?; el=$(( $(date +%s)-s0 ))
ok "DEVKIT_TIMEOUT kills a hung worker quickly" '[ $rc -ne 0 ] && [ $el -lt 15 ]'
ok "timeout is its own status + noted in handoff" 'grep -q "^timeout" $TD/run/to.status && grep -qi "timed out" $TD/handoffs/to.md'
ok "slot released after timeout"    '[ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'

# --- doctor, with stub CLIs on PATH
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
case "$1" in --version) echo "opencode 7.7";; service) echo "${OC_SERVICE:-http://127.0.0.1:49374}";; *) echo "--auto -m";; esac
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
# an interrupted spawn must not leave its tab, an orphan worker, a held slot or a stale "running" status
: > "$HERDR_LOG"
( export PATH="$hs:$PATH"; DEVKIT_VIEW=herdr FAKE_ID=k1 FAKE_SLEEP=20 exec "$spawn" k1 fake "$t/brief.md" ) 2>/dev/null &
sp=$!; sleep 3; kill -TERM $sp; wait $sp 2>/dev/null; sleep 1 # sleep-ok: let the worker claim tab and slot before TERM; let cleanup settle
ok "interrupted spawn closes its herdr tab"          'grep -q "tab close X:t9" "$HERDR_LOG"'
ok "interrupted spawn stops its worker"              '! kill -0 "$(cat $DEVKIT_DIR/fakepid.k1)" 2>/dev/null'
ok "interrupted spawn records killed, not running"   'grep -q "^killed" $TD/run/k1.status && grep -q "k1 killed" $TD/ledger.tsv'
ok "interrupted spawn frees its slot"                '[ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'
kill "$(cat $DEVKIT_DIR/fakepid.k1)" 2>/dev/null; pkill -f "sleep 20" 2>/dev/null; true

# a hard-killed spawn runs no EXIT trap, so the pane itself must close the tab once the spawn pid is gone
: > "$HERDR_LOG"
DEVKIT_VIEW=herdr FAKE_ID=v9 vrun "$spawn" v9 fake "$t/brief.md"
pcmd=$(grep "pane run" "$HERDR_LOG" | head -1 | sed 's/^pane run [^ ]* //')
ok "view: pane command watches the spawn pid" 'echo "$pcmd" | grep -q "kill -0" && echo "$pcmd" | grep -q "tab close"'
: > "$HERDR_LOG"
if echo "$pcmd" | grep -q "kill -0"; then ( export PATH="$hs:$PATH"; eval "$pcmd" ) & ev=$!; sleep 2; kill -0 $ev 2>/dev/null && kill $ev 2>/dev/null; wait $ev 2>/dev/null || true; fi # sleep-ok: give the pane watchdog time to see the dead spawn pid before killing it
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

# --- hardening 2: slot scan is a while loop (seq 1 0 counts down on BSD)
ok "claim scans slots without BSD-unsafe seq" '! grep -q "seq 1" "$spawn"' # pitfall-ok: src-grep negative assertion, slot tests cover behavior
# --- hardening 3: the reaped pid is cleared so cleanup cannot signal a reused pid (behavior: interrupted-spawn test above frees its slot with no orphan worker)

# --- hardening 4: a per-slot mkdir lock guards stale-slot reclaim
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
FAKE_ID=lk0 DEVKIT_MAX_WORKERS=1 "$spawn" lk0 fake "$t/brief.md"
ok "a stale slot is reclaimed under its lock, lock released" '[ -s $TD/handoffs/lk0.md ] && [ -z "$(ls -d $DEVKIT_DIR/run/slot.*.lock 2>/dev/null)" ]'
mkdir -p "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
s0=$(date +%s); DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=3 DEVKIT_MAX_WORKERS=1 "$spawn" lk1 fake "$t/brief.md" 2>/dev/null; rc=$?; el=$(( $(date +%s)-s0 ))
ok "a fresh per-slot lock blocks reclaim of a stale slot" '[ $rc -eq 4 ] && [ "$el" -ge 3 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- hardening 5: a slot dir without a pid file gets a 1s grace, then counts as stale
mkdir -p "$DEVKIT_DIR/run/slot.1"
s0=$(date +%s); DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=5 FAKE_ID=lk2 DEVKIT_MAX_WORKERS=1 "$spawn" lk2 fake "$t/brief.md" 2>/dev/null; rc=$?; el=$(( $(date +%s)-s0 ))
ok "a slot dir without a pid file is reclaimed after a grace" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lk2.md ] && [ "$el" -ge 1 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- hardening 6: a lock older than 5s is removed (behavior test below covers GNU/BSD stat)
mkdir -p "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"; echo 99999999 > "$DEVKIT_DIR/run/slot.1/pid"
touch -t 200001010000 "$DEVKIT_DIR/run/slot.1.lock"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=10 FAKE_ID=lk3 DEVKIT_MAX_WORKERS=1 "$spawn" lk3 fake "$t/brief.md" 2>/dev/null; rc=$?
ok "a lock older than 5s is removed and the stale slot reclaimed" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lk3.md ] && [ ! -e "$DEVKIT_DIR/run/slot.1.lock" ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- hardening 7: pid reuse is guarded by a start-time record
sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; echo "bogus" > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=10 FAKE_ID=lk4 DEVKIT_MAX_WORKERS=1 "$spawn" lk4 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "a slot with a live pid but mismatched start is reclaimed" '[ $rc -eq 0 ] && [ -s $TD/handoffs/lk4.md ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"
sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$live" > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=3 DEVKIT_MAX_WORKERS=1 "$spawn" lk5 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "a slot with a live pid and matching start is kept" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

# --- ship fixes: empty start, TZ-normalized lstart, 08 depth, worktree reuse, cap counts slots above CAP
sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; : > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=3 DEVKIT_MAX_WORKERS=1 "$spawn" lk6 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "an empty start file is treated as no record (live slot kept)" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.1" "$DEVKIT_DIR/run/slot.1.lock"

sleep 30 & live=$! # sleep-ok: live-pid fixture, the 30s guard never elapses (killed right after)
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo "$live" > "$DEVKIT_DIR/run/slot.1/pid"; LC_ALL=C TZ=UTC ps -o lstart= -p "$live" > "$DEVKIT_DIR/run/slot.1/start"
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=3 DEVKIT_MAX_WORKERS=1 TZ="Pacific/Kiritimati" "$spawn" lk7 fake "$t/brief.md" 2>/dev/null; rc=$?
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
DEVKIT_DEPTH=1 DEVKIT_CHILD_WAIT=3 DEVKIT_MAX_WORKERS=1 "$spawn" lk8 fake "$t/brief.md" 2>/dev/null; rc=$?
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
ok "slots above a lowered CAP still count (cap=1, slot.3 live)" '[ $rc -eq 4 ]'
rm -rf "$DEVKIT_DIR/run/slot.3" "$DEVKIT_DIR/run/slot.3.lock"

fresh=$(mktemp -d); (cd "$t" && DEVKIT_DIR="$fresh/.devkit" env -u DEVKIT_TASK "$spawn" q fake "$t/brief.md" 2>/dev/null); rc=$?
ok "no task creates no run dir" '[ $rc -eq 2 ] && [ ! -e "$fresh/.devkit/run" ]'
rm -rf "$fresh"

ok "no call escaped to the tripwire herdr (real herdr never reached)" '[ ! -s "$HERDR_TRIPWIRE_LOG" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
