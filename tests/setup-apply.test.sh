#!/usr/bin/env bash
# Tests for bin/setup --apply under a fake HOME: prompts, fake installers, backup, idempotent, symlink-safe.
# Sections are independent (own HOME, own log, own count) and run side by side in four groups; their
# logs merge in a fixed order below, so the output and the passed/failed count stay deterministic.
# Usage: tests/setup-apply.test.sh
set -u
unset TLA2TOOLS  # the check honours it; the harness must not inherit the caller's
src=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# a private clean repo with no upstream: sync never reaches the caller's tree or a network remote
kit="$t/dev-kit"; setup="$kit/bin/setup"
mkdir -p "$kit"
cp -R "$src/bin" "$src/skills" "$src/library" "$src/opencode" "$kit/"
cp "$src/install.sh" "$kit/install.sh"; chmod +x "$kit/install.sh"
git -C "$kit" init -q -b main
git -C "$kit" add -A
git -C "$kit" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm base
PY=$(command -v python3); [ -n "$PY" ] || PY=/usr/bin/python3
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
mode_of() { if stat -f %Lp "$1" >/dev/null 2>&1; then stat -f %Lp "$1"; else stat -c %a "$1"; fi; }
# the fake curl writes this body; the pin must hash it
printf 'jar\n' > "$t/fake-tla.jar"
grep -v '^tla2tools ' "$kit/library/setup.pins" > "$t/pins.base"
printf 'tla2tools 9.9.9 %s\n' "$(sha_of "$t/fake-tla.jar")" >> "$t/pins.base"
mv "$t/pins.base" "$kit/library/setup.pins"
git -C "$kit" add -A
git -C "$kit" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm pin

# --- a minimal system PATH, so a real java/brew/bun/tlachart can never leak in
sys="$t/sys"; mkdir -p "$sys"
for n in sh uname dirname basename mkdir cp mv diff awk sed grep head cut cat ln readlink pwd \
         chmod date mktemp rm find sort cksum tr wc env; do
  p=$(command -v "$n") && ln -s "$p" "$sys/$n"
done
for n in shasum sha256sum; do p=$(command -v "$n") && ln -s "$p" "$sys/$n"; done
base_path="$sys"

# --- fake CLIs: every installer is a stub that logs; nothing real is installed
fb="$t/bin"; mkdir -p "$fb"
fake() { { printf '#!/bin/bash\n'; printf '%s\n' "$2"; } > "$fb/$1"; chmod +x "$fb/$1"; }
fake bash 'case "${1:-}" in --version) echo "GNU bash, version 5.2.15(1)-release (test)";; *) exec /bin/bash "$@";; esac'
fake git 'case "${1:-}" in --version) echo "git version 2.43.0";; *) exec /usr/bin/git "$@";; esac'
fake perl 'echo "This is perl 5, version 34, subversion 1 (v5.34.1)"'
fake claude ':'
fake codex ':'
fake opencode 'case "${1:-} ${2:-}" in "service status") echo "http://127.0.0.1:49374";; *) :;; esac'
ln -s "$PY" "$fb/python3"

# fake brew creates the tools it "installs" inside $FAKE_INSTALL, which is on PATH
fake brew 'printf "brew %s\n" "$*" >> "$FAKE_LOG"
case $* in
  "install bun") cp "$FAKE_SRC" "$FAKE_INSTALL/bun"; chmod +x "$FAKE_INSTALL/bun";;
  "install openjdk") printf "#!/bin/bash\n:\n" > "$FAKE_INSTALL/java"; chmod +x "$FAKE_INSTALL/java";;
esac'
fake curl 'printf "curl %s\n" "$*" >> "$FAKE_LOG"
url=$*
out=
while [ $# -gt 0 ]; do case $1 in -o) out=$2; shift 2;; *) shift;; esac; done
case "$url" in
  *bun.sh/install*)
    if [ "${FAKE_CURL_FAIL:-}" = bun ]; then printf "curl: (7) failed\n" >&2; exit 7; fi
    [ -n "$out" ] && printf "#!/bin/bash\nprintf ran > \"%s\"\n" "$FAKE_BUN_RAN" > "$out";;
  *) [ -n "$out" ] && printf "jar\n" > "$out";;
esac'

