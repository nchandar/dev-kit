#!/usr/bin/env bash
# Live replay of claim_lead on the real bin/spawn (no extraction): a scratch git
# repo, one fake CLI, two real concurrent --lead spawns at DEVKIT_MAX_LEADS=1.
#   replay.sh fixed    bin/spawn at HEAD, no stall
#   replay.sh stalled  same, with a 2s stall after the lead-dir mkdir, before
#                      the count (PATH shim on mkdir, like the slot replay)
#   replay.sh old      bin/spawn at 7e98b33^ (the old count-then-start)
#
# SAFETY: HOME is the scratch dir; install.sh, setup --apply and anything that
# links into the real HOME are never run.
set -u
here=$(cd "$(dirname "$0")" && pwd)
run=${1:-fixed}
repo=$(cd "$here/../.." && pwd)   # the repo under test is the one holding models/
[ -x "$repo/bin/spawn" ] || { echo "replay: no bin/spawn in $repo" >&2; exit 2; }
scratch=${SCRATCH:-$here/scratch}/$run
rm -rf "$scratch"; mkdir -p "$scratch"/{home,shim}
root=$scratch
cd "$root" || exit 2
git init -q -b main
echo base > f.txt
cat > .gitignore <<'I'
/.devkit/
/fake
/events
/started-*
/*.hold
/*.rc
/*.err
/brief*.md
/shim/
/home/
I
git add -A && git -c user.name=t -c user.email=t@t commit -qm init

# the tree under test: HEAD (fixed) or the pre-fix commit (old)
if [ "$run" = old ]; then
  git -C "$repo" archive 7e98b33^ bin | tar -x -C "$root"
else
  cp -R "$repo/bin" "$root/bin"
fi
[ -x "$root/bin/spawn" ] || { echo "replay: no bin/spawn in $root" >&2; exit 2; }

export HOME="$root/home" DEVKIT_DIR="$root/.devkit" DEVKIT_MODE=headless \
  DEVKIT_TIMEOUT=0 DEVKIT_VIEW=off DEVKIT_MAX_WORKERS=3 DEVKIT_MAX_LEADS=1 \
  DEVKIT_MAX_DEPTH=3 DEVKIT_CHILD_WAIT=1 TMPDIR="$root"
unset DEVKIT_DEPTH DEVKIT_WORKER CLAUDE_CODE_SESSION_ID DEVKIT_MODEL DEVKIT_SAFE DEVKIT_DRYRUN \
  DEVKIT_VIEW_KEEP DEVKIT_VIEW_NOTIFY GIT_CONFIG_COUNT 2>/dev/null || true
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done

T=$("$root/bin/ledger" start lead-cap x) || exit 2
export DEVKIT_TASK=$T
E="$root/events"; : > "$E"

cat > "$root/fake" <<'F'
#!/usr/bin/env bash
echo "start ${FAKE_ID:-x} $$" >> "$DEVKIT_DIR/../events"
: > "$DEVKIT_DIR/../started-${FAKE_ID:-x}"
[ -z "${FAKE_HOLD:-}" ] || while [ -e "$FAKE_HOLD" ]; do sleep 0.1; done
printf 'ran %s\n\n## Checklist\n- [x] done\n' "${FAKE_ID:-x}" > "$2"
F
chmod +x "$root/fake"
export DEVKIT_FAKE="$root/fake"
echo "do the thing" > "$root/brief.md"

if [ "$run" = stalled ]; then
  # the only injection: a stall after a successful mkdir of a *.lead dir,
  # which in claim_lead is between `mkdir "$c"` (:313) and the count (:317-320).
  cat > "$root/shim/mkdir" <<'M'
#!/usr/bin/env bash
/bin/mkdir "$@"; rc=$?
[ $rc -eq 0 ] || exit $rc
case "$*" in *".lead"*) sleep 2;; esac
exit 0
M
  chmod +x "$root/shim/mkdir"
  export PATH="$root/shim:$PATH"
fi

hold="$root/race.hold"; : > "$hold"
leads() { ( export FAKE_ID=$1 FAKE_HOLD=$hold
  "$root/bin/spawn" --lead "$1" fake "$root/brief.md" >/dev/null 2>"$root/$1.err"
  echo $? > "$root/$1.rc" ) & }
leads ra; pra=$!
leads rb; prb=$!
n=0
while [ "$n" -lt 100 ]; do
  [ -e "$root/ra.rc" ] && break
  [ -e "$root/rb.rc" ] && break
  [ -e "$root/started-ra" ] && [ -e "$root/started-rb" ] && break
  sleep 0.05; n=$((n+1))
done
rm -f "$hold"
wait "$pra" 2>/dev/null; wait "$prb" 2>/dev/null

starts() { grep -c "^start $1 " "$E" 2>/dev/null || true; }
sra=$(starts ra); srb=$(starts rb)
rca=$(cat "$root/ra.rc" 2>/dev/null || echo missing); rcb=$(cat "$root/rb.rc" 2>/dev/null || echo missing)
echo "run=$run tree=$( [ "$run" = old ] && echo '7e98b33^ (count-then-start)' || echo 'HEAD (claim-then-count, cap test under the lock)')" 
echo "ra: starts=$sra rc=$rca  err=$(tr '\n' ' ' < "$root/ra.err" 2>/dev/null)"
echo "rb: starts=$srb rc=$rcb  err=$(tr '\n' ' ' < "$root/rb.err" 2>/dev/null)"
echo "lead claims left: $(ls "$root/.devkit/tasks/$T/run"/*.lead 2>/dev/null | wc -l | tr -d ' ')"
total=$((sra + srb)); okrc=$(( (rca == 0) + (rcb == 0) ))
echo "started=$total accepted=$okrc"
case $run in
  fixed)   want=1 ;;
  stalled) want=1 ;;
  old)     want=2 ;;
esac
if [ "$total" -eq "$want" ] && [ "$okrc" -eq "$want" ]; then
  echo "RESULT ok: want $want lead(s), got $total"
  exit 0
fi
echo "RESULT FAIL: want $want lead(s), got $total"
exit 1
