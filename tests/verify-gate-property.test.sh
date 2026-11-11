#!/usr/bin/env bash
# Stateful property test for the verify gate -> ledger done soundness.
#
# Reference model (library/deep/property-check): {tree, newest verify-gate row, waived}.
#   Done succeeds iff the tree equals the base, or the newest verify-gate row is pass for the
#   current tree with a non-empty log under the task's runs/, or a waive reason of 20+ chars.
# Random sequences of Edit, Verify(pass|fail), Done and DoneWaive run against the REAL
# bin/verify and bin/ledger in scratch git repos, and every outcome is compared to the model.
# A mismatch prints the seed and the shrunk action sequence.
# Also kills bin/verify inside finish() at each observable step (bin/verify:68-72) and
# asserts no pass row is ever recorded for a tree that changed after the run started.
#
# Seeded and deterministic: default seed 20261111, 200 random action steps grouped into
# sequences of 1..4 actions, batched 8 repos at a time (about 80 sequences).
# Override: VERIFY_GATE_PROP_SEED, VERIFY_GATE_PROP_STEPS, VERIFY_GATE_PROP_BATCH.
# Mutation proof (manual): VERIFY_GATE_PROP_TOOLS=<copy of bin> must make this suite fail.
# Usage: tests/verify-gate-property.test.sh
set -u
unset DEVKIT_DEPTH DEVKIT_TASK DEVKIT_DIR CLAUDE_CODE_SESSION_ID
here=$(cd "$(dirname "$0")/.." && pwd)
TOOLS=${VERIFY_GATE_PROP_TOOLS:-$here/bin}
SEED=${VERIFY_GATE_PROP_SEED:-20261111}
STEPS=${VERIFY_GATE_PROP_STEPS:-200}
BATCH=${VERIFY_GATE_PROP_BATCH:-8}
case $SEED in ''|*[!0-9]*) echo "verify-gate-property: VERIFY_GATE_PROP_SEED must be a non-negative integer" >&2; exit 2;; esac
case $STEPS in ''|*[!0-9]*|0) echo "verify-gate-property: VERIFY_GATE_PROP_STEPS must be a positive integer" >&2; exit 2;; esac
case $BATCH in ''|*[!0-9]*|0) echo "verify-gate-property: VERIFY_GATE_PROP_BATCH must be a positive integer" >&2; exit 2;; esac
export VERIFY_TICK=0.02 # watchdog poll resolution: faster runs, same bounds
root=$(mktemp -d) || exit 2
trap 'rm -rf "$root"' EXIT
echo "verify-gate-property: seed=$SEED steps=$STEPS batch=$BATCH"

pass=0; fail=0

