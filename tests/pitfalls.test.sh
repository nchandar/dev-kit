#!/usr/bin/env bash
# Bug-class guard: grep -E rules over bin/ and tests/, seeded from docs/pitfalls.md.
# Every rule has a known-bad fixture (must flag) and a known-good one (must pass).
# A real hit is fixed or carries `# pitfall-ok: <id> <why>` on its line
# (fixed sleeps in tests carry `# sleep-ok: <why>` instead).
# tests/pitfalls.test.sh itself is exempt from the src-grep and spawn-isolation
# scans: it is the registry, so it greps sources by design and never runs spawn.
# Usage: tests/pitfalls.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
guards="seq-args portable-cmd lstart-tz bounded-retry decimal-arith sleep-ok spawn-isolation src-grep tripwire"

# --- rule implementations: print offending lines, empty when clean
r_seq() { grep -rn -E '(^|[^A-Za-z0-9_.-])seq +([0-9]+ +)*["]?\$' "$@" 2>/dev/null | grep -v 'pitfall-ok: seq-args' || true; }
r_portable() { grep -rn -E '(^|[^A-Za-z0-9_.-])(stat +-(c|f)|date +-d|readlink +-f|sed +-i([^.]|$))' "$@" 2>/dev/null | grep -v 'pitfall-ok: portable-cmd' || true; }
r_lstart() { grep -rn -E 'ps +-o[^|;]*lstart' "$@" 2>/dev/null | grep -v -E 'LC_ALL=C.*TZ=UTC|TZ=UTC.*LC_ALL=C' | grep -v 'pitfall-ok: lstart-tz' || true; }
r_retry() { # flags until/while-true loops whose line plus 6 followers name no bound
  out=""
  for f in "$@"; do
    while IFS= read -r ln; do
      printf '%s\n' "$(sed -n "${ln},$((ln+6))p" "$f")" | grep -q -E 'tries|waited|count|timeout|CHILD_WAIT|sleep|exit [0-9]|break|return|pitfall-ok: bounded-retry' \
        || out="${out}${f}:${ln}: unbounded retry loop (no counter or timeout nearby)
"
    done < <(grep -n -E '(^|[^A-Za-z0-9_])(until[[:space:]]|while +(true|:)([[:space:];]|$))' "$f" 2>/dev/null | cut -d: -f1)
  done
  printf '%s' "$out"
}
r_arith() { # [ -op ] or $(( )) on $vars without 10#: operands must be decimal-safe
  { grep -rn -E '\$\(\([^)]*\$|-(eq|ne|lt|le|gt|ge)[[:space:]]+["]?\$|\$[A-Za-z_][A-Za-z0-9_]*["]?[[:space:]]+-(eq|ne|lt|le|gt|ge)|\$\{[^}]+\}["]?[[:space:]]+-(eq|ne|lt|le|gt|ge)|-(eq|ne|lt|le|gt|ge)[[:space:]]+["]?\$\{' "$@" 2>/dev/null
    grep -rn -E '\$\(\(' "$@" 2>/dev/null | grep -E -e '-(eq|ne|lt|le|gt|ge)'; } | grep -v '10#' | grep -v 'pitfall-ok: decimal-arith' | sort -u || true
}
r_sleep() { grep -rn -E '(^|[^"_A-Za-z0-9=])sleep [0-9]' "$@" 2>/dev/null | grep -v 'sleep-ok:' || true; }
r_srcgrep() { grep -rn -E 'grep( +-[a-zA-Z]+)* +[^|;&]*(\$spawn|\$here/bin|\$spn|bin/spawn)' "$@" 2>/dev/null | grep -v 'pitfall-ok: src-grep' || true; }
chk_iso() { # one file: runs spawn as a command but names no isolation
  f=$1
  if grep -v -E '^[[:space:]]*#' "$f" 2>/dev/null | grep -q -E '"\$spawn" [A-Za-z-]|(^|[;|&(|`] *)bin/spawn( |$)'; then
    grep -q -E 'DEVKIT_VIEW=off' "$f" 2>/dev/null || grep -q -E 'PATH=.*(stub|hs)|herdr-stub|/stubs' "$f" 2>/dev/null \
      || echo "$f: runs spawn without DEVKIT_VIEW=off or a PATH stub"
  fi
}

# --- self-test: each rule flags its known-bad fixture and passes its known-good one
bad_seq='for i in $(seq 1 $n); do echo $i; done'; good_seq='for i in $(seq 1 10); do echo $i; done'
printf '%s\n' "$bad_seq" > "$t/bad.sh"; printf '%s\n' "$good_seq" > "$t/good.sh"
ok "seq-args flags variable args" '[ -n "$(r_seq "$t/bad.sh")" ]'
ok "seq-args passes literal ranges" '[ -z "$(r_seq "$t/good.sh")" ]'

bad_port='m=$(stat -c %Y "$f")'; good_port='m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) # pitfall-ok: portable-cmd GNU-or-BSD fallback pair'
printf '%s\n' "$bad_port" > "$t/bad.sh"; printf '%s\n' "$good_port" > "$t/good.sh"
ok "portable-cmd flags raw stat" '[ -n "$(r_portable "$t/bad.sh")" ]'
ok "portable-cmd passes the marked fallback pair" '[ -z "$(r_portable "$t/good.sh")" ]'

bad_ls='ps -o lstart= -p "$pid" > start' # pitfall-ok: lstart-tz self-test fixture, never executed
good_ls='LC_ALL=C TZ=UTC ps -o lstart= -p "$pid" > start'
printf '%s\n' "$bad_ls" > "$t/bad.sh"; printf '%s\n' "$good_ls" > "$t/good.sh"
ok "lstart-tz flags unqualified lstart" '[ -n "$(r_lstart "$t/bad.sh")" ]'
ok "lstart-tz passes LC_ALL=C TZ=UTC" '[ -z "$(r_lstart "$t/good.sh")" ]'

