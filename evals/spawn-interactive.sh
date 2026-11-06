#!/usr/bin/env bash
# Interactive spawn eval: per installed CLI, spawn a trivial scout in a herdr tab and check the whole path worked.
# Manual, costs a few agent turns per CLI (like evals/route.sh). Needs a running herdr. Usage: evals/spawn-interactive.sh [--list]
# Env: EVAL_CLIS (default "claude codex opencode"), EVAL_TIMEOUT (300), EVAL_HERDR and EVAL_SPAWN (test seams)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/.." && pwd)
HERDR=${EVAL_HERDR:-herdr}; SPAWN=${EVAL_SPAWN:-$root/bin/spawn}; clis=${EVAL_CLIS:-claude codex opencode}
asserts="tab created|agent detected|ticked checklist|tab closed|exit 0"
if [ "${1:-}" = --list ]; then
  for c in $clis; do command -v "$c" >/dev/null 2>&1 && s=installed || s="not installed (skipped)"; echo "$c: $s"; done
  echo "assertions per cli: ${asserts//|/, }"; exit 0; fi
"$HERDR" tab list >/dev/null 2>&1 || { echo "spawn eval: needs a running herdr (tried: $HERDR tab list)" >&2; exit 2; }

# claude and codex stop on "trust this folder?" in a fresh /var/folders dir; under the repo's git-ignored .devkit they start straight away
mkdir -p "$root/.devkit"; tmp=$(mktemp -d "$root/.devkit/spawn-eval.XXXXXX") || exit 2; tmp=$(cd "$tmp" && pwd -P); trap 'rm -rf "$tmp"' EXIT
real=$(command -v "$HERDR"); mkdir -p "$tmp/bin"
# logging wrapper: the spawn under test finds it first on PATH; agent get output is kept to prove the agent was seen
cat > "$tmp/bin/herdr" <<S
#!/usr/bin/env bash
out=\$("$real" "\$@"); rc=\$?
printf '%s\n' "\$*" >> "$tmp/herdr.log"
case "\$1 \$2" in "agent get") printf 'OUT %s\n' "\$out" >> "$tmp/herdr.log";; esac
printf '%s\n' "\$out"; exit \$rc
S
chmod +x "$tmp/bin/herdr"
echo base > "$tmp/f.txt" # no .git of its own: claude would treat it as a new, untrusted project root
export DEVKIT_DIR="$tmp/.devkit" DEVKIT_MODE=interactive DEVKIT_TIMEOUT=${EVAL_TIMEOUT:-300}
# a worker may run this eval: the sandbox DEVKIT_DIR above is its own world, so drop the inherited depth and task (ledger refuses `start` at depth>=1)
unset DEVKIT_DEPTH DEVKIT_TASK
task=$(cd "$tmp" && "$root/bin/ledger" start spawn-eval); export DEVKIT_TASK=$task
bad=0; n=0
res() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS	$1	$3"; else echo "FAIL	$1	$3"; bad=1; fi; }
for c in $clis; do
  if [ -z "${EVAL_SPAWN:-}" ] && ! command -v "$c" >/dev/null 2>&1; then echo "SKIP	$c	not installed"; continue; fi
  id="ev-$c"; : > "$tmp/herdr.log"; hf="$DEVKIT_DIR/tasks/$task/handoffs/$id.md"
  (cd "$tmp" && PATH="$tmp/bin:$PATH" "$SPAWN" --shape scout --prompt $'route: dev-research\nWrite a handoff that says PASS. Change nothing else.' "$id" "$c" >"$tmp/$c.out" 2>&1); rc=$?
  grep -q '^tab create' "$tmp/herdr.log"; res "$c: tab created" $? ""
  grep -A1 "^agent get $id" "$tmp/herdr.log" | grep -q '^OUT .*agent_status'; res "$c: agent detected" $? ""
  [ -s "$hf" ] && grep -q '^## Checklist' "$hf" && sed -n '/^## Checklist/,$p' "$hf" | grep -q '\[x\]'; res "$c: ticked checklist" $? "$hf"
  grep -q '^tab close' "$tmp/herdr.log"; res "$c: tab closed" $? ""
  [ "$rc" = 0 ]; res "$c: exit 0" $? "rc=$rc"
  [ "$rc" = 0 ] || tail -5 "$tmp/$c.out" | sed 's/^/    /'
done
[ "$n" -gt 0 ] || { echo "spawn eval: no CLI installed, nothing ran" >&2; exit 2; }
exit $bad
