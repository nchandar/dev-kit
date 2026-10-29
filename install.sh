#!/usr/bin/env bash
# Install the harness for every agent. Safe to rerun. Replaces only symlinks, never real files.
#   ~/.agents/harness  -> this dir (bin/, library/ live here)
#   dev-* skills       -> ~/.claude/skills, ~/.codex/skills, ~/.agents/skills (read by OpenCode and others)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
link() { # src dest
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ] && [ ! -L "$2" ]; then echo "skip real file: $2"; return; fi
  ln -sfn "$1" "$2"; echo "linked: $2"
}
link "$here" "$HOME/.agents/harness"
for d in "$here"/skills/dev-*; do
  for root in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"; do link "$d" "$root/$(basename "$d")"; done
done
old=$(for l in "$HOME"/.claude/skills/dev-*; do [ -L "$l" ] && readlink "$l" | grep -q '/skills/skills/' && basename "$l"; done)
[ -z "$old" ] || { echo; echo "Older dev-* skills from ~/skills are still installed and still listed every session:"; echo "$old" | sed 's/^/  /'; echo "Remove with: rm -f ~/.claude/skills/<name> ~/.codex/skills/<name>   (the ~/skills repo is untouched)"; }