printf '%s\n' 'until mkdir "$d" 2>/dev/null; do' '  :' 'done' > "$t/bad.sh"
printf '%s\n' 'tries=0' 'until mkdir "$d" 2>/dev/null; do' '  tries=$((tries+1)); [ "$tries" -ge 20 ] && exit 2' 'done' > "$t/good.sh"
ok "bounded-retry flags a bare until loop" '[ -n "$(r_retry "$t/bad.sh")" ]'
ok "bounded-retry passes a counted loop" '[ -z "$(r_retry "$t/good.sh")" ]'

bad_ar='[ "$depth" -lt "$MAXD" ]'; good_ar='[ "$((10#$depth))" -eq 0 ]'; good_ar2='[ "$tries" -ge 20 ] # pitfall-ok: decimal-arith internal counter, always decimal'
printf '%s\n' "$bad_ar" > "$t/bad.sh"; printf '%s\n' "$good_ar" "$good_ar2" > "$t/good.sh"
ok "decimal-arith flags a bare comparison on vars" '[ -n "$(r_arith "$t/bad.sh")" ]'
ok "decimal-arith passes 10# and marked lines" '[ -z "$(r_arith "$t/good.sh")" ]'

bad_sl='sleep 5' # sleep-ok: self-test fixture, never executed
good_sl='sleep 5 # sleep-ok: bounded wait for the condition below'
printf '%s\n' "$bad_sl" > "$t/bad.sh"; printf '%s\n' "$good_sl" > "$t/good.sh"
ok "sleep-ok flags an unexplained fixed sleep" '[ -n "$(r_sleep "$t/bad.sh")" ]'
ok "sleep-ok passes a sleep with a why" '[ -z "$(r_sleep "$t/good.sh")" ]'

printf '%s\n' '#!/usr/bin/env bash' 'FAKE_ID=x "$spawn" x fake brief.md' > "$t/badt.sh"
printf '%s\n' '#!/usr/bin/env bash' 'export DEVKIT_VIEW=off' 'FAKE_ID=x "$spawn" x fake brief.md' > "$t/goodt.sh"
ok "spawn-isolation flags a run with no isolation" '[ -n "$(chk_iso "$t/badt.sh")" ]'
ok "spawn-isolation passes DEVKIT_VIEW=off" '[ -z "$(chk_iso "$t/goodt.sh")" ]'

bad_sg='grep -q "cannot load" "$here/bin/spawn"'; good_sg='grep -q "^done" "$TD/run/v4.status"'
printf '%s\n' "$bad_sg" > "$t/bad.sh"; printf '%s\n' "$good_sg" > "$t/good.sh"
ok "src-grep flags greps of bin sources" '[ -n "$(r_srcgrep "$t/bad.sh")" ]'
ok "src-grep passes greps of outputs" '[ -z "$(r_srcgrep "$t/good.sh")" ]'

# --- repo scans: the current tree must be clean (fixed or allowlisted)
ok "seq-args: bin/ has no variable-arg seq" '[ -z "$(r_seq "$here/bin")" ]'
ok "portable-cmd: bin/ has no raw stat/date/sed/readlink" '[ -z "$(r_portable "$here/bin")" ]'
ok "lstart-tz: lstart always runs under LC_ALL=C TZ=UTC" '[ -z "$(r_lstart "$here/bin" "$here/tests")" ]'
ok "bounded-retry: bin/ loops name a bound" '[ -z "$(r_retry "$here/bin")" ]'
ok "decimal-arith: bin/ arithmetic is 10# or allowlisted" '[ -z "$(r_arith "$here/bin")" ]'
ok "sleep-ok: fixed sleeps in tests carry a why" '[ -z "$(r_sleep "$here"/tests/*.test.sh)" ]'
srcfiles=""; for f in "$here"/tests/*.test.sh; do case $f in *pitfalls.test.sh) continue;; esac; srcfiles="$srcfiles $f"; done
ok "src-grep: no raw bin-source greps in tests" '[ -z "$(r_srcgrep $srcfiles)" ]'
isobad=""; for f in "$here"/tests/*.test.sh; do case $f in *pitfalls.test.sh) continue;; esac; hit=$(chk_iso "$f"); [ -n "$hit" ] && isobad="$isobad $hit"; done
ok "spawn-isolation: tests running spawn isolate the view" '[ -z "$isobad" ]'

# --- docs index: every row names an existing guard (rule id or repo path)
valid_guards() {
  bad=0
  while IFS= read -r line; do
    guard=$(printf '%s' "$line" | awk -F'|' '{print $4}')
    for tok in $(printf '%s' "$guard" | tr '+,' ' '); do
      tok=$(printf '%s' "$tok" | tr -d '()')
      [ -z "$tok" ] && continue
      case $tok in *"/"*) [ -e "$here/$tok" ] || { echo "unknown file guard: $tok"; bad=1; };; *) case " $guards " in *" $tok "*) ;; *) echo "unknown guard: $tok"; bad=1;; esac;; esac
    done
  done < <(grep '^| pg-' "$here/docs/pitfalls.md" 2>/dev/null)
  [ "$bad" -eq 0 ]
}
ok "pitfalls.md exists with 11 rows" '[ -f "$here/docs/pitfalls.md" ] && [ "$(grep -c "^| pg-" "$here/docs/pitfalls.md")" -ge 11 ]'
ok "every pitfalls.md row names an existing guard" 'valid_guards'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
