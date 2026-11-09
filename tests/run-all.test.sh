#!/usr/bin/env bash
# Tests for tests/run-all.sh FAIL-line reporting. Usage: tests/run-all.test.sh
set -u
unset DEVKIT_DEPTH DEVKIT_TEST_JOBS DEVKIT_TEST_CORES  # fixtures must pass from inside a worker and under DEVKIT_TEST_JOBS=1
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# skeleton dir reusing the real run-all.sh against fixture suites only
mkcase() {
  mkdir -p "$1/tests" "$1/bin"
  cp "$here/tests/run-all.sh" "$1/tests/run-all.sh"
  cat > "$1/bin/lint-budget" <<'S'
#!/usr/bin/env bash
exit 0
S
  chmod +x "$1/bin/lint-budget"
}
mkpass() {
  cat > "$1" <<'S'
#!/usr/bin/env bash
echo "ok   something good"
echo "2 passed, 0 failed"
S
  chmod +x "$1"
}
mkfail() {
  cat > "$1" <<'S'
#!/usr/bin/env bash
echo "ok   something good"
echo "FAIL fake thing is broken   [[ x = y ]]"
echo "1 passed, 1 failed"
exit 1
S
  chmod +x "$1"
}

mkcase "$t/mixed"; mkpass "$t/mixed/tests/fake-pass.test.sh"; mkfail "$t/mixed/tests/fake-fail.test.sh"
out=$("$t/mixed/tests/run-all.sh" 2>&1); rc=$?
ok "failing suite: exit code stays 1" '[ $rc -eq 1 ]'
ok "failing suite: its FAIL line is shown" 'echo "$out" | grep -q "FAIL fake thing is broken"'
ok "failing suite: FAIL line is indented under the summary" 'echo "$out" | grep -q "^    FAIL fake thing is broken"'
ok "only the FAIL line is echoed extra (passing suite prints as before)" '[ "$(echo "$out" | grep -c "^    FAIL")" -eq 1 ]'

mkcase "$t/clean"; mkpass "$t/clean/tests/fake-pass.test.sh"
out2=$("$t/clean/tests/run-all.sh" 2>&1); rc2=$?
ok "all passing: exit 0" '[ $rc2 -eq 0 ]'
ok "all passing: no extra indented lines" '! echo "$out2" | grep -q "^    "'

# per-suite seconds: integer at the end of every suite line, on pass and fail
ok "seconds printed on a passing suite line" 'echo "$out2" | grep -q "^fake-pass.test.sh .*2 passed, 0 failed   [0-9][0-9]*s$"'
ok "seconds printed on a failing suite line" 'echo "$out" | grep -q "^fake-fail.test.sh .*1 passed, 1 failed   [0-9][0-9]*s$"'
ok "seconds printed on every suite line" '[ "$(echo "$out" | grep -c "test.sh .*[0-9]s$")" -eq 2 ]'

# restructured runner prints exactly what the base runner (commit 5ac5174) printed: lines captured from it, seconds normalized, wall= dropped
mkcrash() {
  cat > "$1" <<'S'
#!/usr/bin/env bash
echo "ok   something good"
echo "boom: died before its summary"
exit 2
S
  chmod +x "$1"
}
normrun() { sed -E 's/   [0-9]+s$/   Xs/; /^wall=[0-9]+s$/d'; }
gold_mixed=$(printf '%s\n' 'fake-fail.test.sh          1 passed, 1 failed   Xs' '    FAIL fake thing is broken   [[ x = y ]]' 'fake-pass.test.sh          2 passed, 0 failed   Xs' 'lint-budget                tripwire                   ok')
gold_crash=$(printf '%s\n' 'fake-crash.test.sh         boom: died before its summary   Xs' 'lint-budget                tripwire                   ok')
pin() { # dir label: output must equal $gold, exit code 1
  nout=$("$1/tests/run-all.sh" 2>&1); nrc=$?
  nnorm=$(printf '%s\n' "$nout" | normrun)
  [ "$nnorm" = "$gold" ] || { echo "--- want ---"; printf '%s\n' "$gold"; echo "--- got ---"; printf '%s\n' "$nnorm"; }
  ok "$2: output equals the base runner's" '[ "$nnorm" = "$gold" ]'
  ok "$2: exit code is 1" '[ "$nrc" -eq 1 ]'
}
mkcase "$t/pin-mixed"; mkpass "$t/pin-mixed/tests/fake-pass.test.sh"; mkfail "$t/pin-mixed/tests/fake-fail.test.sh"
gold=$gold_mixed; DEVKIT_TEST_JOBS=1 pin "$t/pin-mixed" "serial runner, pass and fail"
mkcase "$t/pin-crash"; mkcrash "$t/pin-crash/tests/fake-crash.test.sh"
gold=$gold_crash; DEVKIT_TEST_JOBS=1 pin "$t/pin-crash" "serial runner, crash without a summary"
gold=$gold_mixed; DEVKIT_TEST_JOBS=4 pin "$t/pin-mixed" "parallel runner, pass and fail"
gold=$gold_crash; DEVKIT_TEST_JOBS=4 pin "$t/pin-crash" "parallel runner, crash without a summary"
# a summary with text after "0 failed" is still a pass, as in the base runner
mkcase "$t/pin-skip"; printf '#!/usr/bin/env bash\necho "3 passed, 0 failed (2 skipped)"\n' > "$t/pin-skip/tests/fake-skip.test.sh"; chmod +x "$t/pin-skip/tests/fake-skip.test.sh"
skout=$(DEVKIT_TEST_JOBS=1 "$t/pin-skip/tests/run-all.sh" 2>&1); skrc=$?
ok "a summary with trailing text after '0 failed' still passes" '[ "$skrc" -eq 0 ] && ! printf %s "$skout" | grep -q "^    FAIL"'

