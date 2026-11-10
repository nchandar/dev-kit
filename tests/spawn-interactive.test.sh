#!/usr/bin/env bash
# Tests for bin/spawn interactive mode (herdr tab + agent start) with a stub herdr and stub CLIs. No tokens, no real herdr.
set -u
unset DEVKIT_DEPTH DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY DEVKIT_MODE DEVKIT_POLL DEVKIT_GRACE DEVKIT_IDLE_WAIT GIT_CONFIG_COUNT
unset CLAUDE_CODE_SESSION_ID  # a developer's real session pointer must not leak into scratch repos
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && tp=$(pwd -P) && git init -q && echo base > f.txt && git add -A && git -c user.name=t -c user.email=t@t commit -qm init
git remote add origin "$t/remote.git"
export DEVKIT_DIR="$t/.devkit" DEVKIT_VIEW_CLOSE_DELAY=0 DEVKIT_POLL=1 DEVKIT_GRACE=0
TA=$("$here/bin/ledger" start inter x); TD="$DEVKIT_DIR/tasks/$TA"; export DEVKIT_TASK=$TA
echo "do the thing" > "$t/brief.md"

# stub herdr: records every call; agent prompt starts a background process that drops the handoff (STUB_DROP=seconds)
hs="$t/stub"; mkdir -p "$hs"; export HERDR_LOG="$t/herdr.log"
cat > "$hs/herdr" <<'S'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_LOG"
[ ! -e "$HERDR_LOG.dead" ] || exit 1 # STUB_DIE: herdr is gone once the prompt was sent
case "$1 $2" in
  "tab list") exit "${HERDR_DOWN:-0}";;
  "tab create") [ -z "${STUB_TAB_OUT:-}" ] || echo "$STUB_TAB_OUT" >&2; [ -z "${STUB_TAB_FAIL:-}" ] || exit 0; [ -z "${STUB_NO_PANE:-}" ] || { echo '{"result":{"tab":{"tab_id":"X:t9"}}}'; exit 0; }; echo '{"result":{"root_pane":{"pane_id":"X:p9","tab_id":"X:t9"},"tab":{"tab_id":"X:t9"}}}';;
  "agent start") [ -z "${STUB_START_OUT:-}" ] || echo "$STUB_START_OUT" >&2; exit "${STUB_START_RC:-0}";;
  "agent prompt")
    [ -z "${STUB_PROMPT_OUT:-}" ] || echo "$STUB_PROMPT_OUT" >&2
    [ -z "${STUB_PROMPT_RC:-}" ] || exit "$STUB_PROMPT_RC"
    [ -z "${STUB_DIE:-}" ] || touch "$HERDR_LOG.dead"
    pf=$(printf '%s' "$4" | sed -n 's/^Read \(.*\) and follow it.*/\1/p')
    [ -z "${STUB_EDIT:-}" ] || echo edited >> f.txt
    # STUB_FIX: the idle nudge (a prompt naming the final handoff) makes the worker finish
    if [ -n "${STUB_FIX:-}" ] && printf '%s' "$4" | grep -q "without a final handoff"; then
      fh=$(printf '%s' "$4" | sed -n 's/.* to \(\/[^ ]*\)\.$/\1/p'); printf 'fixed\n## Checklist\n- [x] 1. done\n' > "$fh"
    fi
    if [ -n "${STUB_DROP:-}" ] && [ -f "$pf" ]; then
      hf=$(sed -n 's/.*to this absolute path: \(.*\)$/\1/p' "$pf" | head -1)
      # STUB_DROP=0 writes inline, before spawn's first poll: the run ends at once instead of losing a 1 s poll
      # STUB_LATE counts from stub start (not from the drop), so keep it above STUB_DROP
      # the default handoff is final (ends with its checklist); STUB_DRAFT or STUB_LATE makes it the early partial one
      hbody='stub handoff\n## Checklist\n- [x] 1. done\n'; [ -z "${STUB_DRAFT:-}${STUB_LATE:-}" ] || hbody='stub handoff\n'
      if [ "$STUB_DROP" = 0 ]; then printf "$hbody" > "$hf"
      else ( sleep "$STUB_DROP"; printf "$hbody" > "$hf" ) >/dev/null 2>&1 & fi
      [ -z "${STUB_LATE:-}" ] || ( sleep "$STUB_LATE"; printf '\n## Checklist\n- [x] 1. done\n' >> "$hf" ) >/dev/null 2>&1 &
    fi;;
  "agent get") [ -z "${STUB_AGENT_UNKNOWN:-}" ] || exit 1; as=${STUB_AGENT_STATUS:-idle}; [ -z "${STUB_STATUS_FILE:-}" ] || [ ! -s "$STUB_STATUS_FILE" ] || as=$(cat "$STUB_STATUS_FILE")
    echo "{\"result\":{\"agent\":{\"agent_status\":\"$as\"}}}";;
  "pane get") [ -z "${STUB_GONE:-}" ] || exit 1;;
  "pane read") echo "${STUB_PANE:-last screen line}";;
esac
exit 0
S
chmod +x "$hs/herdr"
# headless stub cli: writes the handoff named in its prompt (the last argument or the one after -p)
for c in claude codex opencode; do
  cat > "$hs/$c" <<'S'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$HERDR_LOG.cli"
case "$1 $2" in
  "session delete") [ -z "${STUB_DEL_TS:-}" ] || perl -MTime::HiRes=time -e 'printf "%d\n", time*1000' >> "$STUB_DEL_TS"; echo "session delete $3" >> "$HERDR_LOG"; [ -z "${STUB_STOP_UNIQ:-}" ] || { trap "" TERM; exec sleep 997; }; [ -z "${STUB_STOP_IGNORE:-}" ] || { trap "" TERM; exec sleep 60; }; [ -z "${STUB_STOP_HANG:-}" ] || exec sleep 60; [ -z "${STUB_DEL_TS:-}" ] || perl -MTime::HiRes=time -e 'printf "%d\n", time*1000' >> "$STUB_DEL_TS"; exit "${STUB_STOP_RC:-0}";; # sleep-ok: a hung delete the spawn must cut off
esac
hf=$(printf '%s\n' "$@" | sed -n 's/.*to this absolute path: \(.*\)$/\1/p' | head -1)
[ -z "$hf" ] || printf 'headless handoff\n' > "$hf"
S
  chmod +x "$hs/$c"
done
irun() { : > "$HERDR_LOG"; rm -f "$HERDR_LOG.dead"; ( export PATH="$hs:$PATH"; "$@" ); }
# irun2 leaves the herdr log alone, so concurrent runs can share it
irun2() { ( export PATH="$hs:$PATH"; "$@" ); }
tailargs() { grep '^agent start' "$HERDR_LOG" | sed 's/^.* -- //'; }
# bounded polls replace fixed sleeps: they end as soon as the thing happens, so the wait is a guard, not a cost
waitlog() { local n=0; while [ $n -lt 200 ] && ! grep -q "$1" "${2:-$HERDR_LOG}" 2>/dev/null; do sleep 0.05; n=$((n+1)); done; } # sleep-ok: bounded poll (200 tries) for a herdr log line
waitfile() { local n=0; while [ $n -lt 200 ] && [ ! -s "$1" ]; do sleep 0.05; n=$((n+1)); done; } # sleep-ok: bounded poll (200 tries) for a non-empty file
waitcount() { local n=0 c; while [ $n -lt 200 ]; do c=$(grep -c "$1" "$2" 2>/dev/null); [ "${c:-0}" -gt "$3" ] && return 0; sleep 0.05; n=$((n+1)); done; return 1; } # sleep-ok: bounded poll (200 tries) until a log has more matching lines
gonepoll() { local n=0; while [ $n -lt 20 ] && pgrep -f "$1" >/dev/null 2>&1; do sleep 0.05; n=$((n+1)); done; } # sleep-ok: bounded poll (20 tries) until the process is gone