# the bun stub brew copies in: logs, installs tlachart under ~/.bun, pele under the cwd
cat > "$t/bun.real" <<'S'
#!/bin/bash
printf 'bun %s cwd=%s\n' "$*" "$PWD" >> "$FAKE_LOG"
case $1 in
  add)
    case $2 in
      -g)
        case $3 in
          tlachart@*)
            v=${3#*@}; r="$HOME/.bun/install/global/node_modules/tlachart"
            mkdir -p "$r/src" "$HOME/.bun/bin"
            printf '{"name":"tlachart","version":"%s"}\n' "$v" > "$r/package.json"
            printf '#!/bin/bash\n:\n' > "$r/src/main.js"
            chmod +x "$r/src/main.js"
            ln -sfn ../install/global/node_modules/tlachart/src/main.js "$HOME/.bun/bin/tlachart";;
        esac;;
      pele@*)
        v=${2#*@}; mkdir -p node_modules/pele
        printf '{"name":"pele","version":"%s"}\n' "$v" > node_modules/pele/package.json;;
    esac;;
esac
S
chmod +x "$t/bun.real"
toolsbin="$t/toolsbin"; mkdir -p "$toolsbin"
printf '#!/bin/bash\n:\n' > "$toolsbin/bun"; chmod +x "$toolsbin/bun"
printf '#!/bin/bash\n:\n' > "$toolsbin/java"; chmod +x "$toolsbin/java"

run_with() { # setup home path log install-src
  env HOME="$2" PATH="$3" FAKE_LOG="$4" FAKE_INSTALL="$5" FAKE_SRC="$t/bun.real" FAKE_BUN_RAN="$t/bun-ran" /bin/bash "$1" --apply
}
run_apply() { run_with "$setup" "$1" "$2" "$3" "$4"; }
hash_tree() { ( cd "$1" || exit 1
  find . \( -name .git -o -name .devkit -o -name .lavish \) -prune -o -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort
  find . \( -name .git -o -name .devkit -o -name .lavish \) -prune -o -type l -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do printf '%s -> %s\n' "$p" "$(readlink "$p")"; done
) | cksum; }
backups() { find "$1" -name '*.devkit-bak-*' 2>/dev/null | wc -l | tr -d ' '; }
allow_rows() { "$PY" -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1])).get("permissions",{}).get("allow",[])))' "$1" 2>/dev/null; }
todo_flag() { "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("experimental",{}).get("todo"))' "$1" 2>/dev/null; }
gate_hooks() { "$PY" -c 'import json,sys
cfg=json.load(open(sys.argv[1])); n=0
for g in (cfg.get("hooks") or {}).get("Stop") or []:
    for h in (g.get("hooks") or []):
        n += 1 if str(h.get("command","")).endswith("/bin/stop-gate") else 0
print(n)' "$1" 2>/dev/null; }
has_row() { allow_rows "$1" | while IFS= read -r r; do [ "$r" = "$2" ] && printf 'yes\n'; done; }

make_ready_home() { # dest: links + tools present, settings behind a symlink, todo absent
  h=$1
  mkdir -p "$h/.claude/skills" "$h/.agents/skills" "$h/.agents/dev-kit-tools/node_modules/pele" \
    "$h/.local/share/tla" "$h/.bun/install/global/node_modules/tlachart/src" "$h/.bun/bin" \
    "$h/.config/opencode" "$h/dotfiles"
  ln -s "$kit" "$h/.agents/dev-kit"
  for d in "$kit"/skills/dev-*; do
    ln -s "$d" "$h/.claude/skills/${d##*/}"
    ln -s "$d" "$h/.agents/skills/${d##*/}"
  done
  : > "$h/.local/share/tla/tla2tools.jar"
  printf '{"plugin":[]}\n' > "$h/.config/opencode/opencode.jsonc"
  printf '{"name":"tlachart","version":"0.1.0"}\n' > "$h/.bun/install/global/node_modules/tlachart/package.json"
  printf '#!/bin/bash\n:\n' > "$h/.bun/install/global/node_modules/tlachart/src/main.js"
  chmod +x "$h/.bun/install/global/node_modules/tlachart/src/main.js"
  ln -s ../install/global/node_modules/tlachart/src/main.js "$h/.bun/bin/tlachart"
  printf '{"permissions":{"allow":["Bash(git status:*)"]}}\n' > "$h/dotfiles/claude-settings.json"
  ln -s ../dotfiles/claude-settings.json "$h/.claude/settings.json"
}

merge_settings() { # home: the exact file --apply would write, so no settings prompt remains
  h=$1
  cat > "$h/dotfiles/claude-settings.json" <<EOS
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(~/.agents/dev-kit/bin/ledger *)",
      "Bash(~/.agents/dev-kit/bin/reconcile *)",
      "Bash(~/.agents/dev-kit/bin/state *)",
      "Bash(~/.agents/dev-kit/bin/setup --check)"
    ]
  },
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "$h/.agents/dev-kit/bin/stop-gate", "timeout": 10}]}
    ]
  }
}
EOS
}

