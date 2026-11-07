#!/usr/bin/env bash
# Tests for tests/run-all.sh FAIL-line reporting. Usage: tests/run-all.test.sh
set -u
unset DEVKIT_DEPTH  # fixtures must pass when run from inside a worker too
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

# every real suite must be runnable the way run-all runs it (directly), with a shebang
nx=$(for f in "$here"/tests/*.test.sh; do [ -x "$f" ] || echo "${f##*/}"; done)
ok "every tests/*.test.sh is executable (run-all runs them directly)" '[ -z "$nx" ]'
nb=$(for f in "$here"/tests/*.test.sh; do head -1 "$f" | grep -q "^#!" || echo "${f##*/}"; done)
ok "every tests/*.test.sh starts with a shebang" '[ -z "$nb" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
