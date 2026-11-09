#!/usr/bin/env bash
# Run every script suite and the budget lint. No agents, no tokens. Exit 1 if anything fails.
cd "$(dirname "$0")/.." || exit 2
unset DEVKIT_DEPTH  # these suites must pass when run from inside a worker too
export DEVKIT_VIEW=off  # no suite may open real herdr tabs; tests opting into views use their own PATH stub
# tripwire: a PATH-first fake herdr that logs and fails loudly. Suites that need
# herdr put their own stub first (see spawn.test.sh vrun), so any call reaching
# here is a leak; run-all fails if the log is non-empty.
tripdir=$(mktemp -d); trap 'rm -rf "$tripdir"' EXIT
export DEVKIT_TRIPWIRE_LOG="$tripdir/herdr-calls.log"
cat > "$tripdir/herdr" <<'S'
#!/usr/bin/env bash
echo "herdr $*" >> "$DEVKIT_TRIPWIRE_LOG"
echo "tripwire: real herdr must not be called in tests (use a PATH stub)" >&2
exit 127
S
chmod +x "$tripdir/herdr"
export PATH="$tripdir:$PATH"
fail=0
for t in tests/*.test.sh; do printf '%-26s ' "$(basename "$t")"; start=$SECONDS; out=$("$t" 2>&1); summary=$(printf '%s\n' "$out" | tail -n 1); echo "$summary   $((SECONDS-start))s"; case $summary in *" 0 failed"*) ;; *) fail=1; printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/    /' || true;; esac; done
printf '%-26s ' lint-budget; bin/lint-budget || fail=1
if [ -s "$DEVKIT_TRIPWIRE_LOG" ]; then printf '%-26s FAIL herdr called:\n' tripwire; cat "$DEVKIT_TRIPWIRE_LOG"; fail=1; else printf '%-26s ok\n' tripwire; fi
exit $fail
