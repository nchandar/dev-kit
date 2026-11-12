#!/usr/bin/env bash
# Tests for bin/setup --check under a fake HOME: read-only, stable golden output. Usage: tests/setup.test.sh
set -u
unset TLA2TOOLS  # the check honours it; the harness must not inherit the caller's
src=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# a private clean repo: the sync section must not depend on the caller's tree state or remotes
kit="$t/dev-kit"; setup="$kit/bin/setup"
mkdir -p "$kit/bin" "$kit/library"
cp "$src/bin/setup" "$kit/bin/setup"
cp "$src/library/setup.pins" "$kit/library/setup.pins"
cp -R "$src/skills" "$kit/skills"
git -C "$kit" init -q -b main
git -C "$kit" add -A
git -C "$kit" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm base
base_path=/usr/bin:/bin:/usr/sbin:/sbin  # no ~/.bun/bin, no user tools; every fake comes first

# --- fake binaries: core versions are controlled, optional tools are presence-only
fb="$t/bin"; mkdir -p "$fb"
fake() { { printf '#!/bin/bash\n'; printf '%s\n' "$2"; } > "$fb/$1"; chmod +x "$fb/$1"; }
fake bash 'case "${1:-}" in --version) echo "GNU bash, version 5.2.15(1)-release (test)";; *) exit 1;; esac'
fake git 'case "${1:-}" in --version) echo "git version 2.43.0";; *) exec /usr/bin/git "$@";; esac'
fake perl 'echo "This is perl 5, version 34, subversion 1 (v5.34.1)"'
PY=$(command -v python3); [ -n "$PY" ] || PY=/usr/bin/python3
for n in herdr gh rg java bun claude codex; do fake "$n" 'exit 0'; done
fake python3 "exec $PY \"\$@\""
fake opencode 'case "${1:-} ${2:-}" in "service status") echo "http://127.0.0.1:49374";; *) :;; esac'

# --- a fully set HOME: links, target, Stop-gate, jar, pele and tlachart at ~/.bun/bin
H="$t/home"
mkdir -p "$H/.claude/skills" "$H/.agents/skills" "$H/.local/share/tla" "$H/.agents/dev-kit-tools/node_modules/pele"
mkdir -p "$H/.bun/bin" "$H/.bun/install/global/node_modules/tlachart/src/cli" "$H/.config/opencode"
ln -s "$kit" "$H/.agents/dev-kit"
for d in "$kit"/skills/dev-*; do ln -s "$d" "$H/.claude/skills/${d##*/}"; ln -s "$d" "$H/.agents/skills/${d##*/}"; done
printf '%s\n' '{"experimental":{"todo":true}}' > "$H/.config/opencode/opencode.jsonc"
cat > "$H/.claude/settings.json" <<'EOS'
{
  "permissions": {
    "allow": [
      "Bash(~/.agents/dev-kit/bin/ledger *)",
      "Bash(~/.agents/dev-kit/bin/reconcile *)",
      "Bash(~/.agents/dev-kit/bin/state *)",
      "Bash(~/.agents/dev-kit/bin/setup --check)"
    ]
  },
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "$HOME/.agents/dev-kit/bin/stop-gate"}]}
    ]
  }
}
EOS
: > "$H/.local/share/tla/tla2tools.jar"
printf '{"name":"tlachart","version":"0.1.0"}\n' > "$H/.bun/install/global/node_modules/tlachart/package.json"
printf '#!/bin/bash\nexit 0\n' > "$H/.bun/install/global/node_modules/tlachart/src/cli/main.ts"
chmod +x "$H/.bun/install/global/node_modules/tlachart/src/cli/main.ts"
ln -s ../install/global/node_modules/tlachart/src/cli/main.ts "$H/.bun/bin/tlachart"
skills_n=0; for d in "$kit"/skills/dev-*; do skills_n=$((skills_n+1)); done

run() { HOME="$1" PATH="$2" /bin/bash "$setup" --check > "$3" 2>&1; }
copy_home() { rm -rf "$2"; cp -R "$1" "$2"; }
hash_tree() { ( cd "$1" || exit 1
  find . \( -name .git -o -name .devkit -o -name .lavish \) -prune -o -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort
  find . \( -name .git -o -name .devkit -o -name .lavish \) -prune -o -type l -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do printf '%s -> %s\n' "$p" "$(readlink "$p")"; done
) | cksum; }

