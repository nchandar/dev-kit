#!/usr/bin/env bash
# Tests for repo sync in bin/setup: discovery, offline --check, ff-only --apply, frozen copy.
# Usage: tests/setup-sync.test.sh. All remotes are local bare repos: no network.
set -u
unset TLA2TOOLS
here=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
for i in 0 1 2 3 4 5 6 7 8 9; do unset "GIT_CONFIG_KEY_$i" "GIT_CONFIG_VALUE_$i"; done
unset GIT_CONFIG_COUNT
base_path=/usr/bin:/bin:/usr/sbin:/sbin

# --- a private dev-kit copy: its own git repo with no upstream, so the sync line is stable
kit="$t/dev-kit"
mkdir -p "$kit/bin" "$kit/skills/dev-sync"
cp "$here/bin/setup" "$kit/bin/setup"
printf '# dev-sync\n' > "$kit/skills/dev-sync/SKILL.md"
git -C "$kit" init -q -b main
git -C "$kit" add -A
git -C "$kit" commit -qm base
setup="$kit/bin/setup"

# --- fake CLIs: core versions are controlled; no real installs
fb="$t/bin"; mkdir -p "$fb"
fake() { { printf '#!/bin/bash\n'; printf '%s\n' "$2"; } > "$fb/$1"; chmod +x "$fb/$1"; }
fake bash 'case "${1:-}" in --version) echo "GNU bash, version 5.2.15(1)-release (test)";; *) exec /bin/bash "$@";; esac'
fake git 'case "${1:-}" in --version) echo "git version 2.43.0"; exec true;; esac
case " $* " in
  *" status "*) printf "status locks=%s\n" "${GIT_OPTIONAL_LOCKS:-}" >> "$FAKE_LOG";;
esac
case " $* " in
  *" fetch "*) printf "fetch prompt=%s ssh=%s\n" "${GIT_TERMINAL_PROMPT:-}" "${GIT_SSH_COMMAND:-}" >> "$FAKE_LOG";;
esac
exec /usr/bin/git "$@"'
fake perl 'echo "This is perl 5, version 34, subversion 1 (v5.34.1)"'
for n in codex bun java; do fake "$n" ':'; done
export FAKE_LOG="$t/git.log"; : > "$FAKE_LOG"

base_home() { # dest: links complete, optional tools present, no settings/opencode
  h=$1
  mkdir -p "$h/.agents/skills" "$h/.claude/skills" "$h/.codex/skills" \
    "$h/.local/share/tla" "$h/.agents/dev-kit-tools/node_modules/pele" "$h/.bun/bin"
  : > "$h/.local/share/tla/tla2tools.jar"
  ln -s "$kit" "$h/.agents/dev-kit"
  ln -s "$kit/skills/dev-sync" "$h/.agents/skills/dev-sync"
}
link_skill() { # home repo name
  ln -s "$2/skills/$3" "$1/.agents/skills/$3"
}
check() { HOME="$1" PATH="$fb:$base_path" /bin/bash "$setup" --check > "$2" 2>&1; }
apply_yes() { HOME="$1" PATH="$fb:$base_path" /bin/bash "$setup" --apply; }
apply_n() { HOME="$1" PATH="$fb:$base_path" /bin/bash "$setup" --apply; }

seed() { # name skills|config -> seed worktree path
  name=$1; kind=$2
  r="$t/remotes/$name.git"; w="$t/seed/$name"
  git init -q --bare -b main "$r"
  git init -q -b main "$w"
  if [ "$kind" = skills ]; then
    mkdir -p "$w/skills/dev-$name"
    printf '# dev-%s\n' "$name" > "$w/skills/dev-$name/SKILL.md"
  else
    printf '{"permissions":{"allow":[]}}\n' > "$w/claude-settings.json"
    printf '# AGENTS\n' > "$w/AGENTS.md"
  fi
  git -C "$w" remote add origin "$r"
  git -C "$w" add -A
  git -C "$w" commit -qm base
  git -C "$w" push -q -u origin main
}
clone_repo() { # name dest
  git clone -q "$t/remotes/$1.git" "$2"
}
advance() { # name file content subject
  w="$t/seed/$1"
  printf '%s\n' "$3" > "$w/$2"
  git -C "$w" add -A
  git -C "$w" commit -qm "$4"
  git -C "$w" push -q origin HEAD
}