# parallel runner: jobs validation, clamp, weights order, N=4 vs N=1, wall line, missing rc, INT

val="$t/val"; mkcase "$val"; mkpass "$val/tests/fake-pass.test.sh"
for bad in 0 -3 nope 00 007; do
  verr=$(DEVKIT_TEST_JOBS=$bad "$val/tests/run-all.sh" 2>&1 >/dev/null); vrc=$?
  ok "jobs=$bad: exits 2" '[ "$vrc" -eq 2 ]'
  ok "jobs=$bad: the message names DEVKIT_TEST_JOBS" 'printf %s "$verr" | grep -q DEVKIT_TEST_JOBS'
done
verr=$(DEVKIT_TEST_CORES=many "$val/tests/run-all.sh" 2>&1 >/dev/null); vrc=$?
ok "cores=many: exits 2 and names DEVKIT_TEST_CORES" '[ "$vrc" -eq 2 ] && printf %s "$verr" | grep -q DEVKIT_TEST_CORES'
vout=$(DEVKIT_TEST_JOBS=8 "$val/tests/run-all.sh" 2>&1); vrc=$?
ok "jobs above the suite count is clamped and stays green" '[ "$vrc" -eq 0 ] && printf %s "$vout" | grep -q "^fake-pass.test.sh"'

# default concurrency: two suites that wait for each other finish only if the runner starts them together
rv="$t/rv"; mkcase "$rv"
for n in a b; do
  o=b; [ $n = b ] && o=a
  cat > "$rv/tests/fake-rv-$n.test.sh" <<S
#!/usr/bin/env bash
: > "$rv/up-$n"
i=0; while [ ! -e "$rv/up-$o" ] && [ \$i -lt \${RV_TRIES:-100} ]; do sleep 0.1; i=\$((i+1)); done # sleep-ok: bounded rendezvous (10 s, RV_TRIES tries) with the peer suite
if [ -e "$rv/up-$o" ]; then echo "2 passed, 0 failed"
else echo "FAIL the peer suite never started"; echo "1 passed, 1 failed"; exit 1
fi
S
  chmod +x "$rv/tests/fake-rv-$n.test.sh"
done
rm -f "$rv"/up-*; rvout=$(DEVKIT_TEST_CORES=2 "$rv/tests/run-all.sh" 2>&1); rvrc=$?
ok "default with 2 cores runs two suites at once" '[ "$rvrc" -eq 0 ] && ! printf %s "$rvout" | grep -q FAIL'
rm -f "$rv"/up-*; rvout=$(RV_TRIES=10 DEVKIT_TEST_CORES=1 "$rv/tests/run-all.sh" 2>&1); rvrc=$?
ok "default with 1 core stays serial (the rendezvous times out)" '[ "$rvrc" -eq 1 ] && printf %s "$rvout" | grep -q "peer suite never started"'
rm -f "$rv"/up-*; rvout=$(RV_TRIES=10 DEVKIT_TEST_CORES=8 DEVKIT_TEST_JOBS=1 "$rv/tests/run-all.sh" 2>&1); rvrc=$?
ok "DEVKIT_TEST_JOBS=1 wins over the detected cores" '[ "$rvrc" -eq 1 ] && printf %s "$rvout" | grep -q "peer suite never started"'