# --- fixtures shared read-only by the parallel sections: one ready HOME to copy, and the
# --- per-OS PATHs the installer branches need (built once so no section waits on another)
tmpl="$t/tmpl-home"; make_ready_home "$tmpl"
nobrew="$t/nobrew"; mkdir -p "$nobrew"
for f in "$fb"/*; do case ${f##*/} in brew) ;; *) ln -s "$f" "$nobrew/${f##*/}";; esac; done
linuxbin="$t/linuxbin"; mkdir -p "$linuxbin"
printf '#!/bin/bash\necho Linux\n' > "$linuxbin/uname"; chmod +x "$linuxbin/uname"
darwinbin="$t/darwinbin"; mkdir -p "$darwinbin"
printf '#!/bin/bash\necho Darwin\n' > "$darwinbin/uname"; chmod +x "$darwinbin/uname"

sec_fresh() {
  # --- fresh HOME: yes accepts every prompt and the fakes install in order
  H="$t/fresh"; mkdir -p "$H" "$t/inst1"; log="$t/t1.log"; : > "$log"
  yes | run_apply "$H" "$fb:$t/inst1:$base_path" "$log" "$t/inst1" > "$t/fresh.out" 2>&1; rc=$?
  ok "fresh: exits 0" '[ $rc -eq 0 ]'
  ok "fresh: final verdict ready" '[ "$(tail -n 1 "$t/fresh.out")" = "verdict: ready" ]'
  ok "fresh: install.sh linked the home and a skill" '[ -L "$H/.agents/dev-kit" ] && [ -f "$H/.claude/skills/dev-mode/SKILL.md" ]'
  ok "fresh: brew installed bun" 'grep -qx "brew install bun" "$log" && [ -x "$t/inst1/bun" ]'
  ok "fresh: bun installed tlachart at the pin" 'grep -q "bun add -g tlachart@0.1.0" "$log" && [ -x "$H/.bun/bin/tlachart" ]'
  ok "fresh: pele installed in the dev-kit tools dir" 'grep -q "bun add pele@1.13.0 cwd=.*dev-kit-tools" "$log" && [ -d "$H/.agents/dev-kit-tools/node_modules/pele" ]'
  ok "fresh: brew installed java" 'grep -qx "brew install openjdk" "$log" && [ -x "$t/inst1/java" ]'
  ok "fresh: curl downloaded the jar" 'grep -q "curl .*tla2tools.jar" "$log" && [ -f "$H/.local/share/tla/tla2tools.jar" ]'
  ok "fresh: the jar came from the pinned release" 'grep -qF "releases/download/v9.9.9/tla2tools.jar" "$t/fresh.out" && ! grep -qF "releases/latest" "$t/fresh.out"'
  ok "fresh: the links prompt names the opencode todo flag" 'grep -q "enables the opencode todo flag when opencode is present" "$t/fresh.out"'
  ok "fresh: todo enabled" '[ "$(todo_flag "$H/.config/opencode/opencode.jsonc")" = True ]'
  nb=$(grep -n 'brew install bun' "$log" | head -n 1 | cut -d: -f1)
  nt=$(grep -n 'bun add -g tlachart@0.1.0' "$log" | head -n 1 | cut -d: -f1)
  np=$(grep -n 'bun add pele@1.13.0' "$log" | head -n 1 | cut -d: -f1)
  nc=$(grep -n 'curl .*tla2tools.jar' "$log" | head -n 1 | cut -d: -f1)
  ok "fresh: installers run in order (bun, tlachart, pele, jar)" '[ -n "$nb" ] && [ -n "$nt" ] && [ -n "$np" ] && [ -n "$nc" ] && [ "$nb" -lt "$nt" ] && [ "$nt" -lt "$np" ] && [ "$np" -lt "$nc" ]'
  ok "fresh: prompts show the exact commands" 'grep -qF "brew install bun" "$t/fresh.out" && grep -qF "bun add -g tlachart@0.1.0" "$t/fresh.out" && grep -qF "curl -fsSL" "$t/fresh.out" && grep -qF "https://github.com/tlaplus/tlaplus/releases/download/v9.9.9/tla2tools.jar" "$t/fresh.out" && grep -qF "install.sh" "$t/fresh.out"'
  for r in 'Bash(~/.agents/dev-kit/bin/ledger *)' 'Bash(~/.agents/dev-kit/bin/reconcile *)' 'Bash(~/.agents/dev-kit/bin/state *)' 'Bash(~/.agents/dev-kit/bin/setup --check)'; do
    ok "fresh: settings has $r" '[ -n "$(has_row "$H/.claude/settings.json" "$r")" ]'
  done
  ok "fresh: settings has no bin/run allow row (raw)" '! grep -qF "bin/run *)" "$H/.claude/settings.json"'
  ok "fresh: apply says bin/run is not auto-allowed" 'grep -qF "bin/run is not auto-allowed" "$t/fresh.out"'
  ok "fresh: Stop-gate hook added" 'grep -q "stop-gate" "$H/.claude/settings.json"'
}

