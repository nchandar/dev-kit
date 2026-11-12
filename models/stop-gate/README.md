# Stop-gate accept protocol

TLA+ model of the Claude Code Stop hook: the parent may not end its turn while
a worker it spawned is running or its latest run has no accept newer than its
exit row.

Code under test at `65810a9`:
`bin/stop-gate:13-27` (block counter, fail-open), `bin/reconcile:23-33`
(`gate_task`: `:30` running check, `:33` accept newer than the newest exit row),
`bin/spawn:275` (respawn guard), `:397-407` (`claim_id`), `:478` (start row),
`:481` (status running), `:623-630` (timeout kill), `:655-659` (exit row before
status), `:431-437` (killed rows), `bin/ledger:176-196` (accept append).

## Rules

| Rule | Sentence | Code |
|---|---|---|
| StopNeedsAccept (R1) | A stop without fail-open needs every spawned worker neither running nor never-accepted. | stop-gate:14,17-24; reconcile:30,33 |
| StaleAcceptIgnored (R2) | An accept older than the worker's latest start row never counts. | reconcile:33 `ac>ex`; spawn:478 |
| NoFalseBlock (R3) | A finished worker the parent accepted is not reported outstanding. | reconcile:33; spawn:655-659 |
| FailOpenAfterBlocks (R4) | Fail-open only after `MAX` blocks, and only with work outstanding. | stop-gate:17-24 |
| NoEndTurnWhileRunningOrUnaccepted (R5) | The parent cannot end its turn while a worker runs or its latest run is unaccepted. | stop-gate:14; reconcile:30,33 |

`accepted` is `reconcile:33` exactly: the newest accept row is newer than the
newest row that counts as an exit row, and a running worker is outstanding
whatever its accepts (`reconcile:30`).

## Row types (what counts as an exit row)

`reconcile:33` ignores only the second word `nudge` and `scout`; everything
else with phase `spawn` counts: `running` (start, `:478`), `done|failed|timeout|killed`
(`:656`, `:623-630`, `:431-437`), `isolation-violation` (`:511`),
`owns-overlap` (`:354`), `route-warning` (`:189`). A worker's own accept is now
refused by `bin/ledger:176-196`, so the gate stays a parent decision; the model
already assumes the parent is the only accept writer.

## Run

```sh
./run.sh   # every cfg below, one line each; exits 1 on a mismatch
java -XX:+UseParallelGC -cp "${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}" \
  tlc2.TLC -deadlock -workers 8 -config clean.cfg StopGate.tla
```

Constants: `W={w1,w2,w3}`, `MAXRUNS=2`, `MAXBLOCKS=3`; `chart2` uses 2
workers and `CHECK_DEADLOCK FALSE`.

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
- The 3-block counter is per session and reset on a passing gate; the model
  bounds it at `MAXBLOCKS`.
- Real kills (`kill -9`) run no EXIT trap: the model's `Die` writes no row and
  no status, which is why the start row, not the exit row, keeps a respawn
  unreviewed.
- Pane or agent idleness, `DEVKIT_IDLE_WAIT`, `nudge` and view modes are not
  modelled; they only add rows the gate ignores.
- The worker's own handoff/checklist content is not modelled; `done` is a row.
