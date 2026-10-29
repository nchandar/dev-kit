#!/usr/bin/env bash
# Real cross-agent scenario: the MAIN agent is told, in plain English, to open two other agent
# instances in parallel. Checks the results on disk. Costs a few cents of tokens per run.
# Usage: evals/e2e.sh <claude|codex|opencode> [workerA workerB]     (defaults: the other two CLIs)
set -u
main=${1:?usage: e2e.sh <claude|codex|opencode> [workerA workerB]}
case $main in
  claude)   a=${2:-codex};  b=${3:-opencode};;
  codex)    a=${2:-claude}; b=${3:-opencode};;
  opencode) a=${2:-claude}; b=${3:-codex};;
  *) echo "unknown main $main" >&2; exit 2;;
esac
D=$(mktemp -d)/e2e-$main; mkdir -p "$D" && cd "$D" && git init -q
printf '# Demo project\nA tiny repo.\n' > README.md; printf 'notes\n' > NOTES.md
git add -A && git -c user.name=t -c user.email=t@t commit -qm init

P="Open a $a instance and have it count the tracked markdown files in this repo (git ls-files '*.md'), and in parallel open a $b instance and have it report the first line of README.md. Reply with exactly two lines: the $a result and the $b result."
PK=$(mktemp)
rss() { ps -axo rss=,command= | grep -E '(claude|codex|opencode)' | grep -v grep | awk '{s+=$1} END{print int(s/1024)}'; }
base=$(rss); peak=$base
( while :; do r=$(rss); [ "$r" -gt "$peak" ] && peak=$r && echo "$peak" > "$PK"; sleep 2; done ) & sampler=$!
s=$(date +%s)
case $main in
  claude)   out=$(claude -p "$P" --dangerously-skip-permissions < /dev/null 2>&1);;
  codex)    out=$(codex exec --skip-git-repo-check --ephemeral --dangerously-bypass-approvals-and-sandbox -C "$D" "$P" < /dev/null 2>&1);;
  opencode) out=$(opencode run --auto "$P" < /dev/null 2>&1);;
esac
secs=$(( $(date +%s)-s )); kill $sampler 2>/dev/null; [ -s "$PK" ] && peak=$(cat "$PK")

pass=0; fail=0
chk() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
T=$(ls .devkit/tasks 2>/dev/null | head -1)
chk "main agent answered with the count (2)"            'echo "$out" | grep -q "2"'
chk "main agent answered with the README title"         'echo "$out" | grep -qi "Demo project"'
chk "exactly one task created (workers did not start their own)" '[ "$(ls .devkit/tasks 2>/dev/null | wc -l)" -eq 1 ]'
chk "two workers ran, both finished done"               '[ "$(cat .devkit/tasks/$T/run/*.status 2>/dev/null | grep -c "^done")" -eq 2 ]'
chk "each worker wrote a handoff"                       '[ "$(ls .devkit/tasks/$T/handoffs/*.md 2>/dev/null | wc -l)" -ge 2 ]'
chk "ledger has spawn rows and a closing row"           '[ "$(cut -f2 .devkit/tasks/$T/ledger.tsv | grep -c "^spawn")" -ge 2 ] && cut -f2 .devkit/tasks/$T/ledger.tsv | grep -qE "^(next|done)$"'
chk "project files untouched by scouts"                 '[ -z "$(git status --porcelain | grep -v "\.devkit")" ]'
echo "main=$main workers=$a,$b  secs=$secs  rss base=${base}MB peak=${peak}MB delta=$((peak-base))MB  dir=$D"
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
