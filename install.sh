#!/usr/bin/env bash
# Install dev-kit for every agent. Safe to rerun. Replaces only symlinks, never real files.
#   ~/.agents/dev-kit  -> this dir (bin/, library/ live here)
#   dev-* skills       -> ~/.claude/skills, ~/.codex/skills, ~/.agents/skills (read by OpenCode and others)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
link() { # src dest
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ] && [ ! -L "$2" ]; then echo "skip real file: $2"; return; fi
  ln -sfn "$1" "$2"; echo "linked: $2"
}
[ -L "$HOME/.agents/harness" ] && rm "$HOME/.agents/harness"  # pre-rename link
link "$here" "$HOME/.agents/dev-kit"
for d in "$here"/skills/dev-*; do
  for root in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"; do link "$d" "$root/$(basename "$d")"; done
done
