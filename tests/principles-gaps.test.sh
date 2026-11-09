#!/usr/bin/env bash
# Content checks for the principles-and-gaps additions (what lint-budget cannot see). Usage: tests/principles-gaps.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); cd "$here" || exit 2
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
p=library/principles.md
ok "principles: root causes line, rule in debug-method"  "grep -qi 'root cause' $p && grep -q 'library/debug-method' $p"
ok "principles: observe first links the PR 1 file"        "grep -qi 'observe first' $p && grep -q 'deep/observe-and-test' $p"
ok "principles: deprecate and delete links the new file"  "grep -qi 'deprecate' $p && grep -q 'deep/deprecation-and-migration' $p"
ok "principles stays within 80 lines"                     "[ \$(wc -l < $p) -le 80 ]"
for d in deprecation-and-migration ci-loop launch-and-rollback; do
  f=library/deep/$d.md
  ok "deep $d exists, at most 45 lines"                   "[ -f $f ] && [ \$(wc -l < $f) -le 45 ]"
  ok "deep $d mentions bin/ledger"                        "grep -q 'bin/ledger' $f"
done
d=library/deep/deprecation-and-migration.md
ok "deprecation: Hyrum, zombie code, advisory vs compulsory, expand/contract" "grep -qi hyrum $d && grep -qi zombie $d && grep -qi advisory $d && grep -qi compulsory $d && grep -qi 'expand' $d && grep -qi 'contract' $d"
ok "decision-records points at the deprecation file"      'grep -q "deep/deprecation-and-migration" library/deep/decision-records.md'
ok "ci-loop: read failed log, fix or revert, never retry-pass" "grep -q 'log-failed' library/deep/ci-loop.md && grep -qi 'revert' library/deep/ci-loop.md && grep -qi 'retry' library/deep/ci-loop.md"
ok "launch-and-rollback: staged rollout and rollback triggers" "grep -qi 'staged' library/deep/launch-and-rollback.md && grep -qi 'rollback trigger' library/deep/launch-and-rollback.md"
ok "ci-loop and launch files are linked from a library file" "grep -q 'deep/ci-loop' library/git-ship.md && grep -q 'deep/launch-and-rollback' library/git-ship.md"
ok "explain-the-number: benchmark checklist"              "grep -qi 'did the work happen' library/deep/explain-the-number.md && grep -qi 'repeatab' library/deep/explain-the-number.md && grep -qi 'ballpark' library/deep/explain-the-number.md"
ok "encode-lessons: docs last in the fix order"           "grep -qi 'docs last' library/deep/encode-lessons.md"
ok "quality-bar: ratchet from baseline"                   "grep -qi 'ratchet' library/quality-bar.md"
ok "quality-bar: exceptions need user ok plus expiry"     "grep -qi 'exception' library/quality-bar.md && grep -qi 'expir' library/quality-bar.md"
ok "debug-method: root-cause rule (guard hides a bug, grep the pattern)" "grep -qi 'guard' library/debug-method.md && grep -qi 'grep' library/debug-method.md"
ok "lint-budget passes"                                   'bin/lint-budget >/dev/null 2>&1'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