# --- claude: launch
STUB_DROP=0 irun "$spawn" c1 claude "$t/brief.md"; rc=$?
ok "claude: interactive run succeeds and writes the handoff" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/c1.status && [ -s $TD/handoffs/c1.md ]'
tc=$(grep '^tab create' "$HERDR_LOG")
ok "claude: tab create has cwd, label and no focus steal" 'echo "$tc" | grep -q -- "--cwd $tp" && echo "$tc" | grep -q -- "--label c1 · claude · ship" && echo "$tc" | grep -q -- "--no-focus"'
ok "claude: tab create carries DEVKIT_DEPTH, TASK and DIR" 'echo "$tc" | grep -q -- "--env DEVKIT_DEPTH=1" && echo "$tc" | grep -q -- "--env DEVKIT_TASK=$TA" && echo "$tc" | grep -q -- "--env DEVKIT_DIR=$DEVKIT_DIR"'
ok "claude: tab create turns on the task tools so the checklist panel exists"  'echo "$tc" | grep -q -- "--env CLAUDE_CODE_ENABLE_TODO_TOOLS=1"'
ok "claude: tab create carries the push-guard pair" 'echo "$tc" | grep -q -- "--env GIT_CONFIG_KEY_0=remote.origin.pushurl" && echo "$tc" | grep -q -- "--env GIT_CONFIG_VALUE_0=/dev/null/push-blocked-by-dev-kit" && echo "$tc" | grep -q -- "--env GIT_CONFIG_COUNT=1"'
ok "claude: agent start names the kind and pane" 'grep -q "^agent start c1 --kind claude --pane X:p9 " "$HERDR_LOG"'
ok "claude: agent start tail is interactive (no -p, skips permissions, no print-only flags)" 'a=" $(tailargs) "; case "$a" in *" -p "*) false;; *) true;; esac && echo "$a" | grep -q -- " --dangerously-skip-permissions " && ! echo "$a" | grep -q -- " --no-session-persistence "'
# every flag we pass must exist in the real CLI's interactive help (a flag that is print-mode only killed the first real launch)
realflags() { # cli: flags in the last interactive tail, each checked against `<cli> --help`; skipped when the CLI is not installed
  command -v "$1" >/dev/null 2>&1 || return 0
  local h bad=0 f; h=$("$1" --help 2>&1)
  for f in $(tailargs | tr ' ' '\n' | grep -E '^--?[A-Za-z]'); do
    printf '%s\n' "$h" | grep -qE -- "(^|[[:space:],<])$f([[:space:],>]|$)" || { echo "missing in $1 --help: $f" >&2; bad=1; continue; }
    blk=$(printf '%s\n' "$h" | awk -v f="$f" '$0 ~ "^[ ]+(-[A-Za-z], )?"f"([ ,<\\[]|$)" {p=1; print; next} p && /^  -/ {p=0} p')
    ! printf '%s' "$blk" | tr '\n' ' ' | grep -qi "only works with --print\|only works with -p" || { echo "print-only flag in $1 --help: $f" >&2; bad=1; }
  done
  return $bad; }
ok "claude: every flag in the interactive tail exists in the real claude --help" 'realflags claude'
ok "claude: the full prompt is a file, argv never carries the brief" '[ -s $TD/briefs/c1.prompt ] && grep -q "do the thing" $TD/briefs/c1.prompt && ! tailargs | grep -q "do the thing"'
ok "claude: one short prompt line points at the file" 'grep "^agent prompt" "$HERDR_LOG" | grep -q "agent prompt c1 Read $TD/briefs/c1.prompt and follow it"'
ok "claude: handoff drop closes the tab, no notification" 'grep -q "tab close X:t9" "$HERDR_LOG" && ! grep -q "notification show" "$HERDR_LOG"'
ok "claude: no log tail pane (the TUI is the view)" '! grep -q "pane run" "$HERDR_LOG"'

# --- done signal: an early, partial handoff must not end the run
STUB_DROP=0 STUB_LATE=3 STUB_AGENT_STATUS=working irun "$spawn" e1 claude "$t/brief.md"; rc=$?
ok "an early handoff while the agent is still working does not finish the run" '[ $rc -eq 0 ] && grep -q "^## Checklist" $TD/handoffs/e1.md'
ok "the tab stays open until the checklist lands, then closes" 'grep -q "tab close X:t9" "$HERDR_LOG"'
# an idle agent with a draft or no handoff gets one nudge, then fails (DEVKIT_IDLE_WAIT)
# the cases start here, each with its own herdr log, DEVKIT_DIR and task (slots and ledger are shared state), and run beside the later sections
# their checks are at the end of the file
TI=$(DEVKIT_DIR="$t/igd" "$here/bin/ledger" start ig x); TDI="$t/igd/tasks/$TI"
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 DEVKIT_IDLE_WAIT=1 HERDR_LOG="$t/e2.log" DEVKIT_TIMEOUT=20 STUB_DROP=0 STUB_DRAFT=1 STUB_AGENT_STATUS=idle irun2 "$spawn" e2 claude "$t/brief.md" 2>"$t/e2.err" & p1=$!
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 DEVKIT_IDLE_WAIT=1 HERDR_LOG="$t/ig1.log" DEVKIT_TIMEOUT=20 STUB_AGENT_STATUS=idle STUB_PANE="$(seq 1 25)" irun2 "$spawn" ig1 claude "$t/brief.md" 2>"$t/ig1.err" & p2=$!
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 DEVKIT_IDLE_WAIT=1 HERDR_LOG="$t/ig3.log" DEVKIT_TIMEOUT=20 STUB_FIX=1 STUB_AGENT_STATUS=idle irun2 "$spawn" ig3 claude "$t/brief.md" 2>"$t/ig3.err" & p3=$!
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 DEVKIT_IDLE_WAIT=1 HERDR_LOG="$t/ig4.log" STUB_AGENT_STATUS=working DEVKIT_TIMEOUT=4 irun2 "$spawn" ig4 claude "$t/brief.md" 2>"$t/ig4.err" & p4=$!
# ig5: idle 1.2 s, working until spawn has observed it, then idle 3.2 s; a clock that never reset would nudge
# at ~5 s, a reset one only after the timeout (8 s). The flip waits for the observed agent get, so load cannot skip the working window
echo idle > "$t/ig5.status"
( waitlog "^agent prompt ig5 " "$t/ig5.log"; sleep 1.2 # sleep-ok: the idle phase is the case's own scripted timeline
  printf 'working\n' > "$t/ig5.status.new"; mv "$t/ig5.status.new" "$t/ig5.status"
  b=$(grep -c '^agent get ig5' "$t/ig5.log" 2>/dev/null)
  waitcount '^agent get ig5' "$t/ig5.log" "${b:-0}"
  sleep 3.2; printf 'idle\n' > "$t/ig5.status.new"; mv "$t/ig5.status.new" "$t/ig5.status" ) >/dev/null 2>&1 & p6=$! # sleep-ok: 3.2 s working tail, then the second idle phase
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 HERDR_LOG="$t/ig5.log" STUB_STATUS_FILE="$t/ig5.status" DEVKIT_IDLE_WAIT=4 DEVKIT_TIMEOUT=8 irun2 "$spawn" ig5 claude "$t/brief.md" 2>"$t/ig5.err" & p5=$!
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 HERDR_LOG="$t/ig6.log" DEVKIT_TIMEOUT=20 STUB_DROP=0 STUB_DRAFT=1 STUB_AGENT_STATUS=idle DEVKIT_IDLE_WAIT=0 irun2 "$spawn" ig6 claude "$t/brief.md" 2>"$t/ig6.err" & p7=$!
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 DEVKIT_IDLE_WAIT=1 HERDR_LOG="$t/ig7.log" DEVKIT_TIMEOUT=4 STUB_AGENT_STATUS=blocked irun2 "$spawn" ig7 claude "$t/brief.md" 2>"$t/ig7.err" & p8=$!
# ig8: idle from the start with the idle deadline on the same second as the timeout: the deadline wins, never a nudge
DEVKIT_DIR="$t/igd" DEVKIT_TASK="$TI" DEVKIT_NUDGE_WAIT=0 DEVKIT_IDLE_WAIT=4 HERDR_LOG="$t/ig8.log" STUB_AGENT_STATUS=idle DEVKIT_TIMEOUT=4 irun2 "$spawn" ig8 claude "$t/brief.md" 2>"$t/ig8.err" & p9=$!
waitlog "^agent prompt ig7 " "$t/ig7.log" # ig7 runs 4 s: a live spawn holds its worker slot here
ok "idle-guard cases keep their worker slots out of the shared run dir (the INT test counts slot dirs)" '[ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'


