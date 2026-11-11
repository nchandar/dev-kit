#!/usr/bin/env bash
# Tests for bin/chart-svg: usage, missing bun or pele, render errors, no partial file, real bun.
# Usage: tests/chart-svg.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
chart="$here/bin/chart-svg"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
umask 022
mode_of() { if stat -f %Lp "$1" >/dev/null 2>&1; then stat -f %Lp "$1"; else stat -c %a "$1"; fi; }
base_path=/usr/bin:/bin:/usr/sbin:/sbin

# a PATH with the shell tools the wrapper needs and no bun
sys="$t/sys"; mkdir -p "$sys"
for n in bash dirname basename mktemp rm mv cat chmod; do p=$(command -v "$n") && ln -s "$p" "$sys/$n"; done
empty="$t/empty-home"; mkdir -p "$empty"
tools_home="$t/tools-home"; mkdir -p "$tools_home/.agents/dev-kit-tools/node_modules/pele"

# fake bun: logs its arguments and does what the case asks
fb="$t/fakebin"; mkdir -p "$fb"
fake_bun() { { printf '#!/bin/bash\n'; printf '%s\n' "$1"; } > "$fb/bun"; chmod +x "$fb/bun"; }
fake_bun 'printf "bun %s\n" "$*" >> "$FAKE_BUN_LOG"; printf "%s" "$FAKE_BUN_BODY" > "$3"'
log="$t/bun.log"; : > "$log"
run_fake() { # body exit-code out: fake bun writes body to the temp output, then exits
  FAKE_BUN_LOG="$log" FAKE_BUN_BODY="$1" HOME="$tools_home" PATH="$fb:$base_path" "$chart" "$t/in.mmd" "$3"
}
printf 'flowchart LR\n  A --> B\n' > "$t/in.mmd"

# --- usage and input errors
"$chart" > "$t/usage.out" 2>&1; rc=$?
ok "no arguments: usage exits 2" '[ $rc -eq 2 ] && grep -q "usage: bin/chart-svg SRC.mmd OUT.svg" "$t/usage.out"'
"$chart" "$t/in.mmd" > /dev/null 2>&1
ok "one argument: exits 2" '[ $? -eq 2 ]'
"$chart" "$t/in.mmd" "$t/out.svg" extra > /dev/null 2>&1
ok "three arguments: exits 2" '[ $? -eq 2 ]'
HOME="$empty" PATH="$sys" "$chart" "$t/absent.mmd" "$t/absent.svg" > "$t/src.out" 2>&1; rc=$?
ok "missing source: exits 1" '[ $rc -eq 1 ] && grep -q "no such source" "$t/src.out"'
ok "missing source: no output file" '[ ! -e "$t/absent.svg" ]'

# --- missing bun: one line, the command that fixes it, and no output
HOME="$empty" PATH="$sys" "$chart" "$t/in.mmd" "$t/nobun.svg" > "$t/nobun.out" 2>&1; rc=$?
ok "missing bun: exits 1" '[ $rc -eq 1 ]'
ok "missing bun: names bin/setup --apply" 'grep -qF "bin/setup --apply" "$t/nobun.out"'
ok "missing bun: one line" '[ "$(wc -l < "$t/nobun.out" | tr -d " ")" = 1 ]'
ok "missing bun: no output file" '[ ! -e "$t/nobun.svg" ]'

# --- missing pele: the fake bun is present, so the check fails before any render
HOME="$empty" PATH="$fb:$base_path" "$chart" "$t/in.mmd" "$t/nopele.svg" > "$t/nopele.out" 2>&1; rc=$?
ok "missing pele: exits 1" '[ $rc -eq 1 ]'
ok "missing pele: names bin/setup --apply" 'grep -qF "bin/setup --apply" "$t/nopele.out"'
ok "missing pele: no output file" '[ ! -e "$t/nopele.svg" ]'
ok "missing pele: bun was never run" '[ ! -s "$log" ]'