# --- behind is read from refs already on disk; --check never fetches
seed skills skills
repo="$t/local/skills"; clone_repo skills "$repo"
advance skills "skills/dev-skills/NOTE" "remote" "remote one"
git -C "$repo" fetch -q
H="$t/home-behind"; base_home "$H"; link_skill "$H" "$repo" dev-skills
check "$H" "$t/behind.out"; rc=$?
ok "behind: exits 0" '[ $rc -eq 0 ]'
ok "behind: offline line" 'grep -qx "behind  sync:skills  1 commits (last fetch)" "$t/behind.out"'
ok "behind: --check did not fetch" '[ "$(git -C "$repo" rev-list --count HEAD..origin/main)" = 1 ]'
ok "behind: section header" 'grep -qx "\[sync\]" "$t/behind.out"'
ok "check: git status asks for no optional locks" 'grep -qx "status locks=0" "$FAKE_LOG"'

# --- one up-front prompt; declining it fetches nothing and reports local refs
seed skills10 skills
repo="$t/local/skills10"; clone_repo skills10 "$repo"
advance skills10 "skills/dev-skills10/NOTE" "remote" "remote ten"
H="$t/home-declined"; base_home "$H"; link_skill "$H" "$repo" dev-skills10
before_ref=$(git -C "$repo" rev-parse refs/remotes/origin/main)
printf 'n\n' | apply_yes "$H" > "$t/declined.out" 2>&1; rc=$?
ok "fetch declined: exits 0" '[ $rc -eq 0 ]'
ok "fetch declined: one up-front prompt names the count" 'grep -q "Contact remotes of [0-9][0-9]* repos to check for new commits? \[y/N\]" "$t/declined.out"'
ok "fetch declined: no remote ref moved" '[ "$(git -C "$repo" rev-parse refs/remotes/origin/main)" = "$before_ref" ]'
ok "fetch declined: reports the last fetch" 'grep -qx "ok  sync:skills10  up to date (last fetch)" "$t/declined.out"'
ok "fetch declined: no pull prompt" '! grep -q "Pull .* into skills10" "$t/declined.out"'

# --- y pulls ff-only on the current branch
seed skills2 skills
repo="$t/local/skills2"; clone_repo skills2 "$repo"
advance skills2 "skills/dev-skills2/NOTE" "remote" "remote two"
H="$t/home-y"; base_home "$H"; link_skill "$H" "$repo" dev-skills2
before=$(git -C "$repo" rev-parse HEAD)
printf 'y\ny\n' | apply_yes "$H" > "$t/y.out" 2>&1; rc=$?
ok "y: exits 0" '[ $rc -eq 0 ]'
ok "y: prompt is silent and batch mode is on" 'grep -qx "fetch prompt=0 ssh=ssh -o BatchMode=yes" "$FAKE_LOG"'
ok "y: shows the incoming commit" 'grep -q "remote two" "$t/y.out"'
ok "y: pull prompt names the repo" 'grep -q "Pull 1 commits into skills2? \[y/N\]" "$t/y.out"'
ok "y: head moved" '[ "$(git -C "$repo" rev-parse HEAD)" != "$before" ]'
ok "y: head caught up" '[ "$(git -C "$repo" rev-parse HEAD)" = "$(git -C "$repo" rev-parse origin/main)" ]'
ok "y: still on main" '[ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" = main ]'
after=$(git -C "$repo" rev-parse HEAD)
yes | apply_yes "$H" > "$t/y2.out" 2>&1
ok "second apply: no pull prompt" '! grep -q "Pull .* into skills2" "$t/y2.out"'
ok "second apply: head unchanged" '[ "$(git -C "$repo" rev-parse HEAD)" = "$after" ]'