# --- codex
STUB_DROP=0 irun "$spawn" x1 codex "$t/brief.md"; rc=$?
ok "codex: interactive run succeeds" '[ $rc -eq 0 ] && grep -q "^agent start x1 --kind codex --pane X:p9 " "$HERDR_LOG" && grep -q "tab close X:t9" "$HERDR_LOG"'
ok "codex: tail has no exec, --ephemeral, -o or --skip-git-repo-check" 'a=" $(tailargs) "; for bad in exec --ephemeral -o --skip-git-repo-check; do case "$a" in *" $bad "*) exit 1;; esac; done'
ok "codex: every flag in the interactive tail exists in the real codex --help" 'realflags codex'
ok "codex: tail has -C <wd> and bypasses approvals" 'a=" $(tailargs) "; echo "$a" | grep -q -- " -C $tp " && echo "$a" | grep -q -- " --dangerously-bypass-approvals-and-sandbox "'
ok "codex: the repo root is trusted by a -c override" 'tailargs | grep -q -F -- "-c projects.\"$tp\".trust_level=\"trusted\""'
ok "codex: tab create still carries depth and the push guard" 'grep "^tab create" "$HERDR_LOG" | grep -q -- "--env DEVKIT_DEPTH=1" && grep "^tab create" "$HERDR_LOG" | grep -q -- "--env GIT_CONFIG_VALUE_0=/dev/null/push-blocked-by-dev-kit"'
STUB_DROP=0 irun "$spawn" --model gpt-x --worktree x2 codex "$t/brief.md"
ok "codex: --model and a worktree: -m, -C worktree, both paths trusted" 'a=$(tailargs); echo "$a" | grep -q -- "-m gpt-x" && echo "$a" | grep -q -- "-C $TD/wt/x2" && echo "$a" | grep -q -F "projects.\"$TD/wt/x2\".trust_level" && echo "$a" | grep -q -F "projects.\"$tp\".trust_level"'
# codex shows the symlink-resolved git root (/private/var on macOS) in its trust prompt, so the override must name that path
ln -s "$t" "$t.lnk"
: > "$HERDR_LOG"; rm -f "$HERDR_LOG.dead"; ( export PATH="$hs:$PATH"; cd "$t.lnk" && STUB_DROP=0 "$spawn" x5 codex "$t/brief.md" ); rc=$?
ok "codex: launched from a symlinked cwd, the override names the physical root, not the link" '[ $rc -eq 0 ] && tailargs | grep -q -F "projects.\"$tp\".trust_level" && ! tailargs | grep -q -F "$t.lnk"'
STUB_DROP=0 DEVKIT_SAFE=1 irun "$spawn" x3 codex "$t/brief.md"
ok "codex: DEVKIT_SAFE uses workspace-write, not bypass" 'tailargs | grep -q -- "-s workspace-write" && ! tailargs | grep -q -- "--dangerously-bypass"'
DEVKIT_MODE=interactive DEVKIT_DRYRUN=1 irun "$spawn" x4 codex "$t/brief.md" > "$t/x4.out"
ok "codex: dry-run prints the interactive plan" 'grep -q "^agent start x4 --kind codex" "$t/x4.out"'

