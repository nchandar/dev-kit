#!/usr/bin/env bash
# Tests for bin/model-drift: in-sync, drifted, bad records and a read-only record.
# Usage: tests/model-drift.test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
drift="$here/bin/model-drift"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1   [$2]"; fi; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

repo="$t/repo"; mkdir -p "$repo"
git -C "$repo" init -q
printf 'a\n' > "$repo/a.txt"
printf 'b\n' > "$repo/b.txt"
printf 'c\n' > "$repo/c.txt"
git -C "$repo" add . && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm one
sync=$(git -C "$repo" rev-parse HEAD)
rec="$t/coverage.env"
printf 'sync=%s\nfiles=a.txt b.txt\ncmd=go test ./...\n' "$sync" > "$rec"
before=$(cksum < "$rec")

out=$("$drift" "$rec" --repo "$repo" 2>&1); rc=$?
ok "in sync: exits 0" '[ $rc -eq 0 ]'
ok "in sync: prints one line in-sync" '[ "$out" = in-sync ] && [ "$(printf "%s\n" "$out" | wc -l | tr -d " ")" = 1 ]'
out=$("$drift" --repo "$repo" "$rec" 2>&1); rc=$?
ok "repo before record: exits 0" '[ $rc -eq 0 ] && [ "$out" = in-sync ]'
out=$(cd "$repo" && "$drift" "$rec" 2>&1); rc=$?
ok "default repo: exits 0" '[ $rc -eq 0 ] && [ "$out" = in-sync ]'

printf 'c2\n' > "$repo/c.txt"; git -C "$repo" -c user.name=t -c user.email=t@t commit -qam two
out=$("$drift" "$rec" --repo "$repo" 2>&1); rc=$?
ok "uncovered change: stays in sync" '[ $rc -eq 0 ] && [ "$out" = in-sync ]'

printf 'a2\n' > "$repo/a.txt"; printf 'b2\n' > "$repo/b.txt"; git -C "$repo" -c user.name=t -c user.email=t@t commit -qam three
out=$("$drift" "$rec" --repo "$repo" 2>&1); rc=$?
ok "drifted: exits 1" '[ $rc -eq 1 ]'
ok "drifted: lists covered files in record order" '[ "$out" = "drifted: a.txt b.txt" ]'

typo="$t/typo.env"; printf 'sync=%s\nfiles=a.txt nope.txt\n' "$sync" > "$typo"
out=$("$drift" "$typo" --repo "$repo" 2>&1); rc=$?
ok "mistyped covered path: exits 2, never in-sync" '[ $rc -eq 2 ] && echo "$out" | grep -q "nope.txt"'

rec2="$t/c.env"; printf 'sync=%s\nfiles=c.txt\n' "$(git -C "$repo" rev-parse HEAD)" > "$rec2"
printf 'c3\n' > "$repo/c.txt"
out=$("$drift" "$rec2" --repo "$repo" 2>&1); rc=$?
ok "uncommitted edit of a covered file: drifted" '[ $rc -eq 1 ] && [ "$out" = "drifted: c.txt" ]'
git -C "$repo" checkout -q -- c.txt
rm "$repo/b.txt"; rec3="$t/b.env"; printf 'sync=%s\nfiles=b.txt\n' "$sync" > "$rec3"
out=$("$drift" "$rec3" --repo "$repo" 2>&1); rc=$?
ok "deleted covered file: drifted" '[ $rc -eq 1 ] && [ "$out" = "drifted: b.txt" ]'
git -C "$repo" checkout -q -- b.txt

bad="$t/unknown.env"; printf 'sync=%s\nfiles=a.txt\n' 0123456789012345678901234567890123456789 > "$bad"
out=$("$drift" "$bad" --repo "$repo" 2>&1); rc=$?
ok "unknown sync sha: exits 2" '[ $rc -eq 2 ]'
ok "unknown sync sha: says so" 'echo "$out" | grep -qi "unknown sync"'

nosync="$t/nosync.env"; printf 'files=a.txt\n' > "$nosync"
"$drift" "$nosync" --repo "$repo" >/dev/null 2>&1; rc=$?
ok "missing sync key: exits 2" '[ $rc -eq 2 ]'
nofiles="$t/nofiles.env"; printf 'sync=%s\n' "$sync" > "$nofiles"
"$drift" "$nofiles" --repo "$repo" >/dev/null 2>&1; rc=$?
ok "missing files key: exits 2" '[ $rc -eq 2 ]'

