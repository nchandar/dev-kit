#!/usr/bin/env bash
# Extract slot_live, slot_lock and claim verbatim from bin/spawn so the replay
# drives the real functions, not a copy.
# Usage: extract-slot-lib.sh [bin/spawn] > slot-lib.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=${1:-}
if [ -z "$src" ]; then
  root=$(git -C "$here/../.." rev-parse --show-toplevel) || { echo "extract-slot-lib: not in a git repo" >&2; exit 2; }
  src=$root/bin/spawn
fi
[ -f "$src" ] || { echo "extract-slot-lib: no such file: $src" >&2; exit 2; }
root=$(git -C "$(dirname "$src")" rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$(dirname "$src")/.." && pwd)
rev=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)
printf '# extracted verbatim from %s at %s; regenerate with extract-slot-lib.sh\n' "${src#"$root"/}" "$rev"
for fn in slot_live slot_lock claim; do
  awk -v fn="$fn" 'index($0, fn "()") == 1 { p = 1 } p { print } p && ($0 == "}" || $0 ~ /; }$/) { p = 0 }' "$src"
  printf '\n'
done