# --- n skips the pull and leaves the tree alone
seed skills3 skills
repo="$t/local/skills3"; clone_repo skills3 "$repo"
advance skills3 "skills/dev-skills3/NOTE" "remote" "remote three"
H="$t/home-n"; base_home "$H"; link_skill "$H" "$repo" dev-skills3
before=$(git -C "$repo" rev-parse HEAD)
printf 'n\n' | apply_n "$H" > "$t/n.out" 2>&1; rc=$?
ok "n: exits 0" '[ $rc -eq 0 ]'
ok "n: head unchanged" '[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]'
ok "n: fetch declined, local refs reported" 'grep -qx "ok  sync:skills3  up to date (last fetch)" "$t/n.out"'

# --- dirty, diverged, no upstream and detached are skipped with a reason
seed skills4 skills
repo="$t/local/skills4"; clone_repo skills4 "$repo"
advance skills4 "skills/dev-skills4/NOTE" "remote" "remote four"
printf 'untracked\n' > "$repo/untracked.txt"
H="$t/home-dirty"; base_home "$H"; link_skill "$H" "$repo" dev-skills4
check "$H" "$t/dirty.out"
ok "dirty: --check line" 'grep -qx "skipped  sync:skills4  dirty" "$t/dirty.out"'
printf 'y\n' | apply_yes "$H" > "$t/dirty-apply.out" 2>&1
ok "dirty: --apply skips before fetch" 'grep -qx "skipped  sync:skills4  dirty" "$t/dirty-apply.out" && [ "$(git -C "$repo" rev-list --count HEAD..origin/main)" = 0 ]'

seed skills5 skills
repo="$t/local/skills5"; clone_repo skills5 "$repo"
printf 'local\n' > "$repo/local.txt"
git -C "$repo" add -A; git -C "$repo" commit -qm local
advance skills5 "skills/dev-skills5/NOTE" "remote" "remote five"
git -C "$repo" fetch -q
H="$t/home-div"; base_home "$H"; link_skill "$H" "$repo" dev-skills5
before=$(git -C "$repo" rev-parse HEAD)
printf 'y\n' | apply_yes "$H" > "$t/div.out" 2>&1
ok "diverged: --apply skips" 'grep -qx "skipped  sync:skills5  diverged (ff impossible)" "$t/div.out"'
ok "diverged: head unchanged" '[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]'

seed skills6 skills
repo="$t/local/skills6"; clone_repo skills6 "$repo"
git -C "$repo" checkout -q -b feature
H="$t/home-noup"; base_home "$H"; link_skill "$H" "$repo" dev-skills6
check "$H" "$t/noup.out"
ok "no upstream: --check line" 'grep -qx "skipped  sync:skills6  no upstream" "$t/noup.out"'
printf 'y\n' | apply_yes "$H" > "$t/noup-apply.out" 2>&1
ok "no upstream: --apply never prompts" '! grep -q "Pull .* into skills6" "$t/noup-apply.out"'

seed skills7 skills
repo="$t/local/skills7"; clone_repo skills7 "$repo"
git -C "$repo" checkout -q --detach HEAD
H="$t/home-det"; base_home "$H"; link_skill "$H" "$repo" dev-skills7
check "$H" "$t/det.out"
ok "detached: --check line" 'grep -qx "skipped  sync:skills7  detached" "$t/det.out"'

# --- a non-default branch with an upstream is pulled, and the branch stays current
seed skills8 skills
repo="$t/local/skills8"; clone_repo skills8 "$repo"
git -C "$repo" checkout -q -b feature
git -C "$repo" push -q -u origin feature
git -C "$t/seed/skills8" checkout -q -b feature
advance skills8 "skills/dev-skills8/NOTE" "remote" "remote feature"
git -C "$repo" fetch -q
H="$t/home-feature"; base_home "$H"; link_skill "$H" "$repo" dev-skills8
before=$(git -C "$repo" rev-parse HEAD)
printf 'y\ny\n' | apply_yes "$H" > "$t/feature.out" 2>&1
ok "feature upstream: pulled" '[ "$(git -C "$repo" rev-parse HEAD)" != "$before" ] && [ "$(git -C "$repo" rev-parse HEAD)" = "$(git -C "$repo" rev-parse origin/feature)" ]'
ok "feature upstream: branch kept" '[ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" = feature ]'