sec_symlink() {
  # --- ready HOME, settings behind a symlink: one prompt per write, backup, idempotent
  H2="$t/home2"; cp -R "$tmpl" "$H2"; log="$t/t2.log"; : > "$log"
  yes | run_apply "$H2" "$fb:$toolsbin:$base_path" "$log" "$t/inst2" > "$t/t2.out" 2>&1; rc=$?
  ok "symlink: exits 0" '[ $rc -eq 0 ]'
  ok "symlink: verdict ready" '[ "$(tail -n 1 "$t/t2.out")" = "verdict: ready" ]'
  ok "symlink: the settings link is kept" '[ -L "$H2/.claude/settings.json" ]'
  ok "symlink: the link still points at the dotfiles file" '[ "$(readlink "$H2/.claude/settings.json")" = ../dotfiles/claude-settings.json ]'
  ok "symlink: the target got the four rows" '[ "$(allow_rows "$H2/dotfiles/claude-settings.json" | wc -l | tr -d " ")" -eq 5 ]'
  ok "symlink: the existing allow row is kept" '[ -n "$(has_row "$H2/dotfiles/claude-settings.json" "Bash(git status:*)")" ]'
  ok "symlink: one backup next to the settings file" '[ "$(find "$H2/.claude" -maxdepth 1 -name "settings.json.devkit-bak-*" | wc -l | tr -d " ")" = 1 ]'
  ok "symlink: todo enabled in the jsonc" '[ "$(todo_flag "$H2/.config/opencode/opencode.jsonc")" = True ]'
  for bad in 'Bash(*)' '--dangerously' '/spawn' '/verify' '/push' 'bin/run *)'; do
    ok "symlink: never adds $bad" '! grep -qF -- "$bad" "$H2/dotfiles/claude-settings.json"'
  done
  h1=$(hash_tree "$H2"); b1=$(backups "$H2"); n1=$(wc -l < "$t/t2.out" | tr -d ' ')
  yes | run_apply "$H2" "$fb:$toolsbin:$base_path" "$log" "$t/inst2" > "$t/t2b.out" 2>&1; rc=$?
  ok "second run: exits 0" '[ $rc -eq 0 ]'
  ok "second run: verdict ready" '[ "$(tail -n 1 "$t/t2b.out")" = "verdict: ready" ]'
  ok "second run: the HOME tree is unchanged" '[ "$h1" = "$(hash_tree "$H2")" ]'
  ok "second run: no new backup" '[ "$(backups "$H2")" = "$b1" ]'
  ok "second run: no prompts" '! grep -Eq "apply\? \[y/N\]|run\? \[y/N\]" "$t/t2b.out"'
}

