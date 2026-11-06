#!/usr/bin/env bash
# Tests for evals/route.sh scoring using a fake claude (no tokens). Usage: tests/route-eval.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); ev="$here/evals/route.sh"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/claude" <<'F'
#!/usr/bin/env bash
args="$*"
case $args in *"--output-format json"*) [ -n "${FAKE_NOSID:-}" ] && { echo '{"result":"x"}'; exit 0; }; echo '{"session_id":"s1","result":"route: dev-research, standard"}'; exit 0;; esac
case $args in *"--resume"*) echo "an answer"; [ -n "${FAKE_FOOTER:-}" ] && echo "route: dev-research, step 2/6, next: x"; exit 0;; esac
[ -z "${FAKE_BLIND:-}" ] && while IFS=$'\t' read -r exp req; do case $args in *"$req"*) echo "route: $exp, standard"; exit 0;; esac; done < "$CASES"
echo "route: none, trivial"
F
chmod +x "$t/claude";
cat > "$t/opencode" <<'F'
#!/usr/bin/env bash
# fake opencode: run [-m model] [-s id] <message>; logs the argv so the test can check the model flag
echo "$*" >> "$OC_LOG"
args="$*"
# real opencode prints shell tool output on stderr; repo files contain sample route lines
[ -n "${FAKE_OC_NOISE:-}" ] && echo "route: dev-research, step 1/6, next: x" >&2
# the real opencode rejects session ids that do not start with "ses"
prev=""; for a in "$@"; do [ "$prev" = -s ] && case $a in ses*) ;; *) echo 'Error: Expected a string starting with "ses"'; exit 1;; esac; prev=$a; done
case $args in *"step 1 of 6"*) echo "route: dev-research, step 1/6, next: x"; exit 0;; esac
[ -z "${FAKE_BLIND:-}" ] && while IFS=$'\t' read -r exp req; do case $args in *"$req"*) echo "route: $exp, standard"; exit 0;; esac; done < "$CASES"
case $args in *"-s ses_eval"*) echo "an answer"; [ -n "${FAKE_FOOTER:-}" ] && echo "route: dev-research, step 2/6, next: x"; exit 0;; esac
echo "route: none, trivial"
F
chmod +x "$t/opencode"; export OC_LOG="$t/oc.log"
 export EVAL_CLAUDE="$t/claude" CASES="$here/evals/route.cases"

out=$("$ev" --list 2>&1)
ok "list reports 31 routing cases and 3 drift scenarios" 'printf "%s\n" "$out" | tail -1 | grep -q "31 routing cases, 3 drift scenarios"'
out=$(FAKE_FOOTER=1 "$ev" 2>&1); rc=$?
ok "perfect agent scores 31/31 and 6/6, exit 0"          '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "routing 31/31" && printf "%s" "$out" | grep -q "drift 6/6"'
out=$(FAKE_BLIND=1 FAKE_FOOTER=1 "$ev" 2>&1); rc=$?
ok "agent that always says none scores 5/31, exit 1"     '[ $rc -eq 1 ] && printf "%s" "$out" | grep -q "routing 5/31"'
out=$("$ev" 2>&1); rc=$?
ok "missing footer scores drift 0/6, exit 1"             '[ $rc -eq 1 ] && printf "%s" "$out" | grep -q "drift 0/6"'
out=$(FAKE_NOSID=1 FAKE_FOOTER=1 "$ev" 2>&1); rc=$?
ok "no session id fails both drift turns with a reason"  '[ $rc -eq 1 ] && printf "%s" "$out" | grep -q "drift 0/6" && printf "%s" "$out" | grep -q "no session id"'
out=$(: > "$OC_LOG"; EVAL_AGENT=opencode EVAL_OPENCODE="$t/opencode" EVAL_MODEL=opencode/muse-spark-1.3 FAKE_FOOTER=1 "$ev" 2>&1); rc=$?
ok "opencode agent: perfect fake scores 31/31 and 6/6"   '[ $rc -eq 0 ] && [ -s "$OC_LOG" ] && printf "%s" "$out" | grep -q "routing 31/31" && printf "%s" "$out" | grep -q "drift 6/6"'
ok "opencode agent: passes -m model and a named session"  'grep -q -- "-m opencode/muse-spark-1.3" "$OC_LOG" && grep -q -- "-s ses_eval" "$OC_LOG"'
ok "opencode routing prompt allows only the skill tool"   'grep -q "use only the skill tool" "$OC_LOG"'
ok "live progress lines are printed as cases finish"      'printf "%s" "$out" | grep -c "^PASS" | awk "{exit !(\$1>=60)}"'
out=$(: > "$OC_LOG"; EVAL_AGENT=opencode EVAL_OPENCODE="$t/opencode" FAKE_OC_NOISE=1 FAKE_FOOTER=1 "$ev" 2>&1); rc=$?
ok "opencode: stderr tool noise never decides the route"    '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "routing 31/31" && printf "%s" "$out" | grep -q "drift 6/6"'
out=$(: > "$OC_LOG"; EVAL_AGENT=opencode EVAL_OPENCODE="$t/opencode" FAKE_OC_NOISE=1 "$ev" 2>&1); rc=$?
ok "opencode: stderr noise cannot fake a footer"            '[ $rc -eq 1 ] && printf "%s" "$out" | grep -q "drift 0/6"'
out=$(EVAL_ONLY=drift FAKE_FOOTER=1 "$ev" 2>&1); rc=$?
ok "EVAL_ONLY=drift skips routing and scores drift alone"  '[ $rc -eq 0 ] && printf "%s" "$out" | grep -q "routing skipped" && printf "%s" "$out" | grep -q "drift 6/6" && ! printf "%s" "$out" | grep -q "^PASS.routing"'
out=$(: > "$OC_LOG"; EVAL_AGENT=opencode EVAL_OPENCODE="$t/opencode" FAKE_FOOTER=1 "$ev" 2>&1)
ok "opencode prompts allow the skill tool"               'grep -q "skill tool" "$OC_LOG"'
ok "opencode prompts never say use no tools"             '! grep -q -i "use no tools" "$OC_LOG"'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
