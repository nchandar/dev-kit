#!/usr/bin/env bash
# Run every script suite and the budget lint. No agents, no tokens. Exit 1 if anything fails.
cd "$(dirname "$0")/.." || exit 2
unset DEVKIT_DEPTH  # these suites must pass when run from inside a worker too
fail=0
for t in tests/*.test.sh; do printf '%-26s ' "$(basename "$t")"; out=$("$t" 2>&1 | tail -1); echo "$out"; case $out in *" 0 failed"*) ;; *) fail=1;; esac; done
printf '%-26s ' lint-budget; bin/lint-budget || fail=1
exit $fail