sec_n() {
  # --- n skips every write: nothing is created, the verdict says not ready
  H3="$t/home3"; mkdir -p "$H3" "$t/inst3"; log="$t/t3.log"; : > "$log"
  env HOME="$H3" PATH="$fb:$t/inst3:$base_path" /bin/bash "$setup" --check > "$t/t3.check" 2>&1
  yes n | run_apply "$H3" "$fb:$t/inst3:$base_path" "$log" "$t/inst3" > "$t/t3.out" 2>&1; rc=$?
  ok "n: exits 1" '[ $rc -eq 1 ]'
  ok "n: apply starts with the same check output" 'awk "/^\[apply\]/{exit} {print}" "$t/t3.out" > "$t/t3.first"; cmp -s "$t/t3.check" "$t/t3.first"'
  ok "n: verdict is not ready" '[ "$(tail -n 1 "$t/t3.out")" != "verdict: ready" ]'
  ok "n: no links created" '[ ! -L "$H3/.agents/dev-kit" ]'
  ok "n: no bun, no tlachart" '[ ! -d "$H3/.bun" ]'
  ok "n: no settings file" '[ ! -e "$H3/.claude/settings.json" ]'
  ok "n: no opencode config" '[ ! -e "$H3/.config/opencode" ]'
  ok "n: no jar" '[ ! -e "$H3/.local/share/tla/tla2tools.jar" ]'
  ok "n: no backup" '[ "$(backups "$H3")" = 0 ]'
  ok "n: every finding was shown and skipped" 'grep -qF "install.sh" "$t/t3.out" && grep -qF "brew install bun" "$t/t3.out" && grep -qF "curl -fsSL" "$t/t3.out" && grep -q "skipped" "$t/t3.out"'
}

sec_linux() {
  # --- Linux without brew: the bun curl installer is printed, never run
  H8="$t/home8"; mkdir -p "$H8" "$t/inst8"
  log="$t/t8.log"; : > "$log"
  yes | run_apply "$H8" "$linuxbin:$nobrew:$base_path" "$log" "$t/inst8" > "$t/t8.out" 2>&1
  ok "linux: the bun installer is printed" 'grep -qF "curl -fsSL -o" "$t/t8.out" && grep -qF "https://bun.sh/install" "$t/t8.out" && grep -qF "bash <file>" "$t/t8.out" && ! grep -qF "| bash" "$t/t8.out"'
  ok "linux: the bun installer is not run" 'grep -q "linux: printed only" "$t/t8.out" && ! grep -q "bun.sh/install" "$log"'
}

sec_macos() {
  # --- macOS without brew: the installer is downloaded, checked, then run as a file
  H9="$t/home9"; mkdir -p "$H9"
  log="$t/t9.log"; : > "$log"; rm -f "$t/bun-ran"
  yes | run_apply "$H9" "$darwinbin:$nobrew:$base_path" "$log" "$t/inst9" > "$t/t9.out" 2>&1
  ok "macos: the curl bun installer runs after y" 'grep -q "curl -fsSL -o .*bun.sh/install" "$log"'
  ok "macos: the downloaded installer runs as a file" '[ -f "$t/bun-ran" ]'
}

sec_curl_fail() {
  # --- a failed download is reported and no installer runs
  H16="$t/home16"; mkdir -p "$H16"
  log="$t/t16.log"; : > "$log"; rm -f "$t/bun-ran16"
  yes | env HOME="$H16" PATH="$darwinbin:$nobrew:$base_path" FAKE_LOG="$log" FAKE_INSTALL="$t/inst16" \
    FAKE_SRC="$t/bun.real" FAKE_BUN_RAN="$t/bun-ran16" FAKE_CURL_FAIL=bun /bin/bash "$setup" --apply > "$t/t16.out" 2>&1
  ok "curl failure: says the download failed" 'grep -q "download failed" "$t/t16.out"'
  ok "curl failure: no installer ran" '[ ! -e "$t/bun-ran16" ]'
}