# --- opencode
STUB_DROP=0 irun "$spawn" o1 opencode "$t/brief.md"; rc=$?
sid_o=$(tailargs | grep -o 'ses_[A-Za-z0-9_]*' | head -1)
ok "opencode: interactive run succeeds" '[ $rc -eq 0 ] && grep -q "^agent start o1 --kind opencode --pane X:p9 " "$HERDR_LOG" && grep -q "tab close X:t9" "$HERDR_LOG"'
ok "opencode: tail is --auto -s <session> with no run, -m or --standalone" 'a=" $(tailargs) "; echo "$a" | grep -q -- " --auto -s ses_dk_" && [ -n "$sid_o" ] && for bad in run -m --standalone --title; do case "$a" in *" $bad "*) exit 1;; esac; done'
ok "opencode: every flag in the interactive tail exists in the real opencode --help" 'realflags opencode'
ok "opencode: without a model no config env is set" '! grep "^tab create" "$HERDR_LOG" | grep -q OPENCODE_CONFIG_CONTENT'
ok "opencode: tab create still carries depth and the push guard" 'grep "^tab create" "$HERDR_LOG" | grep -q -- "--env DEVKIT_DEPTH=1" && grep "^tab create" "$HERDR_LOG" | grep -q -- "--env GIT_CONFIG_COUNT=1"'
STUB_DROP=0 irun "$spawn" --model prov/m1 o2 opencode "$t/brief.md"
ok "opencode: the model travels as OPENCODE_CONFIG_CONTENT in the tab env" 'grep "^tab create" "$HERDR_LOG" | grep -q -F -- "--env OPENCODE_CONFIG_CONTENT={\"model\":\"prov/m1\"}" && ! tailargs | grep -q "prov/m1"'
DEVKIT_MODE=interactive DEVKIT_DRYRUN=1 irun "$spawn" o3 opencode "$t/brief.md" > "$t/o3.out"
ok "opencode: dry-run prints the interactive plan" 'grep -q "^agent start o3 --kind opencode" "$t/o3.out"'
rm -f "$HERDR_LOG.cli"; STUB_DROP=0 irun "$spawn" od1 opencode "$t/brief.md"; rc=$?
sid_d=$(tailargs | grep -o 'ses_[A-Za-z0-9_]*' | head -1)
ok "opencode: a done run deletes its own session exactly once" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/od1.status && echo "$sid_d" | grep -q "^ses_dk_" && [ "$(grep -c "^opencode session delete $sid_d$" "$HERDR_LOG.cli" 2>/dev/null)" -eq 1 ]'
rm -f "$HERDR_LOG.cli"; STUB_STOP_RC=1 STUB_DROP=0 irun "$spawn" od2 opencode "$t/brief.md"; rc=$?
ok "opencode: a failing stop on a done run changes nothing" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/od2.status && grep -q "^opencode session delete ses_" "$HERDR_LOG.cli"'
rm -f "$HERDR_LOG.cli"; STUB_DROP=0 irun "$spawn" od3 claude "$t/brief.md"; rc=$?
ok "claude: a done run never stops an opencode session" '[ $rc -eq 0 ] && ! grep -q "session delete" "$HERDR_LOG.cli" 2>/dev/null'
rm -f "$HERDR_LOG.cli"; STUB_DROP=0 irun "$spawn" od4 codex "$t/brief.md"; rc=$?
ok "codex: a done run never stops an opencode session" '[ $rc -eq 0 ] && ! grep -q "session delete" "$HERDR_LOG.cli" 2>/dev/null'
rm -f "$HERDR_LOG.cli"; DEVKIT_TIMEOUT=1 irun "$spawn" ot1 opencode "$t/brief.md" 2>/dev/null; rc=$?
sid_t=$(grep "^agent start ot1 " "$HERDR_LOG" | grep -o 'ses_[A-Za-z0-9_]*' | head -1)
ok "opencode: a timeout stops the session with 'opencode session delete <sid>'" '[ $rc -ne 0 ] && grep -q "^timeout" $TD/run/ot1.status && echo "$sid_t" | grep -q "^ses_dk_" && grep -q "^opencode session delete $sid_t$" "$HERDR_LOG.cli"'
ok "opencode: the timeout stop runs before the tab closes" '[ $(grep -n "^session delete $sid_t$" "$HERDR_LOG" | head -1 | cut -d: -f1) -lt $(grep -n "tab close X:t9" "$HERDR_LOG" | head -1 | cut -d: -f1) ]'
rm -f "$HERDR_LOG.cli"; STUB_GONE=1 irun "$spawn" og1 opencode "$t/brief.md" 2>/dev/null; rc=$?
ok "opencode: a failed run also stops the session" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/og1.status && grep -q "^opencode session delete ses_" "$HERDR_LOG.cli"'
rm -f "$HERDR_LOG.cli"; STUB_STOP_RC=1 DEVKIT_TIMEOUT=1 irun "$spawn" of1 opencode "$t/brief.md" 2>/dev/null; rc=$?
ok "opencode: a failing stop command leaves the timeout outcome unchanged" '[ $rc -ne 0 ] && grep -q "^timeout" $TD/run/of1.status && grep -q "^opencode session delete " "$HERDR_LOG.cli" && grep -q "tab close X:t9" "$HERDR_LOG"'
rm -f "$HERDR_LOG.cli"; s0=$SECONDS; STUB_STOP_HANG=1 DEVKIT_STOP_TIMEOUT=1 DEVKIT_TIMEOUT=1 irun "$spawn" oh1 opencode "$t/brief.md" 2>/dev/null; rc=$?; el=$((SECONDS-s0))
ok "opencode: a hung session delete is cut off, the timeout outcome and tab close still happen" '[ $rc -ne 0 ] && grep -q "^timeout" $TD/run/oh1.status && grep -q "tab close X:t9" "$HERDR_LOG" && [ $el -lt 20 ]'
rm -f "$HERDR_LOG.cli"; s0=$SECONDS; STUB_STOP_HANG=1 DEVKIT_STOP_TIMEOUT=1 STUB_DROP=0 irun "$spawn" oh2 opencode "$t/brief.md" 2>/dev/null; rc=$?; el=$((SECONDS-s0))
ok "opencode: a hung session delete on a done run is cut off and the run stays done" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/oh2.status && [ $el -lt 20 ]'
rm -f "$HERDR_LOG.cli"; s0=$SECONDS; STUB_STOP_IGNORE=1 DEVKIT_STOP_TIMEOUT=1 DEVKIT_TIMEOUT=1 irun "$spawn" oh3 opencode "$t/brief.md" 2>/dev/null; rc=$?; el=$((SECONDS-s0))
ok "opencode: a session delete that ignores TERM is KILLed, not waited on forever" '[ $rc -ne 0 ] && grep -q "^timeout" $TD/run/oh3.status && grep -q "tab close X:t9" "$HERDR_LOG" && [ $el -lt 20 ]'
# a signal while stop_session waits must not leave the delete behind (the 997 s sleep is unique to these stubs)
waitdelete() { local n=0; while [ $n -lt 200 ] && ! grep -q "session delete" "$HERDR_LOG.cli" 2>/dev/null; do sleep 0.05; n=$((n+1)); done; } # sleep-ok: bounded poll: the delete starts in ms, the cap is only a guard
pkill -KILL -f "sleep 997" 2>/dev/null
: > "$HERDR_LOG"; rm -f "$HERDR_LOG.cli"
( export PATH="$hs:$PATH" STUB_DROP=0 STUB_STOP_UNIQ=1 DEVKIT_STOP_TIMEOUT=30; exec "$spawn" os1 opencode "$t/brief.md" ) 2>/dev/null &
sp=$!; waitdelete; kill -TERM $sp; wait $sp 2>/dev/null; gonepoll "sleep 997" # the reap runs in spawn's EXIT trap; poll it instead of a fixed second
ok "TERM during the done-run session delete: no delete process survives" '! pgrep -f "sleep 997" >/dev/null'
pkill -KILL -f "sleep 997" 2>/dev/null
: > "$HERDR_LOG"; rm -f "$HERDR_LOG.cli"
( export PATH="$hs:$PATH" STUB_STOP_UNIQ=1 DEVKIT_STOP_TIMEOUT=30; exec "$spawn" os2 opencode "$t/brief.md" ) 2>/dev/null &
sp=$!; waitlog "^agent prompt os2 "; kill -TERM $sp; waitdelete; kill -TERM $sp; wait $sp 2>/dev/null; gonepoll "sleep 997" # first TERM starts cleanup, the second lands in its delete wait
ok "second TERM during the cleanup session delete: no delete process survives" '! pgrep -f "sleep 997" >/dev/null'
pkill -KILL -f "sleep 997" 2>/dev/null
mkdir -p "$t/ms"; cat > "$t/ms/now" <<'S'
#!/usr/bin/env bash
perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'
S
chmod +x "$t/ms/now"
# time the delete directly: two whole runs are quantized by the poll loop, so their difference jumps by a whole poll.
# The poll is 8 s here so a poll after the delete costs 8 s while normal exit work is ~0.1 s: the 4 s bound
# then sits far from both, and a slow or noisy runner cannot tip it
rm -f "$HERDR_LOG.cli" "$t/del.ts"; STUB_DEL_TS="$t/del.ts" STUB_DROP=0 DEVKIT_POLL=8 irun "$spawn" os3 opencode "$t/brief.md" 2>/dev/null; rc=$?; s1=$("$t/ms/now")
d0=$(sed -n 1p "$t/del.ts" 2>/dev/null); d1=$(sed -n 2p "$t/del.ts" 2>/dev/null)
echo "     timing: delete took $((d1-d0)) ms, spawn exited $((s1-d1)) ms after the delete ended"
ok "an instant session delete returns at once (under 600 ms)" '[ $rc -eq 0 ] && [ -n "$d0" ] && [ -n "$d1" ] && [ $((d1-d0)) -lt 600 ]'
ok "a done run exits within 4 s of its session delete ending, with an 8 s poll (no poll after it)" '[ -n "$d1" ] && [ $((s1-d1)) -lt 4000 ]'
rm -f "$HERDR_LOG.cli"; DEVKIT_TIMEOUT=1 irun "$spawn" ct1 claude "$t/brief.md" 2>/dev/null
ok "claude: a timeout stops no opencode session" '! grep -q "session delete" "$HERDR_LOG.cli" 2>/dev/null'
rm -f "$HERDR_LOG.cli"; DEVKIT_TIMEOUT=1 irun "$spawn" xt1 codex "$t/brief.md" 2>/dev/null
ok "codex: a timeout stops no opencode session" '! grep -q "session delete" "$HERDR_LOG.cli" 2>/dev/null'
: > "$HERDR_LOG"; rm -f "$HERDR_LOG.cli"
( export PATH="$hs:$PATH"; exec "$spawn" oi1 opencode "$t/brief.md" ) 2>/dev/null &
sp=$!; waitlog "^agent prompt oi1 "; kill -TERM $sp; wait $sp 2>/dev/null; waitlog "tab close X:t9" # poll until the tab exists and the cleanup closed it
sid_i=$(grep "^agent start oi1 " "$HERDR_LOG" | grep -o 'ses_[A-Za-z0-9_]*' | head -1)
ok "TERM: an interrupted opencode session is stopped before the tab closes" 'grep -q "^opencode session delete $sid_i$" "$HERDR_LOG.cli" && [ $(grep -n "^session delete $sid_i$" "$HERDR_LOG" | head -1 | cut -d: -f1) -lt $(grep -n "tab close X:t9" "$HERDR_LOG" | head -1 | cut -d: -f1) ]'

