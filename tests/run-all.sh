#!/usr/bin/env bash
# Run every script suite and the budget lint. No agents, no tokens. Exit 1 if anything fails.
cd "$(dirname "$0")/.." || exit 2
unset DEVKIT_DEPTH DEVKIT_LEDGER_MIRROR  # these suites must pass when run from inside a worker too

cap_jobs() { # the default cap: detected cores, at most 4 and at least 1
  c=${DEVKIT_TEST_CORES:-}
  [ -n "$c" ] || c=$(nproc 2>/dev/null)
  [ -n "$c" ] || c=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
  [ -n "$c" ] || c=$(sysctl -n hw.ncpu 2>/dev/null)
  case $c in ''|*[!0-9]*) c=1;; esac
  [ "$c" -ge 1 ] || c=1
  [ "$c" -le 4 ] || c=4
  printf '%s\n' "$c"
}
case ${DEVKIT_TEST_CORES:-1} in
  *[!0-9]*|0*) printf 'run-all: DEVKIT_TEST_CORES must be a positive integer, got %s\n' "$DEVKIT_TEST_CORES" >&2; exit 2;;
esac
njobs=${DEVKIT_TEST_JOBS:-$(cap_jobs)} # DEVKIT_TEST_JOBS=1 runs serially
case $njobs in
  ''|*[!0-9]*|0*) printf 'run-all: DEVKIT_TEST_JOBS must be a positive integer, got %s\n' "$njobs" >&2; exit 2;;
esac
export DEVKIT_VIEW=off  # no suite may open real herdr tabs; tests opting into views use their own PATH stub
# tripwire: a PATH-first fake herdr that logs and fails loudly. Suites that need
# herdr put their own stub first (see spawn.test.sh vrun), so any call reaching
# here is a leak; run-all fails if the log is non-empty.
tmp=$(mktemp -d); start_s=$SECONDS; runner_pid=
cleanup() { # kill the driver's whole process group, then drop every buffered output
  trap - INT TERM EXIT
  if [ -n "$runner_pid" ]; then
    /bin/kill -TERM -"$runner_pid" 2>/dev/null || /bin/kill -TERM "$runner_pid" 2>/dev/null
    wait "$runner_pid" 2>/dev/null
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM
export DEVKIT_TRIPWIRE_LOG="$tmp/herdr-calls.log"
cat > "$tmp/herdr" <<'S'
#!/usr/bin/env bash
echo "herdr $*" >> "$DEVKIT_TRIPWIRE_LOG"
echo "tripwire: real herdr must not be called in tests (use a PATH stub)" >&2
exit 127
S
chmod +x "$tmp/herdr"
export PATH="$tmp:$PATH"
fail=0

run_suite() { # nn path: one suite, buffered so a driver can stream its line later
  st=$SECONDS
  "$2" > "$DEVKIT_RUNALL_TMP/$1.out" 2>&1
  rc=$?
  printf '%s\n' "$rc" > "$DEVKIT_RUNALL_TMP/$1.rc"
  printf '%s\n' "$((SECONDS-st))" > "$DEVKIT_RUNALL_TMP/$1.secs"  # pitfall-ok: decimal-arith SECONDS is an integer
}
export -f run_suite
export DEVKIT_RUNALL_TMP=$tmp

print_suite() { # nn path: one line in today's format, FAIL lines indented below it
  name=${2##*/}
  if [ -f "$tmp/$1.rc" ]; then
    summary=$(tail -n 1 "$tmp/$1.out" 2>/dev/null)
    secs=$(cat "$tmp/$1.secs" 2>/dev/null); [ -n "$secs" ] || secs=0
  else # the worker died before writing its exit code
    summary="missing rc"; secs=0
  fi
  printf '%-26s %s   %ss\n' "$name" "$summary" "$secs"
  case $summary in
    *" 0 failed"*) ;;
    *) fail=1; grep '^FAIL' "$tmp/$1.out" 2>/dev/null | sed 's/^/    /' || true;;
  esac
}

runner_alive() { # a finished xargs may linger as a zombie until reaped
  [ -n "$runner_pid" ] || return 1
  command -v ps >/dev/null 2>&1 || { kill -0 "$runner_pid" 2>/dev/null; return; }
  st=$(ps -o state= -p "$runner_pid" 2>/dev/null) || return 1
  [ -n "$st" ] || return 1
  case $st in *Z*) return 1;; esac
}

wait_suite() { # nn: bounded poll for its rc file while the driver lives
  tries=0
  while [ ! -f "$tmp/$1.rc" ]; do
    tries=$((tries+1)); [ "$tries" -ge 6000 ] && return
    runner_alive || return
    sleep 0.1 # sleep-ok: short poll keeps lines streaming as suites finish
  done
}

start_order() { # $1 weights file (optional); stdin "nn path"; longest first, unknown after
  if [ -n "$1" ] && [ -s "$1" ]; then
    awk -v OFS=' ' '
      NR==FNR { if (NF>=2 && $1 !~ /^#/) w[$1]=$2; next }
      { name=$2; sub(/.*\//,"",name); sub(/\.test\.sh$/,"",name); print ((name in w) ? w[name] : 0), $1, $2 }
    ' "$1" - | sort -k1,1nr -k2,2n | cut -d' ' -f2-
  else
    cat
  fi
}

list=""; count=0
for t in tests/*.test.sh; do
  count=$((count+1)); nn=$(printf '%02d' "$count")
  list="$list$nn $t
"
done
[ "$njobs" -le "$count" ] || njobs=$count # never start more drivers than there are suites
if [ "$njobs" -le 1 ]; then # serial: stream each line as its suite finishes, exactly as before
  i=0
  for t in tests/*.test.sh; do
    i=$((i+1)); nn=$(printf '%02d' "$i")
    set -m # its own process group, killed by cleanup; plain wait returns as soon as a trapped signal arrives
    run_suite "$nn" "$t" &
    runner_pid=$!
    set +m
    wait "$runner_pid" 2>/dev/null
    runner_pid=
    print_suite "$nn" "$t"
  done
elif [ "$count" -gt 0 ]; then
  printf '%s' "$list" | start_order tests/run-all.weights > "$tmp/order"
  set -m # the driver gets its own process group so INT/TERM can kill every child
  xargs -P "$njobs" -L 1 bash -c 'run_suite "$1" "$2"' _ < "$tmp/order" &
  runner_pid=$!
  set +m
  while IFS=' ' read -r nn path; do
    [ -n "$nn" ] || continue
    wait_suite "$nn"
    print_suite "$nn" "$path"
  done <<EOF
$list
EOF
  wait "$runner_pid" 2>/dev/null
  runner_pid=
fi
printf 'wall=%ss\n' "$((SECONDS-start_s))"  # pitfall-ok: decimal-arith SECONDS is an integer
printf '%-26s ' lint-budget; bin/lint-budget || fail=1
if [ -s "$DEVKIT_TRIPWIRE_LOG" ]; then printf '%-26s FAIL herdr called:\n' tripwire; cat "$DEVKIT_TRIPWIRE_LOG"; fail=1; else printf '%-26s ok\n' tripwire; fi
exit $fail