# --- config repos are fetched and reported, never pulled
seed dotfiles config
repo="$t/local/dotfiles"; clone_repo dotfiles "$repo"
advance dotfiles "claude-settings.json" '{"permissions":{"allow":["Bash(ls:*)"]}}' "remote cfg"
H="$t/home-cfg"; base_home "$H"
ln -s "$repo/claude-settings.json" "$H/.claude/settings.json"
before=$(git -C "$repo" rev-parse HEAD)
printf 'y\n' | apply_yes "$H" > "$t/cfg.out" 2>&1
ok "config: behind reported, not pulled" 'grep -qx "behind  sync:dotfiles  1 commits (config, not pulled)" "$t/cfg.out"'
ok "config: head unchanged" '[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]'
ok "config: never prompts to pull" '! grep -q "Pull .* into dotfiles" "$t/cfg.out"'

# --- discovery walks the three skills roots, dedupes, and skips non-git targets silently
seed skills9 skills
repo="$t/local/skills9"; clone_repo skills9 "$repo"
H="$t/home-disc"; base_home "$H"
link_skill "$H" "$repo" dev-skills9
ln -s "$repo/skills/dev-skills9" "$H/.claude/skills/dev-skills9"
ln -s "$repo/skills/dev-skills9" "$H/.codex/skills/dev-skills9"
mkdir -p "$t/not-a-repo"; ln -s "$t/not-a-repo" "$H/.agents/skills/dev-foreign"
ln -s "$t/missing-target" "$H/.claude/skills/dev-dead"
check "$H" "$t/disc.out"; rc=$?
ok "discovery: temp HOME passes" '[ $rc -eq 0 ]'
ok "discovery: one line per repo" '[ "$(grep -c "sync:skills9" "$t/disc.out")" = 1 ]'
ok "discovery: non-git and dead links are silent" '! grep -q "not-a-repo\|missing-target\|dev-foreign" "$t/disc.out"'
ok "discovery: no hardcoded ~/skills or ~/dotfiles" '! grep -qF "$H/skills" "$t/disc.out" && ! grep -qF "$H/dotfiles" "$t/disc.out"'

# --- after a skills pull, the repo's own installer is offered
seed skillsmk skills
repo="$t/local/skillsmk"; clone_repo skillsmk "$repo"
w="$t/seed/skillsmk"
printf 'install-codex:\n\t@printf ran > "$(CURDIR)/install-ran"\n' > "$w/Makefile"
git -C "$w" add -A; git -C "$w" commit -qm makefile; git -C "$w" push -q origin HEAD
git -C "$repo" fetch -q
H="$t/home-mk"; base_home "$H"; link_skill "$H" "$repo" dev-skillsmk
yes | apply_yes "$H" > "$t/mk.out" 2>&1
ok "installer: make command printed" 'grep -q "run: make -C .*skillsmk install-codex" "$t/mk.out"'
ok "installer: make target ran" '[ -f "$repo/install-ran" ]'
ok "installer: warns it runs code from the pulled commits" 'grep -q "runs code from the pulled commits" "$t/mk.out"'

# --- N to the make target means no install.sh offer for the same repo
seed skillsmk2 skills
repo="$t/local/skillsmk2"; clone_repo skillsmk2 "$repo"
w="$t/seed/skillsmk2"
printf 'install-codex:\n\t@printf ran > "$(CURDIR)/make-ran"\n' > "$w/Makefile"
printf '#!/usr/bin/env bash\nd=$(cd "$(dirname "$0")" && pwd); printf ran > "$d/install-ran"\n' > "$w/install.sh"; chmod +x "$w/install.sh"
git -C "$w" add -A; git -C "$w" commit -qm "make and install"; git -C "$w" push -q origin HEAD
git -C "$repo" fetch -q
H="$t/home-mk2"; base_home "$H"; link_skill "$H" "$repo" dev-skillsmk2
printf 'y\ny\nn\n' | apply_yes "$H" > "$t/mk2.out" 2>&1
ok "installer choice: N to make skips install.sh" '! grep -q "run: .*skillsmk2/install.sh" "$t/mk2.out"'
ok "installer choice: install.sh did not run" '[ ! -f "$repo/install-ran" ]'