# record format: comments, blank lines, unknown keys, no trailing newline, CRLF, bad lines
fresh="$t/fresh"; mkdir -p "$fresh/dir"; git -C "$fresh" init -q
printf 'x\n' > "$fresh/x.txt"; printf 'y\n' > "$fresh/dir/y.txt"
git -C "$fresh" add . && git -C "$fresh" -c user.name=t -c user.email=t@t commit -qm one
fs=$(git -C "$fresh" rev-parse HEAD)
printf '# model for x\n\nnote=ignored\nsync=%s\nfiles=x.txt dir\ncmd=run it\n' "$fs" > "$t/rich.env"
out=$("$drift" "$t/rich.env" --repo "$fresh" 2>&1); rc=$?
ok "comments, blank lines and unknown keys are ignored" '[ $rc -eq 0 ] && [ "$out" = in-sync ]'
printf 'sync=%s\nfiles=x.txt' "$fs" > "$t/nonl.env"
out=$("$drift" "$t/nonl.env" --repo "$fresh" 2>&1); rc=$?
ok "last line without a newline is read" '[ $rc -eq 0 ] && [ "$out" = in-sync ]'
printf 'sync=%s\r\nfiles=x.txt\r\n' "$fs" > "$t/crlf.env"
"$drift" "$t/crlf.env" --repo "$fresh" >/dev/null 2>&1; rc=$?
ok "CRLF record never reads as in-sync" '[ $rc -ne 0 ]'
printf 'sync=%s\nfiles x.txt\n' "$fs" > "$t/noeq.env"
"$drift" "$t/noeq.env" --repo "$fresh" >/dev/null 2>&1; rc=$?
ok "a line without = is a bad record: exits 2" '[ $rc -eq 2 ]'

printf 'z\n' > "$fresh/dir/z.txt"
out=$("$drift" "$t/rich.env" --repo "$fresh" 2>&1); rc=$?
ok "new untracked file inside a covered directory: drifted" '[ $rc -eq 1 ] && [ "$out" = "drifted: dir" ]'
rm "$fresh/dir/z.txt"
printf 'new\n' > "$fresh/new.txt"
printf 'sync=%s\nfiles=new.txt\n' "$fs" > "$t/added.env"
out=$("$drift" "$t/added.env" --repo "$fresh" 2>&1); rc=$?
ok "covered file added after the sync commit: drifted" '[ $rc -eq 1 ] && [ "$out" = "drifted: new.txt" ]'
rm "$fresh/new.txt"
printf 'y2\n' > "$fresh/dir/y.txt"
out=$("$drift" "$t/rich.env" --repo "$fresh" 2>&1); rc=$?
ok "edit under a covered directory: drifted" '[ $rc -eq 1 ] && [ "$out" = "drifted: dir" ]'
git -C "$fresh" checkout -q -- dir/y.txt
out=$("$drift" "$t/rich.env" --repo "$fresh/dir" 2>&1); rc=$?
ok "--repo may name a subdirectory: paths stay repo-root relative" '[ $rc -eq 0 ] && [ "$out" = in-sync ]'
out=$("$drift" "$t/rich.env" --repo "$fresh" 2>&1 >/dev/null)
ok "in-sync writes nothing to stderr" '[ -z "$out" ]'

# usage errors all exit 2 with a message on stderr
"$drift" "$t/nope.env" --repo "$fresh" >/dev/null 2>&1; rc=$?
ok "missing record file: exits 2" '[ $rc -eq 2 ]'
"$drift" "$t/rich.env" --repo "$t/not-a-dir" >/dev/null 2>&1; rc=$?
ok "missing repo dir: exits 2" '[ $rc -eq 2 ]'
plain="$t/plain"; mkdir -p "$plain"
"$drift" "$t/rich.env" --repo "$plain" >/dev/null 2>&1; rc=$?
ok "not a git repo: exits 2" '[ $rc -eq 2 ]'
"$drift" "$t/rich.env" --bogus >/dev/null 2>&1; rc=$?
ok "unknown flag: exits 2" '[ $rc -eq 2 ]'
"$drift" "$t/rich.env" --repo >/dev/null 2>&1; rc=$?
ok "--repo without a value: exits 2" '[ $rc -eq 2 ]'
"$drift" "$t/rich.env" "$t/rich.env" >/dev/null 2>&1; rc=$?
ok "two records: exits 2" '[ $rc -eq 2 ]'
err=$("$drift" "$t/rich.env" --bogus 2>&1 >/dev/null)
ok "usage error prints model-drift: on stderr" 'echo "$err" | grep -q "^model-drift:"'

"$drift" >/dev/null 2>&1; rc=$?
ok "no arguments: exits 2" '[ $rc -eq 2 ]'

after=$(cksum < "$rec")
ok "record is never modified" '[ "$before" = "$after" ]'
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