# one template repo on main with copies of the real gate tools; the suite result is an env switch
# so flipping pass/fail never changes the tree id. Every case gets a cheap copy of it.
mktemplate() { # dir
  local d=$1 t
  mkdir -p "$d" || return 2
  ( cd "$d" || exit 2
    git init -q -b main . && git config user.email t@t && git config user.name t || exit 2
    mkdir -p bin tests docs skills/dev-x
    # no verify-scan: it has its own suites, and the gate rule is what this test models (it is
    # also the slowest part of bin/verify on a scratch repo)
    for t in verify ledger run defaults; do cp "$TOOLS/$t" bin/ || exit 2; done
    chmod +x bin/verify bin/ledger bin/run
    printf '#!/usr/bin/env bash\necho lint-ok\n' > bin/lint-budget
    printf '#!/usr/bin/env bash\necho "ok light"\n' > tests/pitfalls.test.sh
    cat > tests/run-all.sh <<'S'
#!/usr/bin/env bash
if [ "${VERIFY_GATE_PROP_SUITE:-pass}" = pass ]; then
  echo "a.test.sh   3 passed, 0 failed   1s"
else
  echo "a.test.sh   0 passed, 1 failed   1s"; exit 1
fi
S
    cat > tests/a.test.sh <<'S'
#!/usr/bin/env bash
[ "${VERIFY_GATE_PROP_SUITE:-pass}" = pass ]
S
    printf 'suite_file_s=100\nsuite_total_s=200\n' > bin/verify.budget
    echo base > README.md; echo s > skills/dev-x/SKILL.md; echo d > docs/a.md
    chmod +x bin/lint-budget tests/*.sh
    git add -A && git commit -qm base || exit 2
  ) || return 2
  return 0
}

newrepo() { # dir: a fresh copy of the template, no task yet
  rm -rf "$1" || return 2
  cp -R "$root/tpl" "$1" || return 2
}

# deterministic LCG: one global seed, 31-bit modulus, no dependency

gen_plan() { # seed -> "action ..." (1..4 actions; edits 40%, verify 15%, done 25%, waive 20%)
  local s=$1 n i p a out=
  n=$(( 1 + (s % 4) ))
  i=0
  while [ "$i" -lt "$n" ]; do
    s=$(( (s * 1103515245 + 12345) % 2147483648 )); p=$(( s % 100 ))
    if [ "$p" -lt 40 ]; then a=edit
    elif [ "$p" -lt 55 ]; then s=$(( (s * 1103515245 + 12345) % 2147483648 ))
      [ $(( s % 2 )) -eq 0 ] && a=vpass || a=vfail
    elif [ "$p" -lt 80 ]; then a=done
    else s=$(( (s * 1103515245 + 12345) % 2147483648 ))
      [ $(( s % 2 )) -eq 0 ] && a=waive-long || a=waive-short
    fi
    out="$out $a"; i=$((i+1))
  done
  printf '%s' "$out"
}

model_fail() { # outfile step action why
  printf 'MISMATCH step=%s action=%s: %s\n' "$2" "$3" "$4" >> "$1"
  exit 1
}

# Execute one action sequence against the real tools; 0 matches the model, 1 mismatch, 2 setup error.
# Every comparison is the model's rule, never a copy of bin/ledger's branches.
run_actions() { # repo plan mismatch-out
  local repo=$1 plan=$2 out=$3
  local BASE GT D T last pass_tree n0 act want rc row got rsn ev nrows last2
  ( cd "$repo" || exit 2
    BASE=$(bin/verify tree) || exit 2
    GT=$(bin/ledger start prop) || exit 2
    D=".devkit/tasks/$GT"; export DEVKIT_TASK=$GT
    T=$BASE; last=none; pass_tree=; n0=0
    for act in $plan; do
      n0=$((n0+1))
      case $act in
        edit)
          printf '%s\n' "edit $n0" >> skills/dev-x/SKILL.md
          T=? # lazily recomputed by the next verify, or implied by a done on a changed tree
          ;;
        vpass|vfail)
          [ "$T" = ? ] && { T=$(bin/verify tree) || model_fail "$out" "$n0" "$act" "verify tree failed"; }
          [ "$act" = vpass ] && want=pass || want=fail
          [ "$T" = "$BASE" ] && want=pass # a tree equal to the base is nodiff: pass, nothing run
          VERIFY_GATE_PROP_SUITE=$want bin/verify >/dev/null 2>&1; rc=$?
          if [ "$want" = pass ]; then rcwant=0; else rcwant=1; fi
          [ "$rc" -eq "$rcwant" ] || model_fail "$out" "$n0" "$act" "verify exit $rc, model expects $rcwant"
          row=$(awk -F'\t' '$2=="verify-gate"{l=$0} END{print l}' "$D/ledger.tsv")
          got=$(printf '%s' "$row" | cut -f6); rsn=$(printf '%s' "$row" | cut -f4); ev=$(printf '%s' "$row" | cut -f5)
          [ "$got" = "$want" ] || model_fail "$out" "$n0" "$act" "newest verify-gate row is '${got:-none}', model expects $want"
          case $rsn in *"tree $T"*) ;; *) model_fail "$out" "$n0" "$act" "row does not name tree $T: $rsn";; esac
          if [ "$got" = pass ]; then
            # a nodiff pass (tree == base) closes on the tree rule and carries no log
            if [ "$T" != "$BASE" ]; then
              [ -n "$ev" ] && [ -f "$ev" ] && [ -s "$ev" ] || model_fail "$out" "$n0" "$act" "pass row has no non-empty log (evidence '${ev:-none}')"
              case $(cd "$(dirname "$ev")" 2>/dev/null && pwd -P) in
                "$(cd "$D/runs" 2>/dev/null && pwd -P)") ;;
                *) model_fail "$out" "$n0" "$act" "pass log $ev is not under the task's runs/" ;;
              esac
            fi
            last=pass; pass_tree=$T
          else
            last=$got; pass_tree=
          fi
          ;;
        done)
          want=4 # the model's rule: base tree, a valid pass for this tree, or a waive
          if [ "$T" = ? ]; then
            : # an edit after the newest row: the tree cannot be the base and every row is stale
          else
            [ "$T" = "$BASE" ] && want=0
            [ "$last" = pass ] && [ "$pass_tree" = "$T" ] && want=0
          fi
          nrows=$(awk 'END{print NR}' "$D/ledger.tsv")
          bin/ledger -t "$GT" done "seq step $n0" >/dev/null 2>"$out.err"; rc=$?
          if [ "$want" -eq 0 ]; then
            [ "$rc" -eq 0 ] || model_fail "$out" "$n0" done "refused (exit $rc) where the model allows the close: $(head -1 "$out.err" 2>/dev/null)"
            [ "$(awk -F'\t' 'END{print $2}' "$D/ledger.tsv")" = done ] || model_fail "$out" "$n0" done "closed without a done row"
            break
          fi
          [ "$rc" -eq 4 ] || model_fail "$out" "$n0" done "exit $rc where the model refuses (4): $(head -1 "$out.err" 2>/dev/null)"
          [ "$(awk 'END{print NR}' "$D/ledger.tsv")" = "$nrows" ] || model_fail "$out" "$n0" done "a refused done wrote rows"
          ;;
        waive-long|waive-short)
          if [ "$act" = waive-long ]; then
            bin/ledger -t "$GT" done --waive "waived by the property test step $n0" "w$n0" >/dev/null 2>&1; rc=$?
            [ "$rc" -eq 0 ] || model_fail "$out" "$n0" "$act" "a 20+ char waive was refused (exit $rc)"
            last2=$(awk -F'\t' '{p=q; q=$2} END{print p" "q}' "$D/ledger.tsv")
            [ "$last2" = "waive done" ] || model_fail "$out" "$n0" "$act" "waive close rows are '$last2', want 'waive done'"
            break
          fi
          nrows=$(awk 'END{print NR}' "$D/ledger.tsv")
          bin/ledger -t "$GT" done --waive "short" "s$n0" >/dev/null 2>&1; rc=$?
          [ "$rc" -eq 2 ] || model_fail "$out" "$n0" "$act" "a short waive returned $rc, want 2"
          [ "$(awk 'END{print NR}' "$D/ledger.tsv")" = "$nrows" ] || model_fail "$out" "$n0" "$act" "a refused waive wrote rows"
          ;;
        *) model_fail "$out" "$n0" "$act" "unknown action" ;;
      esac
    done
    :
  )
}

# batched background sequences: each gets its own scratch repo, task and job dir
jobs="$root/jobs"; : > "$jobs"; batch=0
ok() { # label dir
  local d=$2
  ( if newrepo "$d/repo"; then
      run_actions "$d/repo" "$(cat "$d/plan")" "$d/mismatch" > "$d/out" 2> "$d/err"
      echo $? > "$d/rc"
    else
      echo 2 > "$d/rc"
    fi ) &
  printf '%s\t%s\t%s\n' "$!" "$1" "$d" >> "$jobs"
  batch=$((batch+1)); [ "$batch" -lt "$BATCH" ] || drain
}
drain() {
  local pid name d rc
  while IFS=$'\t' read -r pid name d; do
    wait "$pid" 2>/dev/null; rc=$(cat "$d/rc" 2>/dev/null || echo 2)
    if [ "$rc" -eq 0 ]; then pass=$((pass+1)); echo "ok   $name"
    else fail=$((fail+1)); echo "FAIL $name (rc=$rc)"
      sed 's/^/     /' "$d/mismatch" 2>/dev/null | head -4
      sed 's/^/     /' "$d/err" 2>/dev/null | head -2
    fi
  done < "$jobs"
  : > "$jobs"; batch=0
}

# shrinking: drop actions while the mismatch survives, in fresh repos; only runs on a failure
shrink_plan() { # plan -> shortest plan that still mismatches
  local acts=$1 n i cand changed
  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    n=$(printf '%s\n' $acts | wc -l | tr -d ' ')
    i=1
    while [ "$i" -le "$n" ]; do
      cand=$(printf '%s\n' $acts | awk -v drop="$i" 'NR!=drop' | tr '\n' ' ')
      if newrepo "$root/shrink"; then
        run_actions "$root/shrink" "$cand" "$root/shrink.mismatch" >/dev/null 2>&1
        [ $? -eq 1 ] && { acts=$cand; changed=1; break; }
      fi
      i=$((i+1))
    done
  done
  printf '%s' "$acts"
}

idx=0
mktemplate "$root/tpl" || { echo "verify-gate-property: cannot build the template repo"; exit 2; }
remaining=$STEPS
while [ "$remaining" -gt 0 ]; do
  idx=$((idx+1))
  d="$root/s.$idx"; mkdir -p "$d"
  seed=$(( (SEED + idx * 7919) % 2147483648 ))
  plan=$(gen_plan "$seed")
  plan=$(printf '%s' "$plan" | sed 's/^ *//;s/ *$//')
  set -- $plan
  [ $# -le "$remaining" ] || { plan=$(printf '%s\n' $plan | head -n "$remaining" | tr '\n' ' '); plan=$(printf '%s' "$plan" | sed 's/ *$//'); }
  set -- $plan
  remaining=$((remaining - $#))
  printf '%s\n' "$seed" > "$d/seed"; printf '%s\n' "$plan" > "$d/plan"
  ok "seq $idx seed=$seed [$plan]" "$d"
done
drain

# print the seed and the shrunk sequence for a real mismatch
if [ "$fail" -gt 0 ]; then
  for d in "$root"/s.*; do
    [ -s "$d/mismatch" ] || continue
    seed=$(cat "$d/seed")
    plan=$(cat "$d/plan")
    printf 'FAIL seed=%s sequence=%s\n' "$seed" "$plan"
    sed 's/^/     /' "$d/mismatch"
    printf '     shrunk: %s\n' "$(shrink_plan "$plan")"
  done
fi

# --- kills inside finish(): a pass row must never name a tree that changed after the run started.
# BASH_ENV installs a DEBUG trap only in the copied bin/verify; set -T makes it reach functions.
KT="$root/ktrap"
cat > "$KT" <<'S'
case ${VERIFY_GATE_PROP_KILL:-off} in off) return 0;; esac
set -T
trap '
  case ${BASH_SOURCE[0]:-} in
    *verify)
      case "$BASH_COMMAND" in
        *runlog\ tests/run-all.sh*) [ "${VERIFY_GATE_PROP_KILL:-}" = pre-suite ] && kill -KILL $$;;
        *gate-row*) [ "${VERIFY_GATE_PROP_KILL:-}" = pre-row ] && kill -KILL $$;;
        *tier=\$tier\ tree=\$tree*) [ "${VERIFY_GATE_PROP_KILL:-}" = post-row ] && kill -KILL $$;;
        *exit\ \"\$2\"*) [ "${VERIFY_GATE_PROP_KILL:-}" = pre-exit ] && kill -KILL $$;;
      esac;;
  esac' DEBUG
