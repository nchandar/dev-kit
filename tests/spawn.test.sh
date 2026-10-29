#!/usr/bin/env bash
# Tests for bin/spawn using a fake agent CLI (no tokens). Usage: tests/spawn.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q && echo base > f.txt && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
export HARNESS_DIR="$t/.harness"
export HARNESS_VIEW=off HARNESS_VIEW_CLOSE_DELAY=0
ledger="$here/bin/ledger"
TA=$("$ledger" start task-a x); TB=$("$ledger" start task-b y)
TD="$HARNESS_DIR/tasks/$TA"; export HARNESS_TASK=$TA

cat > "$t/fake" <<'F'
#!/usr/bin/env bash
# $1=prompt $2=handoff path. Behaviour via FAKE_* env.
if [ /dev/stdin -ef /dev/null ]; then stdin_state=null; else stdin_state=open; fi
echo "$(date +%s) start $FAKE_ID" >> "$HARNESS_DIR/events"
[ -n "${FAKE_SPAWN:-}" ] && "$FAKE_SPAWN" x fake /dev/null > "$HARNESS_DIR/nested.out" 2>&1; echo $? > "$HARNESS_DIR/nested.rc"
[ -n "${FAKE_PUSH:-}" ] && { git push origin HEAD >/dev/null 2>&1; echo $? > "$HARNESS_DIR/push.rc"; }
[ -n "${FAKE_EDIT:-}" ] && echo changed >> f.txt
sleep "${FAKE_SLEEP:-0}"
[ -n "${FAKE_NOHANDOFF:-}" ] || printf 'depth=%s cwd=%s stdin=%s\n' "${HARNESS_DEPTH:-}" "$PWD" "$stdin_state" > "$2"
echo "$(date +%s) end $FAKE_ID" >> "$HARNESS_DIR/events"
F
chmod +x "$t/fake"; export HARNESS_FAKE="$t/fake"
echo "do the thing" > "$t/brief.md"

FAKE_ID=a "$spawn" a fake "$t/brief.md"
ok "ship run writes handoff"       '[ -s $TD/handoffs/a.md ]'
ok "status is done"                'grep -q "^done 0" $TD/run/a.status'
ok "worker sees HARNESS_DEPTH=1"   'grep -q "depth=1" $TD/handoffs/a.md'

HARNESS_DEPTH=1 "$spawn" z fake "$t/brief.md" 2>/dev/null; rc=$?
ok "spawn refuses inside a worker" '[ $rc -eq 3 ]'
FAKE_ID=n FAKE_SPAWN="$spawn" "$spawn" n fake "$t/brief.md"
ok "nested spawn from worker blocked" '[ "$(cat $HARNESS_DIR/nested.rc)" = 3 ]'

"$spawn" q nosuchcli "$t/brief.md" 2>/dev/null; rc=$?
ok "unknown cli exits 2"           '[ $rc -eq 2 ]'

FAKE_ID=m FAKE_NOHANDOFF=1 "$spawn" m fake "$t/brief.md"
ok "missing handoff -> fallback + failed" 'grep -q "no handoff written" $TD/handoffs/m.md && grep -q "^failed" $TD/run/m.status'

git checkout -q f.txt
FAKE_ID=s FAKE_EDIT=1 "$spawn" --shape scout s fake "$t/brief.md"
ok "scout that edits code is flagged" 'grep -q "^violation" $TD/run/s.status'
git checkout -q f.txt

FAKE_ID=w "$spawn" --worktree w fake "$t/brief.md"
ok "worktree created on branch"    'git rev-parse --verify -q harness/$TA-w >/dev/null'
ok "worker ran inside worktree"    'grep -q "cwd=.*/wt/w" $TD/handoffs/w.md'

: > $HARNESS_DIR/events
for i in 1 2 3; do FAKE_ID=c$i FAKE_SLEEP=2 "$spawn" c$i fake "$t/brief.md" & done; wait
third=$(awk '$2=="start"{print $1}' $HARNESS_DIR/events | sort -n | tail -1)
firstend=$(awk '$2=="end"{print $1}' $HARNESS_DIR/events | sort -n | head -1)
ok "cap=2: third starts after a slot frees" '[ "$third" -ge "$firstend" ]'
ok "slots released afterwards"     '[ -z "$(ls -d $HARNESS_DIR/run/slot.* 2>/dev/null)" ]'

HARNESS_TASK=$TB FAKE_ID=a "$spawn" a fake "$t/brief.md"
ok "same worker id in another task does not collide" '[ -s "$HARNESS_DIR/tasks/$TB/handoffs/a.md" ] && [ -s $TD/handoffs/a.md ] && ! cmp -s "$HARNESS_DIR/tasks/$TB/handoffs/a.md" /dev/null'
env -u HARNESS_TASK "$spawn" q fake "$t/brief.md" 2>/dev/null; rc=$?
ok "spawn without a task exits 2"  '[ $rc -eq 2 ]'
HARNESS_TASK=$TB FAKE_ID=iso "$spawn" iso fake "$t/brief.md"
ok "spawn logs only to its own task's ledger" 'grep -q "iso done" "$HARNESS_DIR/tasks/$TB/ledger.tsv" && ! grep -q "iso" $TD/ledger.tsv'

