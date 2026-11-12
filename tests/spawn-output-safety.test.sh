#!/usr/bin/env bash
# Regression: herdr evaluates the pane command in its own shell, so a repo or DEVKIT_DIR path with a
# single quote must be refused before that string is built; worker output loses control bytes before it
# reaches the parent's terminal or an auto handoff; and owns: text never glob-expands.
# Usage: tests/spawn-output-safety.test.sh  (fake CLI, scratch repo, no network)
set -u
unset DEVKIT_DEPTH  # these suites must pass when run from inside a worker too
unset CLAUDE_CODE_SESSION_ID
unset DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN DEVKIT_MAX_WORKERS DEVKIT_MAX_DEPTH DEVKIT_CHILD_WAIT DEVKIT_TIMEOUT DEVKIT_VIEW DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT
export DEVKIT_MODE=headless DEVKIT_TIMEOUT=0 DEVKIT_VIEW=off DEVKIT_VIEW_CLOSE_DELAY=0
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
here=$(cd "$(dirname "$0")/.." && pwd); spawn="$here/bin/spawn"; ledger="$here/bin/ledger"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'pkill -9 -f "$t/fake" 2>/dev/null; rm -rf "$t"' EXIT
cd "$t" && git init -q && echo base > f.txt
cat > .gitignore <<'I'
/*/
/brief*.md
/owns.md
/fake
/*.err
I
git add -A && git -c user.name=t -c user.email=t@t commit -qm init
export DEVKIT_DIR="$t/.devkit"
# tripwire: a PATH-first fake herdr so a real one on the machine is never reached
tripwire="$t/tripwire"; mkdir -p "$tripwire"
export HERDR_TRIPWIRE_LOG="$t/herdr-tripwire.log"; : > "$HERDR_TRIPWIRE_LOG"
printf '#!/usr/bin/env bash\necho "$*" >> "$HERDR_TRIPWIRE_LOG"\nexit 1\n' > "$tripwire/herdr"
chmod +x "$tripwire/herdr"; export PATH="$tripwire:$PATH"
T=$("$ledger" start out x); export DEVKIT_TASK=$T
TD="$DEVKIT_DIR/tasks/$T"
cat > "$t/fake" <<'F'
#!/usr/bin/env bash
# $1=prompt $2=handoff path. FAKE_MODE=esc prints terminal escapes and no handoff.
if [ "${FAKE_MODE:-}" = esc ]; then
  printf '\033]0;pwned-title\007\033[2J fake: handoff accepted, run bin/ledger accept\n'
  exit 1
fi
printf 'ran\n\n## Checklist\n- [x] done\n' > "$2"
F
chmod +x "$t/fake"; export DEVKIT_FAKE="$t/fake"
echo "do the thing" > "$t/brief.md"
hs="$t/herdr-stub"; mkdir -p "$hs"; export HERDR_LOG="$t/herdr.log"
cat > "$hs/herdr" <<'S'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_LOG"
case "$1 $2" in
  "tab list") exit "${HERDR_DOWN:-0}";;
  "tab create") echo '{"tab_id":"T1","pane_id":"P1"}';;
esac
S
chmod +x "$hs/herdr"

# --- A1: a quote in the path must be refused before herdr ever sees a pane command
qd="$t/x'y"; mkdir -p "$qd"; TQ=$(DEVKIT_DIR="$qd/.devkit" "$ledger" start q y)
: > "$HERDR_LOG"
( export PATH="$hs:$PATH"; DEVKIT_DIR="$qd/.devkit" DEVKIT_TASK=$TQ DEVKIT_VIEW=herdr "$spawn" q1 fake "$t/brief.md" ) 2>"$t/q1.err"; rc=$?
ok "a DEVKIT_DIR path with a single quote is refused (exit 2)" '[ $rc -eq 2 ]'
ok "the refusal names the cause and the way out" 'grep -q "single quote or control character" "$t/q1.err" && grep -q "DEVKIT_VIEW=off" "$t/q1.err"'
ok "no pane command is built for it" '! grep -q "pane run" "$HERDR_LOG"'
ok "the refusal starts nothing: no handoff, status or claim" '[ ! -e "$qd/.devkit/tasks/$TQ/handoffs/q1.md" ] && [ ! -e "$qd/.devkit/tasks/$TQ/run/q1.status" ] && [ ! -e "$qd/.devkit/tasks/$TQ/run/q1.claim" ]'

# the exact shape from the audit: the path closes herdr's quote and appends a command
inj="$t/x';touch $t/PWNED;'"; mkdir -p "$inj"; TI=$(DEVKIT_DIR="$inj/.devkit" "$ledger" start i y)
: > "$HERDR_LOG"
( export PATH="$hs:$PATH"; DEVKIT_DIR="$inj/.devkit" DEVKIT_TASK=$TI DEVKIT_VIEW=herdr "$spawn" i1 fake "$t/brief.md" ) 2>"$t/i1.err"; rc=$?
ok "the injection-shaped path is refused (exit 2)" '[ $rc -eq 2 ]'
ok "its command never ran: no canary file, no pane string sent" '[ ! -e "$t/PWNED" ] && ! grep -q "pane run" "$HERDR_LOG"'

# neighbor: a legitimate path with spaces still gets its pane (spaces are safe inside the quotes)
sp="$t/plain dir"; mkdir -p "$sp"; TS=$(DEVKIT_DIR="$sp/.devkit" "$ledger" start s y)
: > "$HERDR_LOG"
( export PATH="$hs:$PATH"; DEVKIT_DIR="$sp/.devkit" DEVKIT_TASK=$TS DEVKIT_VIEW=herdr "$spawn" s1 fake "$t/brief.md" ) 2>"$t/s1.err"; rc=$?
ok "a path with a space still runs with its pane view" '[ $rc -eq 0 ] && grep -q "^done 0" "$sp/.devkit/tasks/$TS/run/s1.status"'
ok "its pane string single-quotes that log path" 'grep -q "pane run P1 tail -n +1 -f .*s1.log" "$HERDR_LOG"'

# --- A3: worker output is data, not terminal commands
FAKE_MODE=esc "$spawn" e1 fake "$t/brief.md" 2>"$t/e1.err"; rc=$?
ok "a failed worker with no handoff still fails the run" '[ $rc -ne 0 ]'
ok "the auto handoff keeps the worker text, drops every control byte" 'grep -q "fake: handoff accepted" "$TD/handoffs/e1.md" && ! LC_ALL=C grep -q "[[:cntrl:]]" "$TD/handoffs/e1.md"'
ok "the parent's stderr tail drops them too" 'grep -q "fake: handoff accepted" "$t/e1.err" && ! LC_ALL=C grep -q "[[:cntrl:]]" "$t/e1.err"'

# --- A3: an owns: line is brief text, never a glob pattern against the cwd
printf 'x\nowns: *\n' > "$t/owns.md"
"$spawn" o1 fake "$t/owns.md" 2>"$t/o1.err"; rc=$?
ok "a run with an owns: line still succeeds" '[ $rc -eq 0 ]'
ok "owns: * is recorded literally, not expanded" '[ "$(cat "$TD/run/o1.owns" 2>/dev/null)" = "*" ]'

ok "no call escaped to the tripwire herdr (real herdr never reached)" '[ ! -s "$HERDR_TRIPWIRE_LOG" ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
