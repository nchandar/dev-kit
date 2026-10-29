# quality-bar
Record the bar and any change to it with bin/ledger (phase=quality-bar).

## When to Use
- Project start, or when output quality drifts, or when a change touches test, lint or CI config.

## Steps
1. Interview the user on which dimensions matter (tests, types, lint, coverage floor, perf budget, security); propose sane defaults; do not invent thresholds silently.
2. Write `CONSTRAINTS.md` (max 30 lines) with the agreed thresholds and the command that checks each.
3. Run the commands as the baseline and ledger the numbers.
4. Any diff that touches thresholds, skips, ignores, `--no-verify`, `@ts-ignore`, disabled lint rules, loosened assertions or deleted tests is flagged and needs the user's approval.
5. Re-run the baseline after each slice; the bar may only move up.
6. An instruction you keep repeating becomes a check, lint rule or script, not more prose.

## Red Flags
- Getting green by lowering the bar: a skipped test, loosened assertion, raised timeout or suppressed warning.
- A bar nobody can run with one command.

## Verification
- Baseline numbers are in the ledger; the diff shows no unapproved bar changes; every check command exits 0.