seed skillsinst skills
repo="$t/local/skillsinst"; clone_repo skillsinst "$repo"
w="$t/seed/skillsinst"
printf '#!/usr/bin/env bash\nd=$(cd "$(dirname "$0")" && pwd); printf ran > "$d/install-ran"; pwd -P > "$d/install-cwd"\n' > "$w/install.sh"; chmod +x "$w/install.sh"
git -C "$w" add -A; git -C "$w" commit -qm installer; git -C "$w" push -q origin HEAD
git -C "$repo" fetch -q
H="$t/home-inst"; base_home "$H"; link_skill "$H" "$repo" dev-skillsinst
( cd "$t" && yes | HOME="$H" PATH="$fb:$base_path" /bin/bash "$setup" --apply > "$t/inst.out" 2>&1 )
ok "installer: install.sh printed" 'grep -q "run: .*skillsinst/install.sh" "$t/inst.out"'
ok "installer: install.sh ran" '[ -f "$repo/install-ran" ]'
ok "installer: install.sh ran from the repo root" '[ "$(cat "$repo/install-cwd" 2>/dev/null)" = "$(cd "$repo" && pwd -P)" ]'

# --- a repo that is both a skills repo and a config repo is report-only: config wins
seed both config
w="$t/seed/both"; mkdir -p "$w/skills/dev-both"; printf '# dev-both\n' > "$w/skills/dev-both/SKILL.md"
git -C "$w" add -A; git -C "$w" commit -qm skill; git -C "$w" push -q origin HEAD
repo="$t/local/both"; clone_repo both "$repo"
advance both "claude-settings.json" '{"permissions":{"allow":["Bash(ls:*)"]}}' "remote both"
H="$t/home-both"; base_home "$H"; link_skill "$H" "$repo" dev-both
ln -s "$repo/claude-settings.json" "$H/.claude/settings.json"
before=$(git -C "$repo" rev-parse HEAD)
printf 'y\n' | apply_yes "$H" > "$t/both.out" 2>&1
ok "config wins: behind is reported, not pulled" 'grep -qx "behind  sync:both  1 commits (config, not pulled)" "$t/both.out"'
ok "config wins: head unchanged" '[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]'
ok "config wins: never prompts to pull" '! grep -q "Pull .* into both" "$t/both.out"'

# --- after a dev-kit pull, install.sh runs once so a new skills/dev-* is linked in the same run
kseed="$t/seed/kitpull"
git init -q --bare -b main "$t/remotes/kitpull.git"
git init -q -b main "$kseed"
mkdir -p "$kseed/bin" "$kseed/skills/dev-sync"
cp "$here/bin/setup" "$kseed/bin/setup"
cp "$here/install.sh" "$kseed/install.sh"; chmod +x "$kseed/install.sh"
printf '# dev-sync\n' > "$kseed/skills/dev-sync/SKILL.md"
git -C "$kseed" remote add origin "$t/remotes/kitpull.git"
git -C "$kseed" add -A; git -C "$kseed" commit -qm base; git -C "$kseed" push -q -u origin main
local="$t/local/kitpull"; clone_repo kitpull "$local"
w="$t/seed/kitpull"; mkdir -p "$w/skills/dev-new"; printf '# dev-new\n' > "$w/skills/dev-new/SKILL.md"
git -C "$w" add -A; git -C "$w" commit -qm "new skill"; git -C "$w" push -q origin HEAD
H="$t/home-pull"
mkdir -p "$H/.agents/skills" "$H/.claude/skills" "$H/.codex/skills"
ln -s "$local" "$H/.agents/dev-kit"
ln -s "$local/skills/dev-sync" "$H/.agents/skills/dev-sync"
yes | HOME="$H" PATH="$fb:$base_path" /bin/bash "$local/bin/setup" --apply > "$t/pull.out" 2>&1; rc=$?
ok "dev-kit pull: exits 0" '[ $rc -eq 0 ]'
ok "dev-kit pull: install.sh offered once" '[ "$(grep -c "run: .*install.sh" "$t/pull.out")" = 1 ]'
ok "dev-kit pull: the new skill is linked in the same run" '[ -f "$H/.agents/skills/dev-new/SKILL.md" ]'
yes | HOME="$H" PATH="$fb:$base_path" /bin/bash "$local/bin/setup" --apply > "$t/pull2.out" 2>&1
ok "dev-kit pull: the next run offers no relink" '! grep -q "dev-kit: pulled" "$t/pull2.out"'