# --- doctor: the opencode todo panel needs experimental.todo in the global config
ds="$t/docstubs"; mkdir -p "$ds"
cat > "$ds/opencode" <<'S'
#!/usr/bin/env bash
case "$1" in
  --version) echo "7.7";;
  service) echo "http://127.0.0.1:1";;
  run) echo "  --auto  -m  -s  --title";;
esac
S
chmod +x "$ds/opencode"
docout() { ( export PATH="$ds:/usr/bin:/bin" HOME="$1"; "$spawn" --doctor 2>&1 ); }
mkcfg() { mkdir -p "$t/$1/.config/opencode"; [ -z "${3:-}" ] || printf '%s\n' "$3" > "$t/$1/.config/opencode/$2"; }
mkcfg h1 opencode.jsonc '{"experimental": {"todo": true}}'
mkcfg h2 opencode.jsonc '{"model": "x"}'
mkcfg h3 opencode.jsonc '// comment
{"experimental": {"todo": true}}'
mkcfg h4 opencode.json '{"experimental":{"todo":true}}'
mkcfg h5 opencode.jsonc '{"experimental": {"todo": false}}'
mkdir -p "$t/h6"
ok "doctor: experimental.todo set -> no todo warning" '! docout "$t/h1" | grep -q "experimental.todo"'
ok "doctor: config without it -> WARN naming experimental.todo" 'docout "$t/h2" | grep -q "WARN.*experimental.todo"'
ok "doctor: a commented opencode.jsonc with it set is accepted" '! docout "$t/h3" | grep -q "experimental.todo"'
ok "doctor: plain opencode.json is read too" '! docout "$t/h4" | grep -q "experimental.todo"'
ok "doctor: todo false -> WARN" 'docout "$t/h5" | grep -q "WARN.*experimental.todo"'
ok "doctor: no config at all -> WARN" 'docout "$t/h6" | grep -q "WARN.*experimental.todo"'
ok "doctor: the todo warning does not fail the exit code" '( export PATH="$ds:/usr/bin:/bin" HOME="$t/h2"; "$spawn" --doctor >/dev/null 2>&1 )'

# --- gate
STUB_DROP=0 irun "$spawn" --model opus c2 claude "$t/brief.md"
ok "claude: --model reaches agent start" 'tailargs | grep -q -- "--model opus"'
STUB_DROP=0 DEVKIT_SAFE=1 irun "$spawn" c3 claude "$t/brief.md"
ok "claude: DEVKIT_SAFE keeps the restricted mode" 'tailargs | grep -q -- "--permission-mode acceptEdits" && ! tailargs | grep -q -- "--dangerously-skip-permissions"'
DEVKIT_MODE=headless irun "$spawn" c4 claude "$t/brief.md"
ok "gate: DEVKIT_MODE=headless never starts an agent in a tab" '! grep -q "^agent " "$HERDR_LOG" && grep -q "^done" $TD/run/c4.status'
HERDR_DOWN=1 irun "$spawn" c5 claude "$t/brief.md"
ok "gate: herdr down falls back to headless" '! grep -q "tab create" "$HERDR_LOG" && grep -q "^done" $TD/run/c5.status'
HERDR_DOWN=1 DEVKIT_MODE=interactive irun "$spawn" c6 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "gate: DEVKIT_MODE=interactive without herdr exits 2" '[ $rc -eq 2 ]'
# print-only entry points must never reach an interactive tail, whatever the cli or options
for c in claude codex opencode; do
  STUB_DROP=0 DEVKIT_SAFE=1 irun "$spawn" --model m-x pf-$c $c "$t/brief.md"
  ok "$c: no -p, --print, exec or run in the interactive tail" 'a=" $(tailargs) "; for bad in -p --print exec run --output-format; do case "$a" in *" $bad "*) exit 1;; esac; done'
done
DEVKIT_MODE=sideways irun "$spawn" c7 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "gate: a bad DEVKIT_MODE exits 2" '[ $rc -eq 2 ]'
cat > "$t/fake" <<'F'
#!/usr/bin/env bash
echo ok > "$2"
F
chmod +x "$t/fake"
DEVKIT_FAKE="$t/fake" irun "$spawn" f1 fake "$t/brief.md"
ok "gate: the fake cli stays headless even with herdr up" '! grep -q "^agent " "$HERDR_LOG" && grep -q "^done" $TD/run/f1.status'