S

kill_case() { # point expected-pass-rows
  local point=$1 want=$2 d="$root/k.$1" GT t0 t1 rc rows t1rows t0rows
  newrepo "$d" || { echo "FAIL kill $point: setup"; return 1; }
  cd "$d" || return 1
  GT=$(bin/ledger start kill) || { cd "$root"; echo "FAIL kill $point: ledger start"; return 1; }
  export DEVKIT_TASK=$GT
  echo dirty >> skills/dev-x/SKILL.md
  t0=$(bin/verify tree)
  ( BASH_ENV="$KT" VERIFY_GATE_PROP_KILL=$point bin/verify; rc=$?; exit $rc ) >/dev/null 2>&1; rc=$?
  rows=$(awk -F'\t' '$2=="verify-gate" && $6=="pass"{n++} END{print n+0}' ".devkit/tasks/$GT/ledger.tsv")
  if [ "$rc" -ne 137 ]; then echo "FAIL kill $point: verify rc=$rc, want 137 (killed)"; cd "$root"; return 1; fi
  if [ "$rows" -ne "$want" ]; then echo "FAIL kill $point: $rows pass rows, want $want"; cd "$root"; return 1; fi
  if [ "$want" -gt 0 ]; then
    t0rows=$(awk -F'\t' -v t="$t0" '$2=="verify-gate" && $6=="pass" && index($4,"tree " t){n++} END{print n+0}' ".devkit/tasks/$GT/ledger.tsv")
    [ "$t0rows" -eq "$want" ] || { echo "FAIL kill $point: $t0rows pass rows name the run's tree $t0, want $want"; cd "$root"; return 1; }
  fi
  echo changed >> skills/dev-x/SKILL.md
  t1=$(bin/verify tree)
  t1rows=$(awk -F'\t' -v t="$t1" '$2=="verify-gate" && $6=="pass" && index($4,"tree " t){n++} END{print n+0}' ".devkit/tasks/$GT/ledger.tsv")
  if [ "$t1rows" -ne 0 ]; then echo "FAIL kill $point: $t1rows pass row(s) name the changed tree $t1"; cd "$root"; return 1; fi
  bin/ledger -t "$GT" done "kill $point" >/dev/null 2>&1; rc=$?
  cd "$root"
  [ "$rc" -eq 4 ] || { echo "FAIL kill $point: done rc=$rc after the tree changed, want 4"; return 1; }
  echo "ok   kill $point: rc 137, $rows pass row(s), no row for the changed tree, done refused"
  return 0
}

# the four kill cases are independent: run them together, merge in call order
killjobs="$root/killjobs"; : > "$killjobs"
k=0
for kc in "pre-suite 0" "pre-row 0" "post-row 1" "pre-exit 1"; do
  k=$((k+1)); d="$root/k.$k"; mkdir -p "$d"
  ( set -- $kc; kill_case "$1" "$2"; echo $? > "$d/rc" ) > "$d/out" 2>&1 &
  printf '%s\t%s\n' "$!" "$d" >> "$killjobs"
done
while IFS=$'\t' read -r pid d; do
  wait "$pid" 2>/dev/null; rc=$(cat "$d/rc" 2>/dev/null || echo 2)
  [ -f "$d/out" ] && cat "$d/out"
  if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
done < "$killjobs"

echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
