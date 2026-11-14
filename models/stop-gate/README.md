# Stop-gate accept protocol

TLA+ model of the Claude Code Stop hook: the parent may not end its turn while
a worker it spawned is running or its latest run has no accept newer than its
exit row, except that a live host-tracked waiter lets it park the turn until the
waiter exits and wakes it.

Code under test at `d6e9d69`:
`bin/stop-gate:12,35` (block counter), `:31-33` (reconcile exit: 0 passes and
clears the counter), `:49-64` (hold text), `:65-70` (fail-open and its ledger
row), `:19-30,34` (the tracked-waiter pass), `bin/reconcile:24-34` (`gate_task`:
`:30` running check, `:33` accept newer than the newest exit row), `:59-71`
(`--wait` polls until nothing runs), `bin/spawn:275` (respawn guard), `:397-407`
(`claim_id`), `:478` (start row), `:481` (status running), `:623-630` (timeout
kill), `:655-659` (exit row before status), `:431-437` (killed rows),
`bin/ledger:176-196` (accept append).

## Rules

| Rule | Sentence | Code |
|---|---|---|
| StopNeedsAccept (R1) | A final stop without fail-open needs every spawned worker neither running nor never-accepted. | stop-gate:31-33,49-70; reconcile:30,33 |
| StaleAcceptIgnored (R2) | An accept older than the worker's latest start row never counts. | reconcile:33 `ac>ex`; spawn:478 |
| NoFalseBlock (R3) | A finished worker the parent accepted is not reported outstanding. | reconcile:33; spawn:655-659 |
| FailOpenAfterBlocks (R4) | Fail-open only after `MAX` blocks, and only with work outstanding. | stop-gate:31,35,65-70 |
| NoEndTurnWhileRunningOrUnaccepted (R5) | The parent cannot end its turn while a worker runs or its latest run is unaccepted, unless a tracked waiter is live: that stop is parked, not final, and R6 guards it. | stop-gate:31-33; reconcile:30,33 |
| WaiterWakesParent (R6) | A stop that passes under a waiter is never final while work is outstanding: the turn is over only with a live tracked waiter, whose exit re-invokes the parent. | stop-gate:19-30,34; reconcile:59-71 |

`accepted` is `reconcile:33` exactly: the newest accept row is newer than the
newest row that counts as an exit row, and a running worker is outstanding
whatever its accepts (`reconcile:30`).

`stopped` is a final stop. A stop that passes on a live tracked waiter sets
`parked` instead (`stop-gate:34`): the turn is over, the parent is asleep, its
workers keep running, and the host re-invokes the parent when the waiter exits.
R1 and R5 describe the final stop; the waiter pass is their stated exception and
R6 is the promise that replaces it. `waiter` is `tracked` when the host lists the
task in `background_tasks` (`stop-gate:21-30`) and `untracked` for a nohup or
detached waiter, which exits the same way but never wakes the parent.

## Row types (what counts as an exit row)

`reconcile:33` ignores only the second word `nudge` and `scout`; everything
else with phase `spawn` counts: `running` (start, `:478`), `done|failed|timeout|killed`
(`:656`, `:623-630`, `:431-437`), `isolation-violation` (`:511`),
`owns-overlap` (`:354`), `route-warning` (`:189`). A worker's own accept is now
refused by `bin/ledger:176-196`, so the gate stays a parent decision; the model
already assumes the parent is the only accept writer. The tracked-waiter pass
writes no row and leaves the counter file alone (`stop-gate:34`), so it neither
resets the hold count nor records a decision.

## Run

```sh
./run.sh   # every cfg below, one line each; exits 1 on a mismatch
java -XX:+UseParallelGC -cp "${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}" \
  tlc2.TLC -deadlock -workers 8 -config clean.cfg StopGate.tla
```

Constants: `W={w1,w2,w3}`, `MAXRUNS=2`, `MAXBLOCKS=3`, `TRACKEDONLY=TRUE`
(`broken-R6` sets it FALSE); `chart2` uses 2 workers and `CHECK_DEADLOCK FALSE`.