# --- failure paths
DEVKIT_TIMEOUT=1 irun "$spawn" t1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "timeout: state is timeout, .timedout written, exit non-zero" '[ $rc -ne 0 ] && grep -q "^timeout" $TD/run/t1.status && [ -e $TD/run/t1.timedout ]'
ok "timeout: the user is notified, then the tab is closed (no stale tab)" 'grep "notification show" "$HERDR_LOG" | grep -q "t1 timeout" && grep -q "tab close X:t9" "$HERDR_LOG" && [ ! -e $TD/run/t1.tab ] && [ $(grep -n "notification show" "$HERDR_LOG" | head -1 | cut -d: -f1) -lt $(grep -n "tab close" "$HERDR_LOG" | head -1 | cut -d: -f1) ]'
ok "timeout: a stub handoff carries the pane read" 'grep -q "last screen line" $TD/handoffs/t1.md'
STUB_GONE=1 irun "$spawn" g1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "pane gone with no handoff is failed, with a pane-read stub" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/g1.status && grep -q "pane gone" $TD/handoffs/g1.md'
ok "pane gone: the tab is still closed" 'grep -q "tab close X:t9" "$HERDR_LOG"'
STUB_AGENT_UNKNOWN=1 DEVKIT_TIMEOUT=30 irun "$spawn" u1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "agent unknown with the pane open and no handoff is failed after a few polls, not a timeout" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/u1.status && [ ! -e $TD/run/u1.timedout ] && grep -q "agent gone" $TD/handoffs/u1.md && grep -q "last screen line" $TD/handoffs/u1.md && grep -q "tab close X:t9" "$HERDR_LOG"'
STUB_NO_PANE=1 irun "$spawn" n3 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "tab create with a tab_id but no pane closes that tab, then fails loudly" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/n3.status && grep -q "tab close X:t9" "$HERDR_LOG" && ! grep -q "^agent " "$HERDR_LOG"'
DEVKIT_VIEW_KEEP=1 DEVKIT_TIMEOUT=1 irun "$spawn" t2 claude "$t/brief.md" 2>/dev/null
ok "timeout with DEVKIT_VIEW_KEEP: tab kept and recorded" '! grep -q "tab close" "$HERDR_LOG" && [ -s $TD/run/t2.tab ]'
DEVKIT_VIEW_KEEP=1 STUB_START_RC=1 irun "$spawn" s2 claude "$t/brief.md" 2>/dev/null
ok "failure with DEVKIT_VIEW_KEEP: tab kept and recorded" '! grep -q "tab close" "$HERDR_LOG" && [ -s $TD/run/s2.tab ]'
rm -f "$HERDR_LOG.cli"; STUB_TAB_FAIL=1 irun "$spawn" n1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "tab create failure with herdr up is a loud failure, never a quiet headless run" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/n1.status && [ ! -e "$HERDR_LOG.cli" ] && ! grep -q "^agent " "$HERDR_LOG" && grep -q "tab create failed" $TD/handoffs/n1.md'
STUB_TAB_FAIL=1 irun "$spawn" n2 claude "$t/brief.md" 2>"$t/n2.err"
ok "tab create failure says so on stderr" 'grep -q "not started" "$t/n2.err"'
STUB_START_RC=1 irun "$spawn" s1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "agent start failure (not ready) is failed fast, notified, tab closed, pane read in the stub" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/s1.status && grep "notification show" "$HERDR_LOG" | grep -q "s1 failed" && ! grep -q "^agent prompt" "$HERDR_LOG" && grep -q "tab close X:t9" "$HERDR_LOG" && grep -q "last screen line" $TD/handoffs/s1.md'

# --- D: a failing herdr call keeps its own error before the generic hint; a silent one keeps the old text
STUB_START_RC=1 STUB_START_OUT='boom: x' irun "$spawn" se1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "agent start failure keeps herdr's own error in the handoff before the hint" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/se1.status && grep -q "agent start failed: boom: x; claude not ready" $TD/handoffs/se1.md'
STUB_PROMPT_RC=1 STUB_PROMPT_OUT='boom: p' irun "$spawn" pe1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "agent prompt failure keeps herdr's own error in the handoff before the hint" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/pe1.status && grep -q "agent prompt rejected: boom: p; agent blocked or gone" $TD/handoffs/pe1.md'
STUB_TAB_FAIL=1 STUB_TAB_OUT='boom: t' irun "$spawn" te1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "tab create failure keeps herdr's own error in the handoff before the hint" '[ $rc -ne 0 ] && grep -q "tab create failed: boom: t; herdr answered but gave no pane" $TD/handoffs/te1.md'
STUB_START_RC=1 irun "$spawn" se2 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "a silent agent start failure keeps today's message exactly" '[ $rc -ne 0 ] && grep -qxF "agent start failed: claude not ready (trust dialog, login or update prompt?)" $TD/handoffs/se2.md'
STUB_PROMPT_RC=1 irun "$spawn" pe2 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "a silent agent prompt failure keeps today's message exactly" '[ $rc -ne 0 ] && grep -qxF "agent prompt rejected (agent blocked or gone)" $TD/handoffs/pe2.md'
long=$(i=1; while [ $i -le 50 ]; do echo "line: $i boom"; i=$((i+1)); done)
STUB_START_RC=1 STUB_START_OUT="$long" irun "$spawn" se3 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "a 50-line herdr error is trimmed to a few hundred chars" '[ $rc -ne 0 ] && grep -q "agent start failed: line: 1 boom" $TD/handoffs/se3.md && ! grep -q "line: 11 boom" $TD/handoffs/se3.md && [ $(grep "agent start failed: " $TD/handoffs/se3.md | wc -c) -lt 600 ]'

STUB_DROP=0 DEVKIT_VIEW_KEEP=1 irun "$spawn" k1 claude "$t/brief.md"
ok "DEVKIT_VIEW_KEEP=1 keeps the tab after success" '! grep -q "tab close" "$HERDR_LOG" && [ -s $TD/run/k1.tab ]'
STUB_DROP=0 irun "$spawn" --shape scout sv claude "$t/brief.md" >/dev/null 2>&1; rc=$?
ok "scout run in interactive mode finishes done" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/sv.status'

STUB_EDIT=1 STUB_DROP=0 irun "$spawn" --shape scout sw claude "$t/brief.md" >/dev/null 2>&1; rc=$?; git checkout -q f.txt
ok "scout that changes files in a tab is a ledger warning, not a violation" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/sw.status && grep -q "sw scout changed files" $TD/ledger.tsv'
: > "$HERDR_LOG"
( export PATH="$hs:$PATH"; exec "$spawn" i1 claude "$t/brief.md" ) 2>/dev/null &
sp=$!; waitlog "^agent prompt i1 "; kill -TERM $sp; wait $sp 2>/dev/null; waitlog "tab close X:t9" # poll until the tab exists and the cleanup closed it
ok "TERM: killed spawn writes a pane-read stub, notifies, then closes the tab" 'grep -q "last screen line" $TD/handoffs/i1.md && grep "notification show" "$HERDR_LOG" | grep -q "i1 killed" && [ $(grep -n "notification show" "$HERDR_LOG" | head -1 | cut -d: -f1) -lt $(grep -n "tab close" "$HERDR_LOG" | head -1 | cut -d: -f1) ]'
ok "interrupted interactive spawn closes its tab, records killed and frees its slot" 'grep -q "tab close X:t9" "$HERDR_LOG" && grep -q "^killed" $TD/run/i1.status && [ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'
: > "$HERDR_LOG"
# a plain async job ignores SIGINT; perl restores the default so spawn's INT trap can fire
( export PATH="$hs:$PATH"; exec perl -e '$SIG{INT}="DEFAULT"; exec @ARGV' "$spawn" i2 claude "$t/brief.md" ) 2>/dev/null &
sp=$!; waitlog "^agent prompt i2 "; kill -INT $sp; wait $sp 2>/dev/null; waitlog "tab close X:t9" # poll until the tab exists and the cleanup closed it
ok "INT (cancelled): tab closed, killed recorded, slot freed" 'grep -q "tab close X:t9" "$HERDR_LOG" && grep -q "^killed" $TD/run/i2.status && [ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'
: > "$HERDR_LOG"
( export PATH="$hs:$PATH" DEVKIT_VIEW_KEEP=1; exec "$spawn" i3 claude "$t/brief.md" ) 2>/dev/null &
sp=$!; waitlog "^agent prompt i3 "; kill -TERM $sp; wait $sp 2>/dev/null; waitfile "$TD/run/i3.tab" # poll until the kept tab is recorded
ok "TERM with DEVKIT_VIEW_KEEP: tab kept and recorded" '! grep -q "tab close" "$HERDR_LOG" && [ -s $TD/run/i3.tab ]'