: > $HARNESS_DIR/events
for i in 1 2 3; do tk=$TA; [ $i = 2 ] && tk=$TB; HARNESS_TASK=$tk FAKE_ID=x$i FAKE_SLEEP=2 "$spawn" x$i fake "$t/brief.md" & done; wait
third=$(awk '$2=="start"{print $1}' $HARNESS_DIR/events | sort -n | tail -1)
firstend=$(awk '$2=="end"{print $1}' $HARNESS_DIR/events | sort -n | head -1)
ok "cap=2 holds across different tasks" '[ "$third" -ge "$firstend" ]'

FAKE_ID=in "$spawn" in fake "$t/brief.md" < "$t/brief.md"
ok "worker stdin is closed (no hang on stdin)" 'grep -q "stdin=null$" $TD/handoffs/in.md'

echo dirty > "$t/predirty.txt"
FAKE_ID=pd "$spawn" --shape scout pd fake "$t/brief.md"
ok "scout not blamed for files dirty before the run" 'grep -q "^done" $TD/run/pd.status'

# --- dry-run: flag composition for the real adapters, without running them
d=$(HARNESS_DRYRUN=1 "$spawn" --model m1 d1 claude "$t/brief.md" | tr '\n' ' ')
ok "dry-run claude: -p, --model m1, permissions skipped" 'echo "$d" | grep -q -- "-p " && echo "$d" | grep -q -- "--model m1" && echo "$d" | grep -q -- "--no-session-persistence" && echo "$d" | grep -q -- "--dangerously-skip-permissions"'
d=$(HARNESS_DRYRUN=1 "$spawn" --model m2 d2 codex "$t/brief.md" | tr '\n' ' ')
ok "dry-run codex: exec, bypass approvals+sandbox, -m m2" 'echo "$d" | grep -q "exec" && echo "$d" | grep -q -- "--dangerously-bypass-approvals-and-sandbox" && ! echo "$d" | grep -q -- "workspace-write" && echo "$d" | grep -q -- "-m m2" && echo "$d" | grep -q -- "--ephemeral"'
d=$(HARNESS_MODEL=prov/m3 HARNESS_DRYRUN=1 "$spawn" d3 opencode "$t/brief.md" | tr '\n' ' ')
ok "dry-run opencode: run --auto, -m from HARNESS_MODEL" 'echo "$d" | grep -q "run" && echo "$d" | grep -q -- "--auto" && echo "$d" | grep -q -- "-m prov/m3"'
d=$(HARNESS_DRYRUN=1 "$spawn" d4 claude "$t/brief.md" | tr '\n' ' ')
ok "worker prompt forbids pushing" 'echo "$d" | grep -q "Never git push"'
d=$(HARNESS_SAFE=1 HARNESS_DRYRUN=1 "$spawn" d5 claude "$t/brief.md" | tr '\n' ' '); d6=$(HARNESS_SAFE=1 HARNESS_DRYRUN=1 "$spawn" d6 codex "$t/brief.md" | tr '\n' ' ')
ok "HARNESS_SAFE=1 restores restricted modes" 'echo "$d" | grep -q -- "--permission-mode acceptEdits" && ! echo "$d" | grep -q -- "--dangerously" && echo "$d6" | grep -q -- "-s workspace-write" && ! echo "$d6" | grep -q -- "--dangerously"'
d=$(HARNESS_DRYRUN=1 "$spawn" d4 claude "$t/brief.md" | tr '\n' ' ')
ok "worker prompt forbids starting a new task" 'echo "$d" | grep -q "Do not start a new task"'
ok "no model flag unless asked"    '! echo "$d" | grep -q -- "--model"'
ok "dry-run leaves no status files" '[ ! -e $TD/run/d1.status ] && [ -z "$(ls -d $HARNESS_DIR/run/slot.* 2>/dev/null)" ]'

# --- --prompt: no brief file needed
FAKE_ID=pp "$spawn" --prompt "inline ask" pp fake
ok "--prompt runs and saves the brief" '[ -s $TD/handoffs/pp.md ] && grep -q "inline ask" $TD/briefs/pp.md'

# --- watchdog
s0=$(date +%s); FAKE_ID=to FAKE_SLEEP=30 HARNESS_TIMEOUT=2 "$spawn" to fake "$t/brief.md"; rc=$?; el=$(( $(date +%s)-s0 ))
ok "HARNESS_TIMEOUT kills a hung worker quickly" '[ $rc -ne 0 ] && [ $el -lt 15 ]'
ok "timeout is its own status + noted in handoff" 'grep -q "^timeout" $TD/run/to.status && grep -qi "timed out" $TD/handoffs/to.md'
ok "slot released after timeout"    '[ -z "$(ls -d $HARNESS_DIR/run/slot.* 2>/dev/null)" ]'

