# publish-repo-safely

## When to Load
- Making a private or local repo public.
- The first push of history nobody has reviewed.

## Steps
1. Confirm the target: `gh repo view <owner>/<repo> --json visibility,isEmpty`. It must exist and be empty. Audit before any push.
2. Audit the tree for secrets, home paths, emails, hostnames, runtime state, licence, README accuracy.
3. Audit the whole history, not just the tree: `git log -p -S'<pattern>' --all` per pattern (key prefixes, `/Users/`, `@`).
4. Add a licence. Add README rules for what must never be committed.
5. Add a lint that fails on home paths, emails (except example.com) and secret-shaped strings.
6. Build the lint's test fixtures at runtime, so the repo holds no literal path, address or key marker.
7. Run an independent audit with a second agent over the final tree and history. Read its handoff, fix real findings.
8. If nothing was ever pushed, set the intended identity: `git config user.name` and `user.email`.
9. Rewrite authorship: `git branch backup-pre-rewrite`, then `git rebase --root --exec 'git commit --amend --no-edit --reset-author'`. Verify, then `git branch -D backup-pre-rewrite`.
10. Decide the policy on co-author trailers in commit messages and strip them now if banned: `git log --format=%B | rg -i co-authored`.
11. Push the main branch only: `git push origin main`. Never the backup branch.
12. Clone the public URL into a fake HOME (`HOME=$(mktemp -d) git clone ...`). Run the installer, health check and tests there.

## Gotchas
- The commit email becomes public. Use the host's noreply address if email privacy is on, or the push is rejected.
- A scout flags a false violation if you commit while it runs. Freeze the tree until it reports.
- Piping an installer through `head` can kill it with a broken pipe. Log to a file instead.
- Empty arrays fail under `set -u` in bash 3.2. Use `${a[@]+"${a[@]}"}`.
- History rewrite changes every hash. Do it before the first push, never after.

## Verified
2026-10-29: git 2.56, macOS bash 3.2, claude 2.1.x, codex 0.165, opencode 2.2.

Source: learned publishing a skills repo