# --- C: default selection. Interactive when herdr is up; headless only for herdr down, DEVKIT_MODE=headless, DEVKIT_VIEW=off or the fake cli
for c in claude codex opencode; do
  rm -f "$HERDR_LOG.cli"; HERDR_DOWN=1 irun "$spawn" hd-$c $c "$t/brief.md" 2>/dev/null; rc=$?
  ok "select: $c with herdr down runs headless" '[ $rc -eq 0 ] && ! grep -q "^agent \|^tab create" "$HERDR_LOG" && grep -q "^$c " "$HERDR_LOG.cli"'
done
rm -f "$HERDR_LOG.cli"; DEVKIT_MODE=headless irun "$spawn" hm1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "select: DEVKIT_MODE=headless with herdr up runs headless" '[ $rc -eq 0 ] && ! grep -q "^agent " "$HERDR_LOG" && grep -q "^claude " "$HERDR_LOG.cli"'
rm -f "$HERDR_LOG.cli"; DEVKIT_VIEW=off irun "$spawn" hv1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "select: DEVKIT_VIEW=off runs headless" '[ $rc -eq 0 ] && ! grep -q "^agent " "$HERDR_LOG" && grep -q "^claude " "$HERDR_LOG.cli"'
HERDR_DOWN=1 DEVKIT_MODE=interactive irun "$spawn" hi1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "select: DEVKIT_MODE=interactive with herdr down exits 2, runs nothing" '[ $rc -eq 2 ]'
STUB_DROP=0 irun "$spawn" ha1 claude "$t/brief.md"
ok "select: the default (auto) with herdr up is interactive" 'grep -q "^agent start ha1 " "$HERDR_LOG"'
rm -f "$HERDR_LOG.cli"; STUB_START_RC=1 irun "$spawn" hs1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "select: a launch failure with herdr up never falls back to headless" '[ $rc -ne 0 ] && [ ! -e "$HERDR_LOG.cli" ] && grep -q "^failed" $TD/run/hs1.status'

# --- E: the checklist instruction rides in the short prompt line, and a missing task list gets one nudge
STUB_DROP=0 irun "$spawn" p1 claude "$t/brief.md"
pl=$(grep '^agent prompt p1' "$HERDR_LOG")
ok "prompt line: names the file, 'before any other tool call' and every todo tool" 'echo "$pl" | grep -q "Read $TD/briefs/p1.prompt and follow it" && echo "$pl" | grep -q "before any other tool call" && for w in TaskCreate TodoWrite update_plan todowrite; do echo "$pl" | grep -q "$w" || exit 1; done'
ok "prompt line: still one line" '[ $(echo "$pl" | wc -l) -eq 1 ]'
STUB_DROP=2 DEVKIT_NUDGE_WAIT=1 irun "$spawn" nu1 claude "$t/brief.md"
ok "nudge: no task list on screen -> the instruction is re-sent exactly once" '[ $(grep -c "^agent prompt nu1 " "$HERDR_LOG") -eq 2 ] && grep "^agent prompt nu1 " "$HERDR_LOG" | tail -1 | grep -q "TodoWrite"'
ok "nudge: ledgered" 'grep -q "nu1 nudge" $TD/ledger.tsv'
ok "nudge: the pane was read before nudging" 'grep -q "^pane read" "$HERDR_LOG"'
STUB_DROP=2 DEVKIT_NUDGE_WAIT=1 STUB_PANE="☐ 1. Skim library" irun "$spawn" nu2 claude "$t/brief.md"
ok "nudge: a task list on screen -> no nudge" '[ $(grep -c "^agent prompt nu2 " "$HERDR_LOG") -eq 1 ] && ! grep -q "nu2 nudge" $TD/ledger.tsv'
STUB_DROP=0 DEVKIT_NUDGE_WAIT=0 irun "$spawn" nu3 claude "$t/brief.md"
ok "nudge: DEVKIT_NUDGE_WAIT=0 turns it off" '[ $(grep -c "^agent prompt nu3 " "$HERDR_LOG") -eq 1 ]'

# --- G: edge cases
printf 'quote " and \x27 and `tick` and $dollar\nsecond line\n\xc3\xa9\xe2\x82\xac \xe6\x97\xa5\xe6\x9c\xac \\backslash\n' > "$t/odd.md"
STUB_DROP=0 irun "$spawn" ed1 claude "$t/odd.md"; rc=$?
ok "edge: quotes, newlines, unicode and backslashes reach the prompt file byte for byte" '[ $rc -eq 0 ] && tail -n 3 $TD/briefs/ed1.prompt | cmp -s - "$t/odd.md" && ! tailargs | grep -q "second line"'
ok "edge: the herdr prompt line stays a single line for an odd brief" '[ $(grep -c "^agent prompt ed1 " "$HERDR_LOG") -eq 1 ] && ! grep "^agent prompt ed1" "$HERDR_LOG" | grep -q "second line"'
head -c 300000 /dev/zero | tr '\0' 'x' | fold -w 100 > "$t/long.md"
STUB_DROP=0 irun "$spawn" ed2 claude "$t/long.md"; rc=$?
ok "edge: a 300 KB brief runs; the prompt file holds it all; argv and the prompt line stay short" '[ $rc -eq 0 ] && [ $(wc -c < $TD/briefs/ed2.prompt) -gt 300000 ] && [ $(grep "^agent prompt ed2 " "$HERDR_LOG" | wc -c) -lt 1200 ] && [ $(grep "^agent start ed2 " "$HERDR_LOG" | wc -c) -lt 1500 ]'
for bad in "a b" "a/b" "a;b" 'a$b' "../x" "-x y"; do
  irun "$spawn" "$bad" claude "$t/brief.md" 2>/dev/null; rc=$?
  ok "edge: worker id '$bad' is rejected (exit 2), no herdr call" '[ $rc -eq 2 ] && [ ! -s "$HERDR_LOG" ]'
done
STUB_DROP=1 irun "$spawn" lv1 claude "$t/brief.md" >/dev/null 2>&1 &
lp=$!; waitlog "^agent prompt lv1 " # poll until the first spawn holds the id instead of a fixed 2 s
irun2 "$spawn" lv1 claude "$t/brief.md" 2>"$t/lv1.err"; rc=$?
ok "edge: a second live spawn of the same id exits 2 and does not touch herdr" '[ $rc -eq 2 ] && grep -q "already running" "$t/lv1.err" && [ $(grep -c "^tab create" "$HERDR_LOG") -eq 1 ]'
wait $lp
ok "edge: the first spawn of that id still finished" 'grep -q "^done" $TD/run/lv1.status'
STUB_DROP=0 DEVKIT_DEPTH=1 irun "$spawn" nd1 claude "$t/brief.md"
ok "edge: a nested spawn from a worker (depth 1) puts depth 2 in its tab env" 'grep "^tab create" "$HERDR_LOG" | grep -q -- "--env DEVKIT_DEPTH=2" && grep -q "at depth 2 of 3" $TD/briefs/nd1.prompt'
DEVKIT_DEPTH=3 irun "$spawn" nd2 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "edge: a worker at the depth limit cannot spawn (exit 3, no herdr call)" '[ $rc -eq 3 ] && [ ! -s "$HERDR_LOG" ]'
sp_dir="$t/dir with space"; mkdir -p "$sp_dir"
( export DEVKIT_DIR="$sp_dir"; TS=$("$here/bin/ledger" start sp x); export DEVKIT_TASK=$TS; export PATH="$hs:$PATH" STUB_DROP=0; : > "$HERDR_LOG"
  "$spawn" --worktree --shape ship sw1 codex "$t/brief.md"; echo $? > "$t/sw1.rc"; echo "$sp_dir/tasks/$TS" > "$t/sw1.td" )