| cfg | expected TLC line |
|---|---|
| clean.cfg, clean-noguard.cfg, clean-nudge.cfg | `Model checking completed. No error has been found.` |
| chart2.cfg | `Model checking completed. No error has been found.` |
| clean-early.cfg | `Error: Invariant NoFalseBlock is violated.` |
| broken-R1.cfg | `Error: Invariant StopNeedsAccept is violated.` |
| broken-R2.cfg | `Error: Invariant StaleAcceptIgnored is violated.` |
| broken-R3.cfg, broken-R3b.cfg | `Error: Invariant NoFalseBlock is violated.` |
| broken-R4.cfg | `Error: Invariant FailOpenAfterBlocks is violated.` |
| broken-R5.cfg | `Error: Invariant StaleAcceptIgnored is violated.` |
| broken-R5b.cfg | `Error: Invariant NoEndTurnWhileRunningOrUnaccepted is violated.` |
| broken-R6.cfg | `Error: Invariant WaiterWakesParent is violated.` |

`clean-early` is not a pass case: it states the assumption that an accept
written before the exit row is harmless. R3 falsifies it (the gate over-blocks
once and heals on the next accept), which is why the code publishes the row
first.

## Live replay

`replay.sh` copies `bin/` into a scratch `DEVKIT_DIR`, uses a fake CLI, and
drives the real scripts. The repo is read-only. Three injected variants of
`bin/spawn` in the scratch copy are the break tests: a stall before the exit
row, the status written before the row (pre-PR-25), and no start row. From this
directory:

```sh
bash replay.sh   # 37 assertions; exit 0 = all pass
```

The replay covers: a mid-run accept is stale (C1), an accept of run 1 does not
cover run 2 (C2/C2b), an early accept is a false block and the broken order is
caught (C3), fail-open after 3 blocks (C4), timeout (C5), killed (C6), the
respawn guard (C7), and a signal before the worker launch that writes no row
(C8, breaks no rule; the gate still blocks).

## What the timing exclusions leave out

- The status file is read non-atomically; a half-written status is skipped by
  `reconcile:27`, and `spawn:655-659` writes the row before the status.
- The 3-block counter is per session and reset when the gate passes with
  nothing outstanding (`stop-gate:32`); a waiter pass leaves it alone (`:34`).
  The model bounds it at `MAXBLOCKS`.
- Real kills (`kill -9`) run no EXIT trap: the model's `Kill9` writes no row and
  no status, which is why the start row, not the exit row, keeps a respawn
  unreviewed.
- Pane or agent idleness, `DEVKIT_IDLE_WAIT`, `nudge` and view modes are not
  modelled; they only add rows the gate ignores.
- The worker's own handoff/checklist content is not modelled; `done` is a row.
- The hook parses the payload with `sed` (`stop-gate:23-25`): a pretty-printed
  payload, a nested `background_tasks` array or any other parse doubt holds, and
  the model takes the waiter's presence and tracking as a fact.
- The interactive (non-headless) Stop payload was not captured; the docs say it
  has the same shape as the headless one the research logged.
- A same-user spoof passes the stop: any shell task whose command contains
  `reconcile --wait` matches (`stop-gate:29`). This is not a security boundary,
  the same stance as the push guard. The match is also text-only, so a waiter on
  another session passes, and the model treats it as tracked.
- A tracked waiter still live at a clean stop (nothing outstanding) is not
  modelled past `Done`; its exit only re-invokes an idle parent.
- The parent cannot spawn while parked (it is asleep); the worker lifecycle,
  kills and exit rows keep running until the waiter sees nothing running
  (`reconcile:59-71`).
- The `DEVKIT_WAIT` cap (`reconcile:68`) is not modelled: a timed-out waiter
  exits with workers still running, and a tracked one still wakes the parent.
  The model's waiter exits only when nothing runs.
