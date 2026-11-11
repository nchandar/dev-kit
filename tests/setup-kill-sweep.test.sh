#!/usr/bin/env bash
# Kill bin/setup --apply at each write it performs (links, bun, tools, jar, todo, settings), then rerun:
# the configs stay valid (or exactly the original), the HOME tree converges to an uninterrupted apply,
# and backups stay bounded.
# Usage: tests/setup-kill-sweep.test.sh
# Seed: the fixed backup timestamp (default 20260101T000000Z, printed below); override with KILL_SWEEP_SEED.
# Jobs: DEVKIT_KILL_JOBS (default 4) bounds the parallel kill cases.
# Tree: DEVKIT_SETUP_TEST_SRC (default this repo) runs the sweep against another tree; used to prove it can fail.
set -u
unset TLA2TOOLS  # the check honours it; the harness must not inherit the caller's
src=${DEVKIT_SETUP_TEST_SRC:-$(cd "$(dirname "$0")/.." && pwd)}
seed=${KILL_SWEEP_SEED:-20260101T000000Z}
jobs=${DEVKIT_KILL_JOBS:-4}
case $jobs in ''|*[!0-9]*|0) jobs=4;; esac
printf 'seed: %s\n' "$seed"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
okc() { if eval "$2"; then printf 'ok   %s\n' "$1" >> "$RES"; else printf 'FAIL %s   [%s]\n' "$1" "$2" >> "$RES"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
PY=$(command -v python3); [ -n "$PY" ] || PY=/usr/bin/python3
CP=$(command -v cp); MV=$(command -v mv); LN=$(command -v ln); MKDIR=$(command -v mkdir)
RM=$(command -v rm); CURL=$(command -v curl); DATE=$(command -v date)

# --- a private kit: one skill, no upstream, so sync is a no-op and nothing reaches the caller's tree
kit="$t/dev-kit"; setup="$kit/bin/setup"
mkdir -p "$kit/bin" "$kit/library" "$kit/skills" "$kit/opencode/commands"
cp "$src/bin/setup" "$kit/bin/setup"
cp "$src/library/setup.pins" "$kit/library/setup.pins"
cp "$src/install.sh" "$kit/install.sh"; chmod +x "$kit/install.sh"
cp -R "$src/skills/dev-mode" "$kit/skills/dev-mode"
cp "$src/opencode/commands/dev-mode.md" "$kit/opencode/commands/dev-mode.md"
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
printf 'jar\n' > "$t/fake-tla.jar"
grep -v '^tla2tools ' "$kit/library/setup.pins" > "$t/pins.base"
printf 'tla2tools 9.9.9 %s\n' "$(sha_of "$t/fake-tla.jar")" >> "$t/pins.base"
mv "$t/pins.base" "$kit/library/setup.pins"
git -C "$kit" init -q -b main
git -C "$kit" add -A
git -C "$kit" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm base

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
fake brew 'printf "brew %s\n" "$*" >> "$FAKE_LOG"
case $* in
  "install bun") cp "$FAKE_SRC" "$FAKE_INSTALL/bun"; chmod +x "$FAKE_INSTALL/bun";;
  "install openjdk") printf "#!/bin/bash\n:\n" > "$FAKE_INSTALL/java"; chmod +x "$FAKE_INSTALL/java";;
esac'
fake curl 'printf "curl %s\n" "$*" >> "$FAKE_LOG"
out=
while [ $# -gt 0 ]; do case $1 in -o) out=$2; shift 2;; *) shift;; esac; done
[ -n "$out" ] && printf "jar\n" > "$out"'
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

# --- the kill shim: counts state-changing calls, kills setup's process group at KILL_CAT:KILL_ORD
shim="$t/shim"; mkdir -p "$shim"
cat > "$shim/wshim" <<'S'
#!/bin/bash
kind=${0##*/}
st=${KILL_STATE:?}
real=
case $kind in
  cp) real=@CP@;; mv) real=@MV@;; ln) real=@LN@;; mkdir) real=@MKDIR@;;
  rm) real=@RM@;; curl) real=@CURL@;; python3) real=@PY@;; date) real=@DATE@;;
esac
[ -n "$real" ] || exit 127
if [ "$kind" = date ]; then
  case " $* " in *" +%Y%m%dT%H%M%SZ "*) printf '%s\n' "${KILL_TS:-20260101T000000Z}"; exit;; esac
  exec "$real" "$@"