TS_D=$(cat "$t/sw1.td")
ok "edge: a worktree path with spaces: run succeeds, tab cwd and codex -C carry the whole path" '[ "$(cat $t/sw1.rc)" = 0 ] && [ -d "$TS_D/wt/sw1" ] && grep "^tab create" "$HERDR_LOG" | grep -q -F -- "--cwd $TS_D/wt/sw1" && grep "^agent start sw1" "$HERDR_LOG" | grep -q -F -- "-C $TS_D/wt/sw1"'
STUB_DIE=1 irun "$spawn" hx1 claude "$t/brief.md" 2>/dev/null; rc=$?
ok "edge: herdr dying mid-run is a failed state with a reason, not a hang" '[ $rc -ne 0 ] && grep -q "^failed" $TD/run/hx1.status && [ -z "$(ls -d $DEVKIT_DIR/run/slot.* 2>/dev/null)" ]'
ok "edge: herdr dying mid-run leaves a handoff stub naming the cause" 'grep -qi "pane gone" $TD/handoffs/hx1.md'

# the idle-guard cases share this task dir and its worker slots: let them end before a section fakes slot dirs
wait $p1; r_e2=$?; wait $p2; r_ig1=$?; wait $p3; r_ig3=$?; wait $p4; wait $p5; wait $p6; wait $p7; r_ig6=$?; wait $p8; wait $p9
# --- H: review fixes
mkdir -p "$DEVKIT_DIR/run/slot.1"; echo $$ > "$DEVKIT_DIR/run/slot.1/pid" # a live holder of the only slot
DEVKIT_DEPTH=1 DEVKIT_MAX_WORKERS=1 DEVKIT_CHILD_WAIT=1 irun "$spawn" ex4 claude "$t/brief.md" 2>/dev/null; rc=$?
rm -rf "$DEVKIT_DIR/run/slot.1"
ok "early exit 4 (no free slot) is not recorded as killed" '[ $rc -eq 4 ] && ! grep -q "^killed" $TD/run/ex4.status 2>/dev/null && ! grep -q "ex4 killed" $TD/ledger.tsv && [ ! -s $TD/handoffs/ex4.md ] && ! grep -q "notification show" "$HERDR_LOG"'
STUB_DROP=0 STUB_DRAFT=1 STUB_AGENT_UNKNOWN=1 DEVKIT_TIMEOUT=1 irun "$spawn" au1 claude "$t/brief.md"; rc=$?
ok "an errored agent get counts as still working: a checklist-less handoff does not end the run" '[ $rc -ne 0 ] && grep -q "^timeout" $TD/run/au1.status'
STUB_DROP=0 STUB_AGENT_UNKNOWN=1 STUB_GONE=1 irun "$spawn" au2 claude "$t/brief.md"; rc=$?
ok "an errored agent get with the pane gone still finishes on the handoff" '[ $rc -eq 0 ] && grep -q "^done" $TD/run/au2.status'
STUB_DROP=0 irun "$spawn" --model 'a"b\c' oq1 opencode "$t/brief.md"
ok "opencode: a model with a quote and backslash is escaped in the config JSON" 'grep "^tab create" "$HERDR_LOG" | grep -q -F -- "--env OPENCODE_CONFIG_CONTENT={\"model\":\"a\\\"b\\\\c\"}"'
qd="$t/q\"d"; mkdir -p "$qd"
( export DEVKIT_DIR="$qd"; TQ=$("$here/bin/ledger" start qq x); export DEVKIT_TASK=$TQ; export PATH="$hs:$PATH" STUB_DROP=0; : > "$HERDR_LOG"
  "$spawn" --worktree --shape ship qw1 codex "$t/brief.md"; echo "$qd/tasks/$TQ" > "$t/qw1.td" )
QD=$(cat "$t/qw1.td")
ok "codex: a quote in the worktree path is escaped in the trust override" 'grep "^agent start qw1" "$HERDR_LOG" | grep -q -F "projects.\"${QD//\"/\\\"}/wt/qw1\".trust_level"'

# --- dry run
DEVKIT_MODE=interactive DEVKIT_DRYRUN=1 irun "$spawn" d1 claude "$t/brief.md" > "$t/d1.out"
ok "dry-run prints the interactive plan" 'grep -q "^tab create" "$t/d1.out" && grep -q "^agent start d1 --kind claude" "$t/d1.out" && grep -q "^agent prompt d1 Read " "$t/d1.out" && ! grep -q "^claude" "$t/d1.out"'
ok "dry-run makes no herdr calls" '[ ! -s "$HERDR_LOG" ]'

# --- idle guard results (the cases started after the done-signal section)
nudges() { grep -c "[[:space:]]$1 nudge" "$TDI/ledger.tsv"; }
ok "idle + draft handoff: nudged once, then failed, the draft kept" '[ $r_e2 -ne 0 ] && grep -q "^failed" $TDI/run/e2.status && [ $(nudges e2) -eq 1 ] && [ $(grep -c "^agent prompt e2 " "$t/e2.log") -eq 2 ] && grep -q "^stub handoff$" $TDI/handoffs/e2.md && ! grep -q "^## Checklist" $TDI/handoffs/e2.md'
ok "idle + no handoff: nudged once, then failed with the reason, no timeout wait" '[ $r_ig1 -ne 0 ] && grep -q "^failed" $TDI/run/ig1.status && [ $(nudges ig1) -eq 1 ] && grep -q "idle without final handoff" $TDI/handoffs/ig1.md'
ok "the idle nudge names the handoff path and the checklist" 'grep "^agent prompt ig1 " "$t/ig1.log" | tail -1 | grep -q "without a final handoff.*$TDI/handoffs/ig1.md"'
ok "a final handoff after the nudge ends done, nudged once" '[ $r_ig3 -eq 0 ] && grep -q "^done" $TDI/run/ig3.status && [ $(nudges ig3) -eq 1 ]'
ok "an agent that keeps working is never nudged (the timeout still applies)" 'grep -q "^timeout" $TDI/run/ig4.status && [ $(nudges ig4) -eq 0 ]'
echo "     idle-flip: status=$(cut -d' ' -f1 "$TDI/run/ig5.status" 2>/dev/null) nudges=$(nudges ig5)"
ok "idle that flips back to working resets the clock: no nudge, the timeout ends it" 'grep -q "^timeout" $TDI/run/ig5.status && [ $(nudges ig5) -eq 0 ]'
ok "an idle agent whose nudge deadline is the timeout deadline is timed out, not nudged" 'grep -q "^timeout" $TDI/run/ig8.status && [ $(nudges ig8) -eq 0 ]'
ok "a blocked agent is never nudged (no keystroke into a dialog); the timeout ends it" 'grep -q "^timeout" $TDI/run/ig7.status && [ $(nudges ig7) -eq 0 ] && [ $(grep -c "^agent prompt ig7 " "$t/ig7.log") -eq 1 ]'
ok "DEVKIT_IDLE_WAIT=0 keeps the old rule: draft + idle finishes, checklist flagged missing" '[ $r_ig6 -eq 0 ] && grep -q "^missing" $TDI/run/ig6.checklist && [ $(nudges ig6) -eq 0 ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