# weights: with 2 slots, the lightest suite (first in glob order) starts last only if the weights are applied;
# it records how many other suites had finished when it started, so the check does not race on start order
mkweighted() { # dir: a-light records finished peers; b and c hold a slot for one second, then finish
  mkcase "$1"
  cat > "$1/tests/fake-a-light.test.sh" <<'S'
#!/usr/bin/env bash
d=$(cd "$(dirname "$0")/.." && pwd)
ls "$d"/done.* 2>/dev/null | wc -l | tr -d ' ' > "$d/light.seen"
echo "1 passed, 0 failed"
S
  for h in b c; do
    cat > "$1/tests/fake-$h-heavy.test.sh" <<'S'
#!/usr/bin/env bash
d=$(cd "$(dirname "$0")/.." && pwd)
sleep 1 # sleep-ok: holds a runner slot so a later suite must wait for it
: > "$d/done.$$"
echo "1 passed, 0 failed"
S
  done
  chmod +x "$1"/tests/fake-*.test.sh
}
ord="$t/order"; mkweighted "$ord"
printf 'fake-b-heavy 30\nfake-c-heavy 20\nfake-a-light 1\n' > "$ord/tests/run-all.weights"
oout=$(DEVKIT_TEST_JOBS=2 "$ord/tests/run-all.sh" 2>&1); orc=$?
ok "weights: the lightest suite waits for a finished one (it starts last)" '[ "$(cat "$ord/light.seen" 2>/dev/null)" -ge 1 ]'
ok "weights: output lines stay in glob order" '[ "$(printf %s "$oout" | grep -o "fake-[a-z-]*.test.sh" | tr "\n" " ")" = "fake-a-light.test.sh fake-b-heavy.test.sh fake-c-heavy.test.sh " ]'
ok "weights: a run with a weights file stays green" '[ "$orc" -eq 0 ]'
ctl="$t/order-ctl"; mkweighted "$ctl"
DEVKIT_TEST_JOBS=2 "$ctl/tests/run-all.sh" >/dev/null 2>&1
ok "weights control: without a weights file the lightest suite (glob order first) starts at once" '[ "$(cat "$ctl/light.seen" 2>/dev/null)" -eq 0 ]'

eq="$t/eq"; mkcase "$eq"; mkpass "$eq/tests/fake-a.test.sh"; mkfail "$eq/tests/fake-b.test.sh"; mkcrash "$eq/tests/fake-c.test.sh"
eq1=$(DEVKIT_TEST_JOBS=1 "$eq/tests/run-all.sh" 2>&1); er1=$?
eq4=$(DEVKIT_TEST_JOBS=4 "$eq/tests/run-all.sh" 2>&1); er4=$?
ok "N=4: output equals N=1 on pass, fail and crash fixtures" '[ "$(printf %s "$eq1" | normrun)" = "$(printf %s "$eq4" | normrun)" ]'
ok "N=4: exit code equals N=1" '[ "$er1" -eq 1 ] && [ "$er4" -eq "$er1" ]'

wallc="$t/wall"; mkcase "$wallc"; mkpass "$wallc/tests/fake-pass.test.sh"
wout=$(DEVKIT_TEST_JOBS=2 "$wallc/tests/run-all.sh" 2>&1); wrc=$?
w=$(printf '%s\n' "$wout" | grep -n '^wall=' | cut -d: -f1)
wl=$(printf '%s\n' "$wout" | grep -n '^lint-budget' | cut -d: -f1)
ws=$(printf '%s\n' "$wout" | grep -n 'test.sh .*[0-9]s$' | tail -n 1 | cut -d: -f1)
ok "wall=NNs is printed with no space before the digits" 'printf %s "$wout" | grep -q "^wall=[0-9][0-9]*s$"'
ok "wall line sits after the suite lines and before lint-budget" '[ -n "$w" ] && [ "$w" -gt "$ws" ] && [ "$wl" -gt "$w" ]'
ok "wall line is not counted as a suite line by bin/verify's regex" '[ -z "$(printf %s "$wout" | grep -E " [0-9]+s$" | grep "^wall=")" ]'
ok "a green parallel run stays green" '[ "$wrc" -eq 0 ]'