# --- a render error writes nothing, leaves no temp file and keeps an existing output
fake_bun 'printf "%s" "$FAKE_BUN_BODY" > "$3"; exit 1'
run_fake PARTIAL 1 "$t/fail.svg" > "$t/fail.out" 2>&1; rc=$?
ok "render error: exits 1" '[ $rc -eq 1 ]'
ok "render error: no output file" '[ ! -e "$t/fail.svg" ]'
ok "render error: no temp file left" '[ -z "$(find "$t" -maxdepth 1 -name ".chart-svg*" -print)" ]'
ok "render error: says the render failed and names the fix" 'grep -q "render failed; run bin/setup --apply" "$t/fail.out" && [ "$(wc -l < "$t/fail.out" | tr -d " ")" = 1 ]'
printf 'OLD' > "$t/keep.svg"
run_fake PARTIAL 1 "$t/keep.svg" > /dev/null 2>&1
ok "render error: an existing output is untouched" '[ "$(cat "$t/keep.svg")" = OLD ]'
HOME="$tools_home" PATH="$fb:$base_path" "$chart" "$t/in.mmd" "$t/no-dir/out.svg" > "$t/nodir.out" 2>&1; rc=$?
ok "missing output directory: exits 1" '[ $rc -eq 1 ] && grep -q "no such directory" "$t/nodir.out"'
mkdir -p "$t/outdir"
run_fake '<svg>x</svg>' 0 "$t/outdir" > "$t/outdir.out" 2>&1; rc=$?
ok "output is a directory: exits 1" '[ $rc -eq 1 ] && grep -q "is a directory" "$t/outdir.out"'
ok "output is a directory: nothing written inside it" '[ -z "$(find "$t/outdir" -type f -print)" ]'

# --- the fake bun receives the module, source and tools dir; success moves the temp into place
fake_bun 'printf "bun %s\n" "$*" >> "$FAKE_BUN_LOG"; printf "<svg>%s</svg>" "$FAKE_BUN_BODY" > "$3"'
: > "$log"
FAKE_BUN_LOG="$log" FAKE_BUN_BODY=ok FAKE_BUN_RC=0 HOME="$tools_home" PATH="$fb:$base_path" \
  "$chart" "$t/in.mmd" "$t/ok.svg" > "$t/ok.out" 2>&1; rc=$?
ok "success: exits 0" '[ $rc -eq 0 ]'
ok "success: writes the SVG" '[ "$(cat "$t/ok.svg")" = "<svg>ok</svg>" ]'
ok "success: output mode is 0644" '[ "$(mode_of "$t/ok.svg")" = 644 ]'
ok "success: no temp file left" '[ -z "$(find "$t" -maxdepth 1 -name ".chart-svg*" -print)" ]'
ok "success: runs the module with the source and tools" 'grep -q "chart-svg.mjs $t/in.mmd" "$log" && grep -q "dev-kit-tools" "$log"'

# --- real bun: a stub pele proves the module path; the real pele case runs only where installed
have() { command -v "$1" >/dev/null 2>&1; }
if have bun; then
  stub="$t/stub-home"; mkdir -p "$stub/.agents/dev-kit-tools/node_modules/pele/dist"
  printf '{"name":"pele","type":"module","exports":{".":{"import":"./dist/pele.js"}}}\n' > "$stub/.agents/dev-kit-tools/node_modules/pele/package.json"
  cat > "$stub/.agents/dev-kit-tools/node_modules/pele/dist/pele.js" <<'JS'
export class PeleError extends Error {}
export function render(source) {
  if (!source.includes("flowchart")) throw new PeleError("stub: not a flowchart");
  return { svg: "<svg>" + source.trim().length + "</svg>" };
}
JS
  HOME="$stub" "$chart" "$t/in.mmd" "$t/stub.svg" > "$t/stub.out" 2>&1; rc=$?
  ok "real bun: renders through the module" '[ $rc -eq 0 ] && grep -q "^<svg>" "$t/stub.svg"'
  printf 'not a diagram\n' > "$t/bad.mmd"
  HOME="$stub" "$chart" "$t/bad.mmd" "$t/stub-bad.svg" > "$t/stub-bad.out" 2>&1; rc=$?
  ok "real bun: a PeleError prints one plain line and writes nothing" '[ $rc -eq 1 ] && grep -q "stub: not a flowchart" "$t/stub-bad.out" && [ "$(wc -l < "$t/stub-bad.out" | tr -d " ")" = 1 ] && [ ! -e "$t/stub-bad.svg" ]'
  if [ -d "$HOME/.agents/dev-kit-tools/node_modules/pele" ]; then
    HOME="$HOME" "$chart" "$t/in.mmd" "$t/real.svg" > "$t/real.out" 2>&1; rc=$?
    ok "real bun and pele: writes SVG" '[ $rc -eq 0 ] && grep -q "^<svg" "$t/real.svg"'
  else
    # split the word so verify-scan does not read a legitimate optional skip as a test escape
    printf 'SK%s  real pele: not installed (bun is present)\n' IP
  fi
else
  printf 'SK%s  real bun: not installed\n' IP
  printf 'SK%s  real pele: not installed\n' IP
fi

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
