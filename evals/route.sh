#!/usr/bin/env bash
# Routing eval for dev-mode: does claude announce the right route, and keep the footer on off-topic follow-ups?
# Costs a few dollars of tokens per run. Usage: evals/route.sh [--list]
# Env: EVAL_ONLY=drift (skip routing), EVAL_AGENT (claude|opencode), EVAL_CLAUDE, EVAL_OPENCODE, EVAL_MODEL (opencode: provider/model), EVAL_JOBS (4), EVAL_BAR (29 of 31), EVAL_DRIFT_BAR (5 of 6)
set -u
here=$(cd "$(dirname "$0")" && pwd); cases=$here/route.cases; drift=$here/route.drift
nc=$(wc -l < "$cases" | tr -d ' '); nd=$(wc -l < "$drift" | tr -d ' ')
if [ "${1:-}" = --list ]; then cut -f1 "$cases" | sort | uniq -c | sed 's/^ */  /'; echo "$nc routing cases, $nd drift scenarios"; exit 0; fi

export CL=${EVAL_CLAUDE:-claude} OC=${EVAL_OPENCODE:-opencode} AGENT=${EVAL_AGENT:-claude} MODEL=${EVAL_MODEL:-} cases drift
export NOTE="EVAL MODE: use no tools and do not do the work. Reply with only the announce line (route: <skill>, <size>) and, unless the route is none, the footer line."
export NOTE2="EVAL MODE: use no tools and do not do the work. Treat the route as just started at step 1 of 6; reply with the announce line and the footer. Answer later questions briefly."
# opencode has no slash-command injection: the model must load the skill itself, so it may not be told "use no tools"
export NOTE_OC="EVAL MODE: use only the skill tool; do not read files, search or run commands. Load the dev-mode skill, then reply with only the announce line (route: <skill>, <size>) and, unless the route is none, the footer line."
export NOTE2_OC="You may use only the skill tool, to load dev-mode. Do not do the work. Treat the route as just started at step 1 of 6; reply with the announce line and the footer. Answer later questions briefly."
export tmp=$(mktemp -d) res=$(mktemp -d); trap 'rm -rf "$tmp" "$res"' EXIT
(cd "$tmp" && git init -q)

run_route() { # n: one single-turn classification
  local exp req out got r
  IFS=$'\t' read -r exp req < <(sed -n "${1}p" "$cases")
  if [ "$AGENT" = opencode ]; then
    # opencode prints its answer on stdout and tool traces on stderr; the traces can echo
    # repo files that hold sample "route: ..." lines, so score only the answer
    out=$(cd "$tmp" && "$OC" run ${MODEL:+-m "$MODEL"} "Use the dev-mode skill for this request: $req"$'\n\n'"$NOTE_OC" 2>/dev/null </dev/null)
  else
    out=$(cd "$tmp" && "$CL" -p "/dev-mode $req"$'\n\n'"$NOTE" --no-session-persistence ${MODEL:+--model "$MODEL"} 2>&1 </dev/null)
  fi
  got=$(printf '%s\n' "$out" | grep -o -E 'route: (dev-[a-z]+|none)' | head -1 | sed 's/route: //')
  [ "$got" = "$exp" ] && r=PASS || r=FAIL
  printf '%s\trouting %s\texp=%s got=%s\t%s\n' "$r" "$1" "$exp" "${got:-?}" "$req" > "$res/r$1"
  cut -c1-150 "$res/r$1" >&2 # live progress
}
run_drift() { # n: a route, then two off-topic questions; the footer must stay on the follow-up replies
  local id req q1 q2 j sid q k=0 out r
  IFS=$'\t' read -r id req q1 q2 < <(sed -n "${1}p" "$drift")
  if [ "$AGENT" = opencode ]; then
    sid="ses_eval_${id}_$$" # opencode creates a session under a name we pick; it must start with "ses"
    (cd "$tmp" && "$OC" run ${MODEL:+-m "$MODEL"} -s "$sid" "Use the dev-mode skill for this request: $req"$'\n\n'"$NOTE2_OC" >/dev/null 2>&1 </dev/null)
  else
    j=$(cd "$tmp" && "$CL" -p "/dev-mode $req"$'\n\n'"$NOTE2" --output-format json ${MODEL:+--model "$MODEL"} 2>/dev/null </dev/null)
    sid=$(printf '%s' "$j" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -1)
  fi
  if [ -z "$sid" ]; then # a failed first call must not look like a footer miss
    for k in 1 2; do printf 'FAIL\tdrift %s.%s\tno session id from the first call\n' "$id" "$k" > "$res/d$1.$k"; cut -c1-150 "$res/d$1.$k" >&2; done; return
  fi
  for q in "$q1" "$q2"; do k=$((k+1))
    if [ "$AGENT" = opencode ]; then out=$(cd "$tmp" && "$OC" run ${MODEL:+-m "$MODEL"} -s "$sid" "$q" 2>/dev/null </dev/null)
    else out=$(cd "$tmp" && "$CL" -p "$q" --resume "$sid" ${MODEL:+--model "$MODEL"} 2>&1 </dev/null); fi
    printf '%s\n' "$out" | grep -q -E 'route: dev-[a-z]+, step [0-9]+/[0-9]+, next:' && r=PASS || r=FAIL
    printf '%s\tdrift %s.%s\t%s\n' "$r" "$id" "$k" "$q" > "$res/d$1.$k"
    cut -c1-150 "$res/d$1.$k" >&2
  done
}
export -f run_route run_drift
{ [ "${EVAL_ONLY:-}" = drift ] || seq 1 "$nc" | sed 's/^/r /'; seq 1 "$nd" | sed 's/^/d /'; } | xargs -P "${EVAL_JOBS:-4}" -L1 bash -c 'if [ "$0" = r ]; then run_route "$1"; else run_drift "$1"; fi'

cat "$res"/r* "$res"/d* 2>/dev/null | sort -k2,2V | cut -c1-150
rp=$(cat "$res"/r* 2>/dev/null | grep -c '^PASS'); dp=$(cat "$res"/d* 2>/dev/null | grep -c '^PASS')
if [ "${EVAL_ONLY:-}" = drift ]; then # cheap loop while tuning the footer rule
  echo "routing skipped, drift $dp/$((nd*2)) (bar ${EVAL_DRIFT_BAR:-5})"
  [ "$dp" -ge "${EVAL_DRIFT_BAR:-5}" ]; exit
fi
echo "routing $rp/$nc (bar ${EVAL_BAR:-29}), drift $dp/$((nd*2)) (bar ${EVAL_DRIFT_BAR:-5})"
[ "$rp" -ge "${EVAL_BAR:-29}" ] && [ "$dp" -ge "${EVAL_DRIFT_BAR:-5}" ]