envd="$t/env"; mkcase "$envd"
cat > "$envd/tests/fake-env.test.sh" <<'S'
#!/usr/bin/env bash
echo "mirror=${DEVKIT_LEDGER_MIRROR:-unset} depth=${DEVKIT_DEPTH:-unset} 0 failed"
S
chmod +x "$envd/tests/fake-env.test.sh"
eout=$(DEVKIT_LEDGER_MIRROR='echo leaked' DEVKIT_DEPTH=3 DEVKIT_TEST_JOBS=1 "$envd/tests/run-all.sh" 2>&1); erc=$?
ok "environment: DEVKIT_LEDGER_MIRROR and DEVKIT_DEPTH are unset for suites" 'printf %s "$eout" | grep -q "mirror=unset depth=unset"'
ok "environment: the run stays green" '[ "$erc" -eq 0 ]'

miss="$t/miss"; mkcase "$miss"; mkpass "$miss/tests/fake-ok.test.sh"
cat > "$miss/tests/fake-suicide.test.sh" <<'S'
#!/usr/bin/env bash
kill -KILL "$PPID"
S
chmod +x "$miss/tests/fake-suicide.test.sh"
mout=$(DEVKIT_TEST_JOBS=2 "$miss/tests/run-all.sh" 2>&1); mrc=$?
ok "missing rc: the run fails" '[ "$mrc" -eq 1 ]'
ok "missing rc: the suite line says so" 'printf %s "$mout" | grep -q "missing rc"'

# interrupt: TERM, because a script backgrounded from a non-interactive shell ignores SIGINT; N=2 and N=1 must both stop the suite child and drop the temp dir
intcase() { # label jobs
  int="$t/int-$1"; mkcase "$int"
  cat > "$int/tests/fake-slow.test.sh" <<'S'
#!/usr/bin/env bash
echo $$ > "$(cd "$(dirname "$0")/.." && pwd)/child.pid"
sleep 20 # sleep-ok: gives the interrupt test a live child to kill
echo "1 passed, 0 failed"
S
  chmod +x "$int/tests/fake-slow.test.sh"
  mkdir -p "$t/inttmp-$1"
  TMPDIR="$t/inttmp-$1" DEVKIT_TEST_JOBS=$2 "$int/tests/run-all.sh" > "$t/int-$1.out" 2>&1 &
  rpid=$!
  n=0; while [ ! -s "$int/child.pid" ]; do n=$((n+1)); [ "$n" -ge 200 ] && break; sleep 0.05 # sleep-ok: bounded wait for the fixture suite to start
  done
  cpid=$(cat "$int/child.pid" 2>/dev/null)
  kill -TERM "$rpid" 2>/dev/null
  n=0; while kill -0 "$rpid" 2>/dev/null; do n=$((n+1)); [ "$n" -ge 60 ] && break; sleep 0.05 # sleep-ok: bounded wait (3 s) for run-all to stop on TERM
  done
  rstop=1; kill -0 "$rpid" 2>/dev/null && rstop=0
  wait "$rpid" 2>/dev/null; rrc=$?
  n=0; while [ -n "$cpid" ] && kill -0 "$cpid" 2>/dev/null; do n=$((n+1)); [ "$n" -ge 60 ] && break; sleep 0.05 # sleep-ok: bounded wait for the killed child to disappear
  done
  [ -z "$cpid" ] || kill -KILL "$cpid" 2>/dev/null
  ok "TERM at N=$2: run-all stops within 3 s, while its suite still has 17 s to run" '[ "$rstop" -eq 1 ]'
  ok "TERM at N=$2: exits 130" '[ "$rrc" -eq 130 ]'
  ok "TERM at N=$2: the suite child does not survive" '[ -n "$cpid" ] && ! kill -0 "$cpid" 2>/dev/null'
  ok "TERM at N=$2: the temp dir is removed" '[ -z "$(ls -A "$t/inttmp-$1" 2>/dev/null)" ]'
}
intcase par 2
intcase ser 1

# the budget file is sourceable and holds positive integers
ok "bin/verify.budget sets suite_file_s and suite_total_s to positive integers" \
  '(suite_file_s=; suite_total_s=; . "$here/bin/verify.budget"; case $suite_file_s$suite_total_s in *[!0-9]*|"") exit 1;; esac; [ "$suite_file_s" -gt 0 ] && [ "$suite_total_s" -gt 0 ])'

# every real suite must be runnable the way run-all runs it (directly), with a shebang
nx=$(for f in "$here"/tests/*.test.sh; do [ -x "$f" ] || echo "${f##*/}"; done)
ok "every tests/*.test.sh is executable (run-all runs them directly)" '[ -z "$nx" ]'
nb=$(for f in "$here"/tests/*.test.sh; do head -1 "$f" | grep -q "^#!" || echo "${f##*/}"; done)
ok "every tests/*.test.sh starts with a shebang" '[ -z "$nb" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