sec_jar_mismatch() {
  # --- a jar whose hash does not match the pin is refused (its own kit copy: pins are shared state)
  k15="$t/kit15"; cp -R "$kit" "$k15"
  H15="$t/home15"; mkdir -p "$H15"
  grep -v '^tla2tools ' "$k15/library/setup.pins" > "$t/pins15"
  printf 'tla2tools 9.9.9 0000000000000000000000000000000000000000000000000000000000000000\n' >> "$t/pins15"
  mv "$t/pins15" "$k15/library/setup.pins"
  log="$t/t15.log"; : > "$log"
  yes | run_with "$k15/bin/setup" "$H15" "$fb:$t/inst15:$base_path" "$log" "$t/inst15" > "$t/t15.out" 2>&1
  ok "jar mismatch: the jar is refused" '[ ! -e "$H15/.local/share/tla/tla2tools.jar" ]'
  ok "jar mismatch: the note says checksum mismatch" 'grep -q "checksum mismatch" "$t/t15.out"'
}

sec_utf8() {
  # --- settings keep their encoding, mode and diff labels; opencode is backed up; a mere mention is not a hook
  H11="$t/home-utf8"; cp -R "$tmpl" "$H11"; log="$t/t11.log"; : > "$log"
  cat > "$H11/dotfiles/claude-settings.json" <<EOS
{
  "contextMarker": "CTX3",
  "statusLine": {
    "text": "café"
  },
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(~/.agents/dev-kit/bin/ledger *)",
      "Bash(~/.agents/dev-kit/bin/reconcile *)",
      "Bash(~/.agents/dev-kit/bin/state *)",
      "Bash(~/.agents/dev-kit/bin/run *)"
    ]
  },
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "echo stop-gate"}]}
    ]
  }
}
EOS
  chmod 644 "$H11/dotfiles/claude-settings.json"
  yes | run_apply "$H11" "$fb:$toolsbin:$base_path" "$log" "$t/inst11" > "$t/t11.out" 2>&1; rc=$?
  ok "utf8: exits 0" '[ $rc -eq 0 ]'
  ok "utf8: non-ASCII text is kept literally" 'grep -qF "café" "$H11/dotfiles/claude-settings.json" && ! grep -q "\\\\u00e9" "$H11/dotfiles/claude-settings.json"'
  ok "diff: stable a/ and b/ labels" 'grep -qF -- "--- a/settings.json" "$t/t11.out" && grep -qF -- "+++ b/settings.json" "$t/t11.out"'
  ok "diff: one line of context" '! grep -q "CTX3" "$t/t11.out"'
  ok "mode: the settings file keeps 0644" '[ "$(mode_of "$H11/dotfiles/claude-settings.json")" = 644 ]'
  ok "utf8: an existing bin/run row is left alone" 'grep -qF "Bash(~/.agents/dev-kit/bin/run *)" "$H11/dotfiles/claude-settings.json"'
  ok "utf8: apply warns that bin/run is not auto-allowed" 'grep -qF "warn  allow-rows  bin/run row present; bin/run is not auto-allowed, remove it" "$t/t11.out"'
  ok "opencode: the config is backed up once" '[ "$(find "$H11/.config/opencode" -name "opencode.jsonc.devkit-bak-*" | wc -l | tr -d " ")" = 1 ]'
  ok "stop-gate: a mention does not count, the real hook is added" '[ "$(gate_hooks "$H11/dotfiles/claude-settings.json")" = 1 ]'
}

sec_stderr() {
  # --- a failing step's stderr reaches the user
  H14="$t/home14"; mkdir -p "$H14" "$t/badbrew"
  for f in "$fb"/*; do case ${f##*/} in brew) ;; *) ln -s "$f" "$t/badbrew/${f##*/}";; esac; done
  printf '#!/bin/bash\nprintf "brew-broke\\n" >&2\nexit 1\n' > "$t/badbrew/brew"; chmod +x "$t/badbrew/brew"
  log="$t/t14.log"; : > "$log"
  yes | run_apply "$H14" "$t/badbrew:$t/inst14:$base_path" "$log" "$t/inst14" > "$t/t14.out" 2>&1
  ok "stderr: a failing brew's message reaches the user" 'grep -q "brew-broke" "$t/t14.out"'
}

sec_broken_java() {
  # --- java is probed, not just found
  H13="$t/home13"; cp -R "$tmpl" "$H13"; log="$t/t13.log"; : > "$log"
  badjava="$t/badjava"; mkdir -p "$badjava"
  printf '#!/bin/bash\nexit 1\n' > "$badjava/java"; chmod +x "$badjava/java"
  yes | run_apply "$H13" "$fb:$badjava:$base_path" "$log" "$t/inst13" > "$t/t13.out" 2>&1
  ok "broken java: apply installs a JDK" 'grep -qx "brew install openjdk" "$log"'
}