# --- fresh HOME with an empty PATH: every required item is missing
mkdir -p "$t/fresh" "$t/empty"
mkdir -p "$t/fresh/.agents/skills"  # codex/opencode links, so a faked CLI in a fresh HOME is not spuriously incomplete
for d in "$kit"/skills/dev-*; do ln -s "$d" "$t/fresh/.agents/skills/${d##*/}"; done
HOME="$t/fresh" PATH="$t/empty" /bin/bash "$setup" > "$t/fresh.out" 2>&1; rc=$?
ok "fresh HOME: exits 1" '[ $rc -eq 1 ]'
for n in bash git perl cli; do ok "fresh HOME: missing $n listed" "grep -q '^missing  $n  ' '$t/fresh.out'"; done
ok "fresh HOME: verdict counts the four" 'grep -qx "verdict: 4 missing" "$t/fresh.out"'

# --- fully set HOME: ready, exits 0
run "$H" "$fb:$base_path" "$t/ready.out"; rc=$?
ok "full HOME: exits 0" '[ $rc -eq 0 ]'
ok "full HOME: verdict ready" 'grep -qx "verdict: ready" "$t/ready.out"'
ok "full HOME: no missing line" '! grep -q "^missing  " "$t/ready.out"'
ok "full HOME: no temp path in output" '! grep -qF "$t" "$t/ready.out"'
ok "tlachart is not on PATH (fallback case)" '[ -z "$(PATH="$fb:$base_path" command -v tlachart 2>/dev/null)" ]'
ok "tlachart found at ~/.bun/bin" 'grep -qx "ok  tlachart  0.1.0" "$t/ready.out"'
ok "default mode is --check" 'HOME="$H" PATH="$fb:$base_path" /bin/bash "$setup" > "$t/default.out" 2>&1; cmp -s "$t/ready.out" "$t/default.out"'

# --- read-only proof: the HOME and the repo hash the same before and after a check
before_h=$(hash_tree "$H"); before_r=$(hash_tree "$kit")
run "$H" "$fb:$base_path" "$t/ro.out"
ok "read-only: HOME tree unchanged" '[ "$before_h" = "$(hash_tree "$H")" ]'
ok "read-only: repo tree unchanged" '[ "$before_r" = "$(hash_tree "$kit")" ]'

# --- tlachart behind the pin: outdated, line format, still optional
H2="$t/home-old"; copy_home "$H" "$H2"
printf '{"name":"tlachart","version":"0.0.9"}\n' > "$H2/.bun/install/global/node_modules/tlachart/package.json"
run "$H2" "$fb:$base_path" "$t/old.out"; rc=$?
ok "outdated tlachart: still exits 0" '[ $rc -eq 0 ]'
ok "outdated tlachart: have/want line" 'grep -qx "outdated  tlachart  have 0.0.9 want 0.1.0" "$t/old.out"'
ok "outdated tlachart: verdict ready" 'grep -qx "verdict: ready" "$t/old.out"'

# --- a newer tlachart is just as outdated as an older one
H6="$t/home-new"; copy_home "$H" "$H6"
printf '{"name":"tlachart","version":"0.2.0"}\n' > "$H6/.bun/install/global/node_modules/tlachart/package.json"
run "$H6" "$fb:$base_path" "$t/newer.out"
ok "newer tlachart: have/want line" 'grep -qx "outdated  tlachart  have 0.2.0 want 0.1.0" "$t/newer.out"'

# --- TLA2TOOLS overrides the default jar location
H7="$t/home-jar"; copy_home "$H" "$H7"; rm "$H7/.local/share/tla/tla2tools.jar"; : > "$t/custom.jar"
TLA2TOOLS="$t/custom.jar" HOME="$H7" PATH="$fb:$base_path" /bin/bash "$setup" > "$t/jar.out" 2>&1; rc=$?
ok "TLA2TOOLS: jar found via the env" '[ $rc -eq 0 ] && grep -qx "ok  tla2tools  found" "$t/jar.out"'

# --- absent claude: its section is skipped, codex satisfies the agent-CLI requirement
pcli="$t/bin-cli"; mkdir -p "$pcli"
for n in bash git perl; do ln -s "$fb/$n" "$pcli/$n"; done
printf '#!/bin/bash\nexit 0\n' > "$pcli/codex"; chmod +x "$pcli/codex"
HOME="$t/fresh" PATH="$pcli:$base_path" /bin/bash "$setup" > "$t/noclaude.out" 2>&1; rc=$?
ok "no claude: exits 0" '[ $rc -eq 0 ]'
ok "no claude: section skipped" 'grep -qx "skipped  claude  not installed" "$t/noclaude.out"'
ok "no claude: codex satisfies core" 'grep -qx "ok  cli  codex" "$t/noclaude.out"'
ok "no claude: verdict ready" 'grep -qx "verdict: ready" "$t/noclaude.out"'