# --- a pull that rewrites bin/setup cannot break the run: the frozen copy finishes, new code next run
kseed="$t/seed/kitfrozen"
git init -q --bare -b main "$t/remotes/kitfrozen.git"
git init -q -b main "$kseed"
mkdir -p "$kseed/bin" "$kseed/skills/dev-sync"
cp "$here/bin/setup" "$kseed/bin/setup"
printf '# dev-sync\n' > "$kseed/skills/dev-sync/SKILL.md"
git -C "$kseed" remote add origin "$t/remotes/kitfrozen.git"
git -C "$kseed" add -A; git -C "$kseed" commit -qm base; git -C "$kseed" push -q -u origin main
local="$t/local/kitfrozen"; clone_repo kitfrozen "$local"
printf '#!/usr/bin/env bash\necho NEW-CODE-RAN >&2\nexit 9\n' > "$kseed/bin/setup"
git -C "$kseed" add -A; git -C "$kseed" commit -qm rewrite; git -C "$kseed" push -q origin main
H="$t/home-frozen"
mkdir -p "$H/.agents/skills" "$H/.claude/skills" "$H/.codex/skills" \
  "$H/.local/share/tla" "$H/.agents/dev-kit-tools/node_modules/pele" "$H/.bun/bin"
: > "$H/.local/share/tla/tla2tools.jar"
ln -s "$local" "$H/.agents/dev-kit"
ln -s "$local/skills/dev-sync" "$H/.agents/skills/dev-sync"
printf 'y\ny\n' | HOME="$H" PATH="$fb:$base_path" /bin/bash "$local/bin/setup" --apply > "$t/frozen.out" 2>&1; rc=$?
ok "frozen: the old copy finishes" '[ $rc -eq 0 ]'
ok "frozen: new code did not run" '! grep -q NEW-CODE-RAN "$t/frozen.out"'
ok "frozen: pull landed on disk" 'grep -q NEW-CODE-RAN "$local/bin/setup"'
ok "frozen: says the new code runs next time" 'grep -q "frozen copy" "$t/frozen.out" && grep -q "next run" "$t/frozen.out"'
HOME="$H" PATH="$fb:$base_path" /bin/bash "$local/bin/setup" --check > "$t/next.out" 2>&1; rc2=$?
ok "frozen: the next run is the new code" '[ $rc2 -eq 9 ] && grep -q NEW-CODE-RAN "$t/next.out"'

# --- goldens: stable order, no temp paths, one line per repo
H="$t/home-gold"; base_home "$H"; link_skill "$H" "$repo" dev-skillsinst
check "$H" "$t/gold1.out"; check "$H" "$t/gold2.out"
ok "goldens: two checks match" 'cmp -s "$t/gold1.out" "$t/gold2.out"'
ok "goldens: no temp path" '! grep -qF "$t" "$t/gold1.out"'
ok "goldens: line format" 'grep -Eq "^(ok|behind|skipped)  sync:[^ ]+  .+$" "$t/gold1.out"'

echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