sec_todo_false() {
  # --- an explicit todo=false is respected and the file is untouched
  H4="$t/home4"; cp -R "$tmpl" "$H4"; merge_settings "$H4"; log="$t/t4.log"; : > "$log"
  printf '{"experimental":{"todo":false}}\n' > "$H4/.config/opencode/opencode.jsonc"
  cp "$H4/.config/opencode/opencode.jsonc" "$t/todo-false.before"
  h4=$(hash_tree "$H4")
  yes | run_apply "$H4" "$fb:$toolsbin:$base_path" "$log" "$t/inst4" > "$t/t4.out" 2>&1; rc=$?
  ok "todo=false: exits 0" '[ $rc -eq 0 ]'
  ok "todo=false: the config is unchanged" 'cmp -s "$H4/.config/opencode/opencode.jsonc" "$t/todo-false.before"'
  ok "todo=false: the user is told it is respected" 'grep -q "explicitly false" "$t/t4.out"'
  ok "todo=false: the HOME tree is unchanged" '[ "$h4" = "$(hash_tree "$H4")" ]'
}

sec_commented() {
  # --- a commented jsonc is left untouched, with a hint
  H5="$t/home5"; cp -R "$tmpl" "$H5"; merge_settings "$H5"; log="$t/t5.log"; : > "$log"
  printf '{\n  // mine\n  "plugin": []\n}\n' > "$H5/.config/opencode/opencode.jsonc"
  cp "$H5/.config/opencode/opencode.jsonc" "$t/todo-comment.before"
  yes | run_apply "$H5" "$fb:$toolsbin:$base_path" "$log" "$t/inst5" > "$t/t5.out" 2>&1
  ok "commented jsonc: left untouched" 'cmp -s "$H5/.config/opencode/opencode.jsonc" "$t/todo-comment.before"'
  ok "commented jsonc: hint printed" 'grep -q "left untouched" "$t/t5.out"'
}

sec_bad_settings() {
  # --- settings that are not plain JSON: untouched, no backup, hint
  H6="$t/home6"; cp -R "$tmpl" "$H6"; log="$t/t6.log"; : > "$log"
  printf '{ not json\n' > "$H6/dotfiles/claude-settings.json"
  cp "$H6/dotfiles/claude-settings.json" "$t/settings-bad.before"; b6=$(find "$H6/.claude" -maxdepth 1 -name 'settings.json.devkit-bak-*' | wc -l | tr -d ' ')
  yes | run_apply "$H6" "$fb:$toolsbin:$base_path" "$log" "$t/inst6" > "$t/t6.out" 2>&1; rc=$?
  ok "bad settings: exits 1 (Stop-gate still missing)" '[ $rc -eq 1 ]'
  ok "bad settings: the file is untouched" 'cmp -s "$H6/dotfiles/claude-settings.json" "$t/settings-bad.before"'
  ok "bad settings: no backup" '[ "$(find "$H6/.claude" -maxdepth 1 -name "settings.json.devkit-bak-*" | wc -l | tr -d " ")" = "$b6" ]'
  ok "bad settings: hint printed" 'grep -q "left untouched" "$t/t6.out"'
}

sec_kill() {
  # --- killed between the backup and the write: the original is intact
  H7="$t/home7"; cp -R "$tmpl" "$H7"; log="$t/t7.log"; : > "$log"
  printf '{"experimental":{"todo":true}}\n' > "$H7/.config/opencode/opencode.jsonc"
  cp "$H7/dotfiles/claude-settings.json" "$t/settings-kill.before"
  killbin="$t/killbin"; mkdir -p "$killbin"
  cat > "$killbin/mv" <<'S'
#!/bin/bash
last=
for a in "$@"; do last=$a; done
case $last in *settings.json) kill -9 "$PPID"; exit 1;; esac
exec /bin/mv "$@"
S
  chmod +x "$killbin/mv"
  # the killed pipeline's job-control chatter (PIDs) goes aside so the merged log stays deterministic
  { yes | env HOME="$H7" PATH="$killbin:$fb:$toolsbin:$base_path" FAKE_LOG="$log" FAKE_INSTALL="$t/inst7" FAKE_SRC="$t/bun.real" /bin/bash "$setup" --apply > "$t/t7.out"; } 2> "$t/t7.err"; rc=$?
  ok "kill mid-write: the run exits nonzero" '[ $rc -ne 0 ]'
  ok "kill mid-write: the original settings are intact" 'cmp -s "$H7/dotfiles/claude-settings.json" "$t/settings-kill.before"'
  ok "kill mid-write: the backup was already written" '[ "$(backups "$H7")" = 1 ]'
}