# --- old core versions: bash 3.2+ and git 2.31+ are required
pold="$t/bin-old"; mkdir -p "$pold"
fake_old() { { printf '#!/bin/bash\n'; printf '%s\n' "$2"; } > "$pold/$1"; chmod +x "$pold/$1"; }
fake_old bash 'echo "GNU bash, version 3.1.0(1)-release (test)"'
fake_old git 'case "${1:-}" in --version) echo "git version 2.30.0";; *) exec /usr/bin/git "$@";; esac'
for n in perl; do ln -s "$fb/$n" "$pold/$n"; done
ln -s "$pcli/codex" "$pold/codex"
HOME="$t/fresh" PATH="$pold:$base_path" /bin/bash "$setup" > "$t/oldcore.out" 2>&1; rc=$?
ok "old core: exits 1" '[ $rc -eq 1 ]'
ok "old bash is missing" 'grep -qx "missing  bash  3.1.0 (need 3.2+)" "$t/oldcore.out"'
ok "old git is missing" 'grep -qx "missing  git  2.30.0 (need 2.31+)" "$t/oldcore.out"'
ok "old core: verdict counts two" 'grep -qx "verdict: 2 missing" "$t/oldcore.out"'

ok "unknown flag: rejected" 'HOME="$t/fresh" PATH="$fb:$base_path" /bin/bash "$setup" --bogus >/dev/null 2>&1; [ $? -eq 2 ]'
ok "extra argument: rejected" 'HOME="$t/fresh" PATH="$fb:$base_path" /bin/bash "$setup" --check extra >/dev/null 2>&1; [ $? -eq 2 ]'

# --- one missing claude skill link is reported, and it counts as missing
H5="$t/home-partial"; copy_home "$H" "$H5"
first=$(ls "$H5/.claude/skills" | head -n 1); rm "$H5/.claude/skills/$first"
run "$H5" "$fb:$base_path" "$t/partial.out"; rc=$?
ok "partial links: exits 1" '[ $rc -eq 1 ]'
ok "partial links: count in the line" "grep -Eq '^missing  skills  [0-9]+ of $skills_n linked$' '$t/partial.out'"

# --- the four claude allow rows: a full set is ok, a partial set is optional and never fails; a colon form counts
H10="$t/home-allow"; copy_home "$H" "$H10"
cat > "$H10/.claude/settings.json" <<'EOS'
{
  "permissions": {
    "allow": [
      "Bash(~/.agents/dev-kit/bin/ledger:*)",
      "Bash(~/.agents/dev-kit/bin/state *)"
    ]
  },
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "$HOME/.agents/dev-kit/bin/stop-gate"}]}
    ]
  }
}
EOS
run "$H10" "$fb:$base_path" "$t/allow.out"; rc=$?
ok "allow rows: partial still exits 0" '[ $rc -eq 0 ]'
ok "allow rows: partial is optional with a count" 'grep -qx "optional  allow-rows  2 of 4 (bin/setup --apply; bin/run is not auto-allowed)" "$t/allow.out"'
ok "allow rows: partial verdict stays ready" 'grep -qx "verdict: ready" "$t/allow.out"'

# --- a legacy bin/run allow row stays in place, is not counted, and is warned about
H11="$t/home-legacy-run"; copy_home "$H" "$H11"
"$PY" - "$H11/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p))
cfg["permissions"]["allow"].append("Bash(~/.agents/dev-kit/bin/run *)")
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
PY
run "$H11" "$fb:$base_path" "$t/legacy.out"; rc=$?
ok "legacy run row: exits 0 (a warning is not missing)" '[ $rc -eq 0 ]'
ok "legacy run row: the four required rows still count" 'grep -qx "ok  allow-rows  4 configured (bin/run is not auto-allowed)" "$t/legacy.out"'
ok "legacy run row: reported as a warning, not removed" 'grep -qx "warn  allow-rows  bin/run row present; bin/run is not auto-allowed, remove it" "$t/legacy.out" && grep -qF "Bash(~/.agents/dev-kit/bin/run *)" "$H11/.claude/settings.json"'
H12="$t/home-legacy-colon"; copy_home "$H" "$H12"
"$PY" - "$H12/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p))
cfg["permissions"]["allow"].append("Bash(~/.agents/dev-kit/bin/run:*)")
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
PY
run "$H12" "$fb:$base_path" "$t/legacy-colon.out"
ok "legacy colon run row: also warned" 'grep -qx "warn  allow-rows  bin/run row present; bin/run is not auto-allowed, remove it" "$t/legacy-colon.out"'

