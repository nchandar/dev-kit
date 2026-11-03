#!/usr/bin/env bash
# Asserts the CI workflow exists and meets the brief. Usage: tests/ci.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); wf="$here/.github/workflows/test.yml"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }

ok "workflow file exists"                            '[ -f "$wf" ]'
ok "runs on pull_request"                            '[ -f "$wf" ] && grep -q "pull_request" "$wf"'
ok "runs on push to main"                            '[ -f "$wf" ] && grep -q "push" "$wf" && grep -q "main" "$wf"'
ok "matrix job tests over ubuntu and macos"          '[ -f "$wf" ] && grep -q "ubuntu-latest" "$wf" && grep -q "macos-latest" "$wf"'
ok "calls tests/run-all.sh"                          '[ -f "$wf" ] && grep -q "tests/run-all.sh" "$wf"'
ok "checkout pinned to a full commit SHA"            '[ -f "$wf" ] && grep -qE "actions/checkout@[0-9a-f]{40}( |$)" "$wf"'
ok "no floating action versions"                     '[ ! -f "$wf" ] || ! grep -qE "uses:[[:space:]]*[^ #]*@v[0-9]" "$wf"'
ok "minimal permissions (contents read)"             '[ -f "$wf" ] && grep -q "contents:[[:space:]]*read" "$wf"'
ok "concurrency cancel-in-progress"                  '[ -f "$wf" ] && grep -q "cancel-in-progress" "$wf"'
ok "timeout-minutes 20"                              '[ -f "$wf" ] && grep -q "timeout-minutes:[[:space:]]*20" "$wf"'
ok "sets git user.name and user.email"              '[ -f "$wf" ] && grep -q "user.name" "$wf" && grep -q "user.email" "$wf"'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