sec_extra_args() {
  # --- arg handling stays strict
  mkdir -p "$t/home-extra"
  ok "extra args with --apply: rejected" 'env HOME="$t/home-extra" PATH="$fb:$base_path" /bin/bash "$setup" --apply extra >/dev/null 2>&1; [ $? -eq 2 ]'
}

sec_symlinked() {
  # --- symlinked configs: both backups land beside the link the user sees, never in its target repo
  H17="$t/home17"; cp -R "$tmpl" "$H17"
  rm -f "$H17/.config/opencode/opencode.jsonc"
  printf '{"plugin":[]}\n' > "$H17/dotfiles/opencode.jsonc"
  ln -s ../../dotfiles/opencode.jsonc "$H17/.config/opencode/opencode.jsonc"
  log="$t/t17.log"; : > "$log"
  yes | run_apply "$H17" "$fb:$toolsbin:$base_path" "$log" "$t/inst17" > "$t/t17.out" 2>&1; rc=$?
  ok "symlinked configs: exits 0" '[ $rc -eq 0 ]'
  ok "symlinked configs: the settings backup sits beside the link" '[ "$(find "$H17/.claude" -maxdepth 1 -name "settings.json.devkit-bak-*" | wc -l | tr -d " ")" = 1 ]'
  ok "symlinked configs: the opencode backup sits beside the link" '[ "$(find "$H17/.config/opencode" -maxdepth 1 -name "opencode.jsonc.devkit-bak-*" | wc -l | tr -d " ")" = 1 ]'
  ok "symlinked configs: no backup lands in the link target repo" '[ "$(backups "$H17/dotfiles")" = 0 ]'
  ok "symlinked configs: both links are kept" '[ -L "$H17/.claude/settings.json" ] && [ -L "$H17/.config/opencode/opencode.jsonc" ]'
  ok "symlinked configs: both targets got the change" '[ "$(allow_rows "$H17/dotfiles/claude-settings.json" | wc -l | tr -d " ")" -eq 5 ] && [ "$(todo_flag "$H17/dotfiles/opencode.jsonc")" = True ]'
  b17=$(backups "$H17")
  yes | run_apply "$H17" "$fb:$toolsbin:$base_path" "$log" "$t/inst17" > "$t/t17b.out" 2>&1
  ok "symlinked configs: a rerun adds no backup" '[ "$(backups "$H17")" = "$b17" ]'
}

# --- one section: own HOME, own log, own count; a section that dies without a count fails the suite
section() { # name fn: counters named past the section bodies so a body cannot clobber them
  ( sec_pass=0; sec_fail=0
    ok() { if eval "$2"; then sec_pass=$((sec_pass+1)); echo "ok   $1"; else sec_fail=$((sec_fail+1)); echo "FAIL $1   [$2]"; fi; }
    if type "$2" >/dev/null 2>&1; then "$2"; else echo "FAIL section $1 has no such section function"; sec_fail=1; fi
    echo "$sec_pass $sec_fail" > "$t/$1.cnt" ) > "$t/$1.log" 2>&1
}
group() { for s in "$@"; do section "$s" "sec_$s"; done; }

# four balanced groups: the two ~7s sections lead separate groups, the rest fill them up
group symlinked n kill &
group symlink utf8 stderr &
group broken_java todo_false commented jar_mismatch &
group bad_settings fresh macos linux curl_fail extra_args &
wait

# fixed merge order: the log order and the count do not depend on which group finished first
for s in fresh symlink n linux macos curl_fail jar_mismatch utf8 stderr broken_java todo_false commented bad_settings kill extra_args symlinked; do
  cat "$t/$s.log"
  if read -r sec_pass sec_fail < "$t/$s.cnt" 2>/dev/null; then pass=$((pass+sec_pass)); fail=$((fail+sec_fail)); else fail=$((fail+1)); echo "FAIL section $s crashed"; fi
done
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
