# launch-and-rollback

## When to Load
- A change ships to users of a tool or service, and a bad release is costly or hard to undo.

## Pattern
1. Before shipping, write the rollback in one line (revert, flag off, previous version) and prove it runs once.
2. Define "working": the signals that say the release is healthy (library/observability) and their normal values.
3. Staged rollout: a small slice first (your own use, then a few users, then all). Hold at each stage long enough for the signals to move; widen only when they stay inside the thresholds.
4. Rollback triggers, set before launch: error rate above the threshold, latency or saturation past its limit, any data-loss or security signal. Hitting one means roll back first, investigate after.
5. Tools without a service: ship to a scratch install first, then one real project, then everyone; the signals are the ledger rows and exit codes.
6. Irreversible steps (data drops, schema contracts) ship alone, after the reversible ones have held.
7. After full rollout, read the signals once more and ledger the result with `bin/ledger` (phase=ship).

## Red Flags
- "Roll back" with no tested command.
- Thresholds chosen after seeing the numbers.
- A big-bang release of a change that cannot be undone.

Source: agent-skills/shipping-and-launch
