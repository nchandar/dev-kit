# Lead claim model (bin/spawn claim_lead)

TLA+ model of the `--lead` cap: one repo-wide owner lock, a per-id claim dir
published before the count, the count of live other claims (reclaiming dead
ones), and the cap decision under the lock. It covers the caller's refusals
(`:328-336`) and cleanup (`:449`).

Code under test: `bin/spawn:305-327` at `65810a9`. The fixed order is modelled:
the cap test and a refusal's `rm -rf` stay under the lock, and a successful
claim is the only path that takes `rm -f "$l"` (`:325-326`).

## Promises

| # | Promise, one sentence | Rule |
|---|---|---|
| I1 | At most MAX accepted lead places are live at any instant. | `LeadsBounded` |
| I2 | A live claimant keeps its candidate dir from mkdir until it accepts or is refused, and a live accepted lead keeps its claim dir. | `NoLostCandidate`, `NoLostLeadPlace` |
| I3 | The cap count counts live claims only, never a stale dir. | `CountsOnlyLive` |
| I4 | Under fair scheduling a stale claim dir, or a lock left by a dead spawner, never blocks new leads forever. | `StaleClaimReclaimed`, `DeadLockStolen` (FairSpec) |
| I5 | Under fair scheduling a refused candidate is removed under the lock, so a live claimant is never refused while no accepted place is live. | `Progress` (FairSpec) |

`LeadsBounded` counts live accepted places, not dirs: a refused claimant's
candidate can still be a live dir before the lock is taken, and every other
claimant counts it and blocks. That is a safe over-block.

## One model action = one code step

| bin/spawn at 65810a9 | Action |
|---|---|
| `slot_live` :280-288 | `LiveDir` (a live pid; wpid and ps lstart excluded) |
| `slot_lock` :289-299 | `LeadClaimStart` (one atomic take/steal) |
| same-id read :311-312 | `LeadSameIdRefuse` (return 3, caller exits 2) |
| `rm -rf`; `mkdir` :313 | `LeadPublish` |
| start + pid :315-316 | `LeadWritePid` / `LeadPublishFail` |
| count live others, `rm -rf` dead :317-321 | `LeadCountOthers` (one command block under the lock) |
| verify own pid :322 | `LeadVerifyOwn` / `LeadVerifyFail` |
| `nlead < MAX` :325 | `LeadAccept` (under the lock) |
| `nlead >= MAX` :325 | `LeadRefuse` (rm -rf then unlock, under the lock) |
| `rm -f "$l"` :326 | the unlock after a successful cap test |
| cleanup :449 | `LeadRelease` |
| any kill -9 | `Die` (no EXIT trap) |

## Run

```sh
./run.sh   # every cfg below, one line each; exits 1 on a mismatch
java -XX:+UseParallelGC -cp "${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}" \
  tlc2.TLC -deadlock -workers 4 -metadir states/LeadClaim-cap2 -config LeadClaim-cap2.cfg LeadClaim.tla
```

| cfg | expected TLC line |
|---|---|
| LeadClaim-cap1.cfg, LeadClaim-cap2.cfg (Spec, 3 actors) | `Model checking completed. No error has been found.` |
| LeadClaim-live-cap1.cfg, LeadClaim-live-cap2.cfg (FairSpec) | `Model checking completed. No error has been found.` |
| LeadClaim-progress-cap1.cfg (FairSpec, Progress) | `Model checking completed. No error has been found.` |
| LeadClaimChart.cfg | `Model checking completed. No error has been found.` |
| broken-NoLock-cap1.cfg (NoLock) | `Error: Invariant NoLostCandidate is violated.` |
| broken-CountFirst-cap1.cfg (CountFirst) | `Error: Invariant LeadsBounded is violated.` |
| broken-NoLockSteal-cap1.cfg (NoLockSteal) | `Error: Temporal properties were violated.` |
| broken-CountStale-cap1.cfg (CountStale) | `Error: Invariant CountsOnlyLive is violated.` |
| broken-CountStale-live.cfg (CountStale, FairSpec) | `Error: Temporal properties were violated.` |

`gen-variants.py` writes the four broken copies from `LeadClaim.tla`;
`gen-chart.py` writes `LeadClaimChart.tla`, which drops `Die` and the
stale/dead initial states so the chart stays readable.

## Progress: the window the fixed order closes

Before the fix, the cap test ran after `rm -f "$l"` and the caller removed a
refused candidate, so two claimants could each count the other's live
candidate and both be refused while no accepted place was live.
`LeadClaim-progress-cap1` reported `Error: Temporal properties were violated.`
With the cap test and refusal removal under the lock that interleaving is gone;
the config now passes. `replay.sh stalled` stalls a claimant after it publishes
its pid, before the count, and still admits exactly one lead.

## Live replay

`replay.sh` builds a scratch git repo, a fake CLI, and runs two real concurrent
`bin/spawn --lead` at `DEVKIT_MAX_LEADS=1`; `HOME` is the scratch dir. From
this directory:

```sh
bash replay.sh fixed     # HEAD: exactly 1 lead starts, the loser exits 4
bash replay.sh stalled   # HEAD + a 2s stall after the lead-dir mkdir: 1 lead
bash replay.sh old       # 7e98b33^ (count-then-start): 2 leads start (the race)
```

`old` is the break test: it shows the replay can still fail. The repo guard for
the cap is `tests/spawn-lead-cap.test.sh`.

## What the timing exclusions leave out

- The lock retry budget (`tries < 100`, 10ms sleeps, `:307-310`): the model
  waits without bound. A timeout only drops a lead (exit 4), never admits one.
  Measured live: a 2s stall still got the lock (the real budget is ~2.5s
  because each try forks `ps`).
- `slot_lock` as one atomic take/steal. Two stealers of a dead owner's symlink,
  and the legacy dir-lock branch, are excluded.
- Pid reuse and `ps -o lstart` granularity: `alive[p]` is "pid alive and start
  matches"; reused-pid reclaim is covered only by the test.
- `wpid` (`:618`): a dead spawner whose worker still runs keeps its place. The
  model's `Die` drops that link; only the test covers it.
- The signal gap between `mkdir` (`:313`) and `leadclaim=$c` (`:314`): the model
  publishes in one step.
- `DEVKIT_MAX_LEADS` is per run; a cap lowered while leads are live is not
  modelled (live places are not evicted).
- The count loop is one action; the lock is what makes the batch read sound
  (`broken-NoLock-cap1` shows the difference).
