# git-ship
Record the commit hashes and the ship decision with bin/ledger (phase=ship).

## When to Use
- Committing, branching, preparing a change for merge or release.

## Steps
1. Scope check: `git status -sb`, `git diff --stat`. No strays, no secrets, no generated noise.
2. Never add an AI as author, co-author or contributor: no `Co-Authored-By` or "Generated with" lines. One logical change per commit; message states intent and, for fixes, the root cause. Stack commits in the order that proves the work (failing test, then fix).
3. Branch per task; never commit to main directly unless the repo says so.
4. Pre-merge: tests, lint, typecheck, and the verify checks all green on the final diff.
5. For risky changes: rollback plan in one line, and how you will know it broke (see library/observability).
6. Ask the user before pushing, opening a PR, merging or tagging. Never force-push shared branches.

## Red Flags
- Huge mixed commits; "wip" history on a shared branch.
- Skipping hooks (`--no-verify`) to get past a check.
- Pushing without being asked.

## Verification
- Clean `git status`; each commit builds and passes tests; the user approved any push.