# --- doctor, with stub CLIs on PATH
stubs="$t/stubs"; mkdir -p "$stubs"
cat > "$stubs/claude" <<'S'
#!/usr/bin/env bash
case "$1" in --version) echo "claude 9.9";; *) echo "-p --permission-mode --allowedTools --add-dir --no-session-persistence --model --dangerously-skip-permissions";; esac
S
cat > "$stubs/codex" <<'S'
#!/usr/bin/env bash
case "$1" in --version) echo "codex 8.8";; *) echo "-C -s --add-dir --skip-git-repo-check -o -m --dangerously-bypass-approvals-and-sandbox $CODEX_STUB_EXTRA";; esac
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
ok "worker push is blocked" '[ "$(cat $HARNESS_DIR/push.rc)" != 0 ] && [ "$(git -C "$t/remote.git" rev-list --all 2>/dev/null | wc -l)" -eq 0 ]'
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

HARNESS_VIEW=herdr FAKE_ID=v1 vrun "$spawn" v1 fake "$t/brief.md"
ok "view: tab labelled '<id> · <cli> · <shape>', no focus steal" 'grep -q "tab create --label v1 · fake · ship --cwd .* --no-focus" "$HERDR_LOG"'
ok "view: pane tails the worker log"            'grep -q "pane run X:p9 tail -n +1 -f .*v1.log" "$HERDR_LOG"'
ok "view: reported working, then idle"          'grep -n "report-agent" "$HERDR_LOG" | head -1 | grep -q "working" && grep "report-agent" "$HERDR_LOG" | tail -1 | grep -q "idle"'
ok "view: Agents panel gets title and display name" 'grep "report-metadata" "$HERDR_LOG" | grep -q -- "--display-agent fake ship" && grep "report-metadata" "$HERDR_LOG" | grep -q -- "--title v1"'
ok "view: no notification when all is well"      '! grep -q "notification show" "$HERDR_LOG"'
ok "view: tab closed after a successful run"    'grep -q "tab close X:t9" "$HERDR_LOG"'
ok "view: worker itself unchanged (done + handoff)" 'grep -q "^done" $TD/run/v1.status && [ -s $TD/handoffs/v1.md ]'

HARNESS_VIEW_KEEP=1 HARNESS_VIEW=herdr FAKE_ID=v2 vrun "$spawn" v2 fake "$t/brief.md"
ok "view: HARNESS_VIEW_KEEP=1 leaves the tab open" '! grep -q "tab close" "$HERDR_LOG" && grep "report-agent" "$HERDR_LOG" | tail -1 | grep -q "idle"'

HARNESS_VIEW=herdr FAKE_ID=v3 FAKE_NOHANDOFF=1 vrun "$spawn" v3 fake "$t/brief.md"
ok "view: a failed worker is reported blocked and its tab kept" 'grep "report-agent" "$HERDR_LOG" | tail -1 | grep -q "blocked" && ! grep -q "tab close" "$HERDR_LOG"'

ok "view: failure raises a notification with the request sound" 'grep "notification show" "$HERDR_LOG" | grep -q "v3" && grep "notification show" "$HERDR_LOG" | grep -q -- "--sound request"'
ok "view: the failed tab id is remembered" '[ -s $TD/run/v3.tab ]'
: > "$HERDR_LOG"; ( export PATH="$hs:$PATH"; "$spawn" --close-views )
ok "view: --close-views closes kept tabs and forgets them" 'grep -q "tab close X:t9" "$HERDR_LOG" && [ ! -e $TD/run/v3.tab ]'
HARNESS_VIEW_NOTIFY=all HARNESS_VIEW=herdr FAKE_ID=v7 vrun "$spawn" v7 fake "$t/brief.md"
ok "view: HARNESS_VIEW_NOTIFY=all also notifies on success" 'grep "notification show" "$HERDR_LOG" | grep -q -- "--sound done"'

HARNESS_VIEW=off FAKE_ID=v4 vrun "$spawn" v4 fake "$t/brief.md"
ok "view: HARNESS_VIEW=off makes no herdr calls" '[ ! -s "$HERDR_LOG" ] && grep -q "^done" $TD/run/v4.status'

HERDR_DOWN=1 HARNESS_VIEW=herdr FAKE_ID=v5 vrun "$spawn" v5 fake "$t/brief.md"
ok "view: herdr server down falls back to headless" '! grep -q "tab create" "$HERDR_LOG" && grep -q "^done" $TD/run/v5.status'

( export PATH="/usr/bin:/bin"; export HARNESS_VIEW=herdr; FAKE_ID=v6 "$spawn" v6 fake "$t/brief.md" )
ok "view: no herdr installed falls back to headless" 'grep -q "^done" $TD/run/v6.status'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