# --- golden outputs: stable order, no timestamps, no temp paths
golden() { # label want-rc want-file home path
  local label=$1 wrc=$2 want=$3 home=$4 path=$5 grc gdiff
  HOME="$home" PATH="$path" /bin/bash "$setup" --check > "$t/gold.out" 2>&1; grc=$?
  gdiff=$(diff -u "$want" "$t/gold.out" 2>&1)
  if [ "$grc" -eq "$wrc" ] && [ -z "$gdiff" ] && ! grep -qF "$t" "$t/gold.out"; then
    pass=$((pass+1)); echo "ok   $label"
  else
    fail=$((fail+1)); echo "FAIL $label (rc=$grc want=$wrc)"; printf '%s\n' "$gdiff" | sed 's/^/     /'
  fi
}

cat > "$t/want-all" <<EOF
[core]
ok  bash  5.2.15
ok  git  2.43.0
ok  perl  present
ok  cli  claude codex opencode
[tools]
ok  python3  found
ok  herdr  found
ok  gh  found
ok  rg  found
ok  java  found
ok  tla2tools  found
ok  bun  found
ok  tlachart  0.1.0
ok  pele  found
[claude]
ok  skills  $skills_n linked
ok  home  linked
ok  stop-gate  configured
ok  allow-rows  4 configured (bin/run is not auto-allowed)
[codex]
ok  skills  $skills_n linked
[opencode]
ok  skills  $skills_n linked
ok  todo  enabled
ok  service  up
[sync]
skipped  sync:dev-kit  no upstream
verdict: ready
EOF
golden "golden: all present" 0 "$t/want-all" "$H" "$fb:$base_path"

pnoh="$t/bin-noherdr"; mkdir -p "$pnoh"
for f in "$fb"/*; do case ${f##*/} in herdr) ;; *) ln -s "$f" "$pnoh/${f##*/}";; esac; done
sed 's/^ok  herdr  found$/optional  herdr  not found/' "$t/want-all" > "$t/want-noherdr"
golden "golden: no herdr" 0 "$t/want-noherdr" "$H" "$pnoh:$base_path"

H3="$t/home-notl"; copy_home "$H" "$H3"; rm -rf "$H3/.bun"
sed 's/^ok  tlachart  0.1.0$/optional  tlachart  not found/' "$t/want-all" > "$t/want-notl"
golden "golden: no tlachart" 0 "$t/want-notl" "$H3" "$fb:$base_path"

H4="$t/home-nogate"; copy_home "$H" "$H4"
printf '%s\n' '{"hooks":{}}' > "$H4/.claude/settings.json"
sed 's/^ok  stop-gate  configured$/missing  stop-gate  not configured/; s|^ok  allow-rows  4 configured (bin/run is not auto-allowed)$|optional  allow-rows  0 of 4 (bin/setup --apply; bin/run is not auto-allowed)|; s/^verdict: ready$/verdict: 1 missing/' "$t/want-all" > "$t/want-nogate"
golden "golden: claude without the Stop-gate" 1 "$t/want-nogate" "$H4" "$fb:$base_path"

# --- absent codex or opencode: that section is skipped, the rest still checked
pnoc="$t/bin-nocodex"; mkdir -p "$pnoc"
for f in "$fb"/*; do case ${f##*/} in codex) ;; *) ln -s "$f" "$pnoc/${f##*/}";; esac; done
awk '/^\[codex\]$/{print; print "skipped  codex  not installed"; getline; next} {print}' "$t/want-all" | sed 's/^ok  cli  claude codex opencode$/ok  cli  claude opencode/' > "$t/want-nocodex"
golden "golden: no codex" 0 "$t/want-nocodex" "$H" "$pnoc:$base_path"

pnoo="$t/bin-noopencode"; mkdir -p "$pnoo"
for f in "$fb"/*; do case ${f##*/} in opencode) ;; *) ln -s "$f" "$pnoo/${f##*/}";; esac; done
awk '/^\[opencode\]$/{print; print "skipped  opencode  not installed"; getline; getline; getline; next} {print}' "$t/want-all" | sed 's/^ok  cli  claude codex opencode$/ok  cli  claude codex/' > "$t/want-noopencode"
golden "golden: no opencode" 0 "$t/want-noopencode" "$H" "$pnoo:$base_path"

