# ci-loop

## When to Load
- A CI check is red, pending too long, or flaky on a branch or on main.

## Pattern
1. Read the failed log first: `gh run view <id> --log-failed` (or `gh pr checks <n>` to find the run). Quote the failing line in the ledger.
2. Reproduce the failure locally with the same command CI runs. Cannot reproduce: suspect environment, then ordering or time.
3. Fix the cause, or revert the change that broke it. Whoever sees red on main first owns it until it is green; do not wait for the author.
4. Never retry-pass: a rerun that goes green hides a flaky test or a race. Treat flaky as a bug (library/debug-method) and fix it.
5. Never loosen a test, raise a timeout or skip a check to get green (library/quality-bar).
6. CI over about 10 minutes: split suites, cache installs, run the cheap checks first.
7. After the fix, read the new run to the end; green on one job is not green.
8. Record each red run, its cause and the fix with `bin/ledger` (phase=verify).

## Red Flags
- Rerunning until green; merging with a pending or missing check.
- A fix that touches the test and not the code, with no reason.

Source: agent-skills/ci-cd-and-automation