fi
write=0; srcf=; dst=; all="$*"
case $kind in
  mkdir) for a in "$@"; do case $a in -*) ;; *) [ -d "$a" ] || write=1;; esac; done;;
  ln) for a in "$@"; do case $a in -*) ;; *) if [ -z "$srcf" ]; then srcf=$a; else dst=$a; fi;; esac; done
      write=1; [ -L "$dst" ] && [ "$(readlink "$dst")" = "$srcf" ] && write=0;;
  cp|mv) for a in "$@"; do case $a in -*) ;; *) if [ -z "$srcf" ]; then srcf=$a; else dst=$a; fi;; esac; done; write=1;;
  rm|curl) write=1;;
  python3) # only install.sh writes a HOME config directly (python3 - <opencode config>)
    if [ $# -eq 2 ] && [ "$1" = - ]; then case ${2##*/} in opencode.json|opencode.jsonc) write=1;; esac; fi;;
esac
[ "$write" = 1 ] || exec "$real" "$@"
printf '%s\t%s\n' "$kind" "$all" >> "$st/log"
n=$(( $(cat "$st/count" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "$n" > "$st/count"
cat=other
case $all in
  *settings.json*) cat=settings;;
  *opencode.json*) cat=todo;;
  *tla2tools*) cat=jar;;
  *tlachart*|*pele*|*dev-kit-tools*) cat=tools;;
  */bun) cat=bun;;
  */.claude/*|*/.codex/*|*/.agents/*|*/opencode/commands/*) cat=links;;
esac
if [ -n "${KILL_CAT:-}" ] && [ "$cat" = "$KILL_CAT" ]; then
  c=$(( $(cat "$st/c.$cat" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "$c" > "$st/c.$cat"
  if [ "$c" = "${KILL_ORD:-0}" ]; then
    case $kind in
      cp) sz=$(wc -c < "$srcf" 2>/dev/null || echo 0); head -c $((sz/2)) "$srcf" > "$dst" 2>/dev/null || : > "$dst";;
      curl) out=; prev=; for a in "$@"; do [ "$prev" = -o ] && out=$a; prev=$a; done; [ -z "$out" ] || : > "$out";;
    esac
    kill -9 -"$(cat "$st/pgid")" 2>/dev/null
    exit 137
  fi
fi
exec "$real" "$@"
S
sed -e "s|@CP@|$CP|g" -e "s|@MV@|$MV|g" -e "s|@LN@|$LN|g" -e "s|@MKDIR@|$MKDIR|g" \
    -e "s|@RM@|$RM|g" -e "s|@CURL@|$CURL|g" -e "s|@PY@|$PY|g" -e "s|@DATE@|$DATE|g" \
    "$shim/wshim" > "$shim/wshim.tmp" && mv "$shim/wshim.tmp" "$shim/wshim"
chmod +x "$shim/wshim"
for n in cp mv ln mkdir rm curl python3 date; do ln -s wshim "$shim/$n"; done

launch="$t/launch"
cat > "$launch" <<'S'
#!/bin/bash
printf '%s\n' "$$" > "$KILL_STATE/pgid"
exec /bin/bash "$KIT_SETUP" --apply
S
answers="$t/answers"; : > "$answers"
i=0; while [ "$i" -lt 40 ]; do printf 'y\n' >> "$answers"; i=$((i+1)); done

# A file's content is compared after replacing the HOME path, because settings.json embeds it.
tree_list() { # home
  ( cd "$1" || exit 1
    find . \( -name .git -o -name .devkit -o -name .lavish -o -name '.devkit-new.*' -o -name '*.part' -o -name '*.devkit-bak-*' \) -prune -o \
      -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s\n' "$(sed "s|$1|@HOME@|g" "$f" 2>/dev/null | cksum)" "$f"
      done
    find . \( -name .git -o -name .devkit -o -name .lavish -o -name '.devkit-new.*' -o -name '*.part' -o -name '*.devkit-bak-*' \) -prune -o \
      -type l -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do printf '%s -> %s\n' "$p" "$(readlink "$p")"; done
  ) }
backups() { find "$1" -name '*.devkit-bak-*' 2>/dev/null | wc -l | tr -d ' '; }
n_backups() { find "$1" -maxdepth 1 -name "$2.devkit-bak-*" 2>/dev/null | wc -l | tr -d ' '; }
valid_or_orig() { # file original
  [ -f "$1" ] || return 1
  cmp -s "$1" "$2" && return 0
  "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
}
same_tree() { # home baseline-home case-id
  local a b
  a=$(tree_list "$1"); b=$(tree_list "$2")
  [ "$a" = "$b" ] && return 0
  printf '%s\n' "$b" > "$t/tree-$3-base.txt"; printf '%s\n' "$a" > "$t/tree-$3-home.txt"
  echo "  tree diff:"; diff -u "$t/tree-$3-base.txt" "$t/tree-$3-home.txt" | sed -n '1,16p' | sed 's/^/    /'
  return 1
}
backups_ok() { # home baseline-home: a backup present in both has the same content
  ( cd "$1" || exit 1; find . -name '*.devkit-bak-*' -type f -print 2>/dev/null ) | while IFS= read -r f; do
    [ -f "$2/$f" ] || continue
    cmp -s "$1/$f" "$2/$f" || exit 1
  done
}

run_apply() { # home out kill-cat kill-ord inst toolsbin(0|1)
  local h=$1 out=$2 kc=$3 ko=$4 inst=$5 tb=$6 ppath pid st
  ppath=$inst; [ "$tb" = 1 ] && ppath="$toolsbin:$inst"
  st="$out.state"; rm -rf "$st"; mkdir -p "$st"; : > "$st/log"; printf '0\n' > "$st/count"
  rm -f "$out.bun-ran"
  ( set -m
    env HOME="$h" PATH="$shim:$fb:$ppath:$base_path" FAKE_LOG="$out.fake.log" FAKE_INSTALL="$inst" \
      FAKE_SRC="$t/bun.real" FAKE_BUN_RAN="$out.bun-ran" KILL_STATE="$st" KILL_CAT="$kc" KILL_ORD="$ko" \
      KILL_TS="$seed" KIT_SETUP="$setup" /bin/bash "$launch" < "$answers" > "$out" 2>&1 &
    pid=$!
    set +m
    wait "$pid" ) 2>/dev/null
  return $?
}

make_ready_home() { # dest: links + tools present, settings behind a symlink, todo absent
  h=$1
  mkdir -p "$h/.claude/skills" "$h/.codex/skills" "$h/.agents/skills"
  mkdir -p "$h/.agents/dev-kit-tools/node_modules/pele" "$h/.local/share/tla"
  mkdir -p "$h/.bun/install/global/node_modules/tlachart/src" "$h/.bun/bin"
  mkdir -p "$h/.config/opencode/commands" "$h/dotfiles"
  ln -s "$kit" "$h/.agents/dev-kit"
  for root in .claude/skills .codex/skills .agents/skills; do ln -s "$kit/skills/dev-mode" "$h/$root/dev-mode"; done
  ln -s "$kit/opencode/commands/dev-mode.md" "$h/.config/opencode/commands/dev-mode.md"
  : > "$h/.local/share/tla/tla2tools.jar"
  printf '{"plugin":[]}\n' > "$h/.config/opencode/opencode.jsonc"
  printf '{"name":"tlachart","version":"0.1.0"}\n' > "$h/.bun/install/global/node_modules/tlachart/package.json"
  printf '#!/bin/bash\n:\n' > "$h/.bun/install/global/node_modules/tlachart/src/main.js"
  chmod +x "$h/.bun/install/global/node_modules/tlachart/src/main.js"
  ln -s ../install/global/node_modules/tlachart/src/main.js "$h/.bun/bin/tlachart"
  printf '{"permissions":{"allow":["Bash(git status:*)"]}}\n' > "$h/dotfiles/claude-settings.json"
  ln -s ../dotfiles/claude-settings.json "$h/.claude/settings.json"
}

# --- the two starting shapes; the fresh one also makes install.sh run (one missing link)
fresh0="$t/fresh0"; make_ready_home "$fresh0"
rm "$fresh0/.agents/skills/dev-mode"
rm -rf "$fresh0/.bun" "$fresh0/.agents/dev-kit-tools"
rm -f "$fresh0/.local/share/tla/tla2tools.jar"
ready0="$t/ready0"; make_ready_home "$ready0"

baseline() { # label init toolsbin categories
  local label=$1 init=$2 tb=$3 want=$4 base rc w pat
  base="$t/$label-r000"; cp -R "$init" "$base"
  mkdir -p "$t/$label-i000"
  run_apply "$base" "$t/$label-base.out" "" 0 "$t/$label-i000" "$tb"; rc=$?
  ok "$label: uninterrupted apply exits 0" '[ $rc -eq 0 ]'
  ok "$label: uninterrupted apply ends ready" 'tail -n 1 "$t/$label-base.out" | grep -qx "verdict: ready"'
  cp "$t/$label-base.out.state/log" "$t/$label-base.log"
  for w in $want; do
    case $w in
      links) pat='\.(claude|codex|agents)/skills/|\.agents/dev-kit|opencode/commands';;
      bun) pat='/bun$';;
      tools) pat='tlachart|pele|dev-kit-tools';;
      jar) pat='tla2tools';;
      todo) pat='opencode\.json';;
      settings) pat='settings\.json';;
    esac
    ok "$label: saw $w writes" "grep -qE '$pat' '$t/$label-base.log'"
  done
  backups "$base" > "$t/$label-base.bak"
  printf '%s: %s writes, baseline backups %s\n' "$label" "$(cat "$t/$label-base.out.state/count")" "$(cat "$t/$label-base.bak")"
  rm -rf "$t/$label-i000"
}

# kill_case id label init toolsbin category ordinal
kill_case() {
  local id=$1 label=$2 init=$3 tb=$4 cat=$5 ord=$6 h inst rc nid
  RES="$t/results/$id.txt"
  nid=$((10#$id))
  h="$t/$label-r$(printf '%03d' "$nid")"; cp -R "$init" "$h"
  inst="$t/$label-i$(printf '%03d' "$nid")"; mkdir -p "$inst"
  run_apply "$h" "$t/$label-$id.out" "$cat" "$ord" "$inst" "$tb"; rc=$?
  okc "kill $label/$cat:$ord: setup was killed" '[ $rc -ne 0 ]'
  okc "kill $label/$cat:$ord: settings.json is valid or the original" 'valid_or_orig "$h/.claude/settings.json" "$init/dotfiles/claude-settings.json"'
  okc "kill $label/$cat:$ord: opencode config is valid or the original" 'valid_or_orig "$h/.config/opencode/opencode.jsonc" "$init/.config/opencode/opencode.jsonc"'
  run_apply "$h" "$t/$label-$id-rerun.out" "" 0 "$inst" "$tb"; rc=$?
  okc "kill $label/$cat:$ord: rerun exits 0" '[ $rc -eq 0 ]'
  okc "kill $label/$cat:$ord: HOME tree equals an uninterrupted apply" 'same_tree "$h" "$t/$label-r000" "$id"'
  okc "kill $label/$cat:$ord: existing backups are intact" 'backups_ok "$h" "$t/$label-r000"'
  okc "kill $label/$cat:$ord: the settings backup matches the baseline" '[ "$(n_backups "$h/.claude" settings.json)" = "$(n_backups "$t/$label-r000/.claude" settings.json)" ]'
  okc "kill $label/$cat:$ord: at most one settings backup" '[ "$(n_backups "$h/.claude" settings.json)" -le 1 ]'
  okc "kill $label/$cat:$ord: at most one opencode backup" '[ "$(n_backups "$h/.config/opencode" opencode.jsonc)" -le 1 ]'
  rm -rf "$h" "$inst"
}

baseline fresh "$fresh0" 0 "links bun tools jar todo settings"
baseline ready "$ready0" 1 "todo settings"

results="$t/results"; mkdir -p "$results"
n=0; pids=""
for spec in "fresh 0 links 1" "fresh 0 bun 1" "fresh 0 tools 2" "fresh 0 jar 2" \
            "fresh 0 todo 1" "fresh 0 settings 2" "ready 1 todo 2" "ready 1 settings 2"; do
  set -- $spec; n=$((n+1)); id=$(printf '%02d' "$n")
  : > "$results/$id.txt"
  kin=$ready0; [ "$1" = fresh ] && kin=$fresh0
  kill_case "$id" "$1" "$kin" "$2" "$3" "$4" &
  pids="$pids $!"
  if [ "$((n % jobs))" -eq 0 ]; then wait $pids; pids=""; fi
done
[ -z "$pids" ] || wait $pids
f=1
while [ "$f" -le "$n" ]; do cat "$results/$(printf '%02d' "$f").txt"; f=$((f+1)); done
bpass=$pass; bfail=$fail
pass=$(cat "$results"/*.txt | grep -c '^ok')
fail=$(cat "$results"/*.txt | grep -c '^FAIL')
pass=$((pass + bpass)); fail=$((fail + bfail))

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
