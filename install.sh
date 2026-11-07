#!/usr/bin/env bash
# Install dev-kit for every agent. Safe to rerun. Replaces only symlinks, never real files.
# Prunes dangling dev-* links into this repo's skills/ (renamed or removed skills); nothing else is removed.
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
# stale = symlink, dev-* name, target inside our skills/, target gone; anything else is not ours to delete
for root in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"; do
  for e in "$root"/dev-*; do
    [ -L "$e" ] && [ ! -e "$e" ] || continue
    case $(readlink "$e") in "$here"/skills/*) rm "$e"; echo "pruned stale: $e";; esac
  done
done

# OpenCode shows a worker's checklist in its side panel only with experimental.todo. Additive: absent keys only, plain JSON only.
oc_dir="$HOME/.config/opencode"
if [ -d "$oc_dir" ] || command -v opencode >/dev/null 2>&1; then
  link "$here/opencode/commands/dev-mode.md" "$oc_dir/commands/dev-mode.md"  # adds the /dev-mode command to opencode's picker
  # migration: drop only our old /dev link; a real file or a link elsewhere stays.
  if [ -L "$oc_dir/commands/dev.md" ] && [ "$(readlink "$oc_dir/commands/dev.md")" = "$here/opencode/commands/dev.md" ]; then
    rm "$oc_dir/commands/dev.md"; echo "migrated: $oc_dir/commands/dev.md -> dev-mode.md"
  fi
  oc_cfg="$oc_dir/opencode.jsonc"; [ -e "$oc_cfg" ] || [ ! -e "$oc_dir/opencode.json" ] || oc_cfg="$oc_dir/opencode.json"
  hint="set \"experimental\": {\"todo\": true} in $oc_cfg yourself, then run: opencode service restart"
  if ! command -v python3 >/dev/null 2>&1; then echo "opencode: python3 not found; $hint"
  else
    mkdir -p "$oc_dir"
    res=$(python3 - "$oc_cfg" <<'PY'
import json, os, sys
p = sys.argv[1]
try:
    cfg = json.load(open(p)) if os.path.exists(p) else {"$schema": "https://opencode.ai/config.json"}
except ValueError:
    print("skip"); sys.exit()
exp = cfg.setdefault("experimental", {})
if "todo" in exp:
    print("same"); sys.exit()
exp["todo"] = True
tmp = p + ".tmp"
json.dump(cfg, open(tmp, "w"), indent=2); open(tmp, "a").write("\n"); os.replace(tmp, p)
print("set")
PY
)
    case $res in
      set) echo "opencode: enabled experimental.todo in $oc_cfg; apply it with: opencode service restart";;
      skip) echo "opencode: $oc_cfg has comments or is not plain JSON, left untouched; $hint";;
    esac
  fi
fi

# Parent Stop gate: printed only, never applied; the user decides.
cat <<EOF
stop-gate: merge this Stop hook into ~/.claude/settings.json to block a parent while its workers are unaccepted:
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$HOME/.agents/dev-kit/bin/stop-gate","timeout":10}]}]}}
EOF