# --- opencode is optional: a missing todo flag or a down service never fails
H8="$t/home-notodo"; copy_home "$H" "$H8"
printf '%s\n' '{"plugin":[]}' > "$H8/.config/opencode/opencode.jsonc"
run "$H8" "$fb:$base_path" "$t/notodo.out"; rc=$?
ok "todo missing: still exits 0" '[ $rc -eq 0 ]'
ok "todo missing: optional hint line" 'grep -qx "optional  todo  off (set experimental.todo true, then opencode service restart)" "$t/notodo.out"'
ok "todo missing: verdict ready" 'grep -qx "verdict: ready" "$t/notodo.out"'

psd="$t/bin-servicedown"; mkdir -p "$psd"
for f in "$fb"/*; do case ${f##*/} in opencode) ;; *) ln -s "$f" "$psd/${f##*/}";; esac; done
printf '#!/bin/bash\nexit 0\n' > "$psd/opencode"; chmod +x "$psd/opencode"
run "$H" "$psd:$base_path" "$t/servicedown.out"; rc=$?
ok "service down: still exits 0" '[ $rc -eq 0 ]'
ok "service down: optional hint line" 'grep -qx "optional  service  down (run opencode service start once)" "$t/servicedown.out"'
ok "service down: verdict ready" 'grep -qx "verdict: ready" "$t/servicedown.out"'

# --- opencode reads both roots: ~/.claude/skills alone is enough
H9="$t/home-claude-root"; copy_home "$H" "$H9"; rm -rf "$H9/.agents/skills"
run "$H9" "$pnoc:$base_path" "$t/clauderoot.out"; rc=$?
ok "opencode skills: claude root is enough" '[ $rc -eq 0 ] && grep -A1 "^\[opencode\]$" "$t/clauderoot.out" | grep -qx "ok  skills  $skills_n linked"'

# --- a Stop hook must end in /bin/stop-gate; a mere mention does not count
Hg="$t/home-gatemention"; copy_home "$H" "$Hg"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo stop-gate"}]}]}}\n' > "$Hg/.claude/settings.json"
run "$Hg" "$fb:$base_path" "$t/gatemention.out"; rc=$?
ok "stop-gate mention: exits 1" '[ $rc -eq 1 ]'
ok "stop-gate mention: reported missing" 'grep -qx "missing  stop-gate  not configured" "$t/gatemention.out"'

# --- without python3 the grep fallback matches the same ending
pnopy="$t/bin-nopy"; mkdir -p "$pnopy"
for f in "$fb"/*; do case ${f##*/} in python3) ;; *) ln -s "$f" "$pnopy/${f##*/}";; esac; done
run "$H" "$pnopy:$base_path" "$t/nopy.out"; rc=$?
ok "stop-gate fallback: configured without python3" '[ $rc -eq 0 ] && grep -qx "ok  stop-gate  configured" "$t/nopy.out"'

# --- ge: "3" is not >= "3.2"
p3="$t/bin-bash3"; mkdir -p "$p3"
for f in "$fb"/*; do case ${f##*/} in bash) ;; *) ln -s "$f" "$p3/${f##*/}";; esac; done
printf '#!/bin/bash\ncase "${1:-}" in --version) echo "GNU bash, version 3(1)-release (test)";; *) exec /bin/bash "$@";; esac\n' > "$p3/bash"; chmod +x "$p3/bash"
run "$H" "$p3:$base_path" "$t/bash3.out"; rc=$?
ok "bash 3: exists 1" '[ $rc -eq 1 ]'
ok "bash 3: not >= 3.2" 'grep -qx "missing  bash  3 (need 3.2+)" "$t/bash3.out"'

# --- java is probed, not just found: the macOS stub exits nonzero
pj="$t/bin-badjava"; mkdir -p "$pj"
for f in "$fb"/*; do case ${f##*/} in java) ;; *) ln -s "$f" "$pj/${f##*/}";; esac; done
printf '#!/bin/bash\nexit 1\n' > "$pj/java"; chmod +x "$pj/java"
run "$H" "$pj:$base_path" "$t/badjava.out"; rc=$?
ok "broken java: still exits 0" '[ $rc -eq 0 ]'
ok "broken java: reported optional, not found" 'grep -qx "optional  java  not found" "$t/badjava.out"'

# --- the frozen copy deletes itself only under the mktemp name pattern
leak="$t/leaked-setup"; cp "$kit/bin/setup" "$leak"; chmod +x "$leak"
HOME="$H" PATH="$fb:$base_path" DEVKIT_SETUP_FROZEN="$leak" DEVKIT_SETUP_HOME="$kit" /bin/bash "$leak" --check > "$t/leak.out" 2>&1
ok "frozen: a non-mktemp path is not deleted" '[ -f "$leak" ]'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
