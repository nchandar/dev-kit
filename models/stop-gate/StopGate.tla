---- MODULE StopGate ----
\* Stop-gate accept protocol, re-synced to bin/stop-gate at d6e9d696b2c0c70b5a95994680b35b7570a146d5.
\* Code: bin/stop-gate:12,35 (block counter), :31-33 (reconcile exit: 0 passes and
\*   clears the counter), :49-64 (hold text), :65-70 (fail-open + ledger row),
\*   :19-30 waiter_running (one background_tasks object with type shell, status
\*   running and a command containing "reconcile --wait"), :34 the stop that passes
\*   on a tracked waiter with the counter and the ledger untouched,
\*   bin/reconcile:24-34 (gate_task: :30 running check, :33 ac>ex over spawn rows
\*   except nudge/scout), :59-71 (--wait polls until nothing runs),
\*   bin/spawn:275 (status guard), :397-407 claim_id (atomic same-id claim),
\*   :478 (start row), :481 (status running), :623-630 timeout guard,
\*   :655-659 exit order, :431-437 killed rows,
\*   bin/ledger:176-196 (accept append: refuses a worker's own or a sibling id,
\*   checks a lead's base, and has no check that the run exited).
\*
\* The gate compares the newest accept row with the newest row that counts as an
\* exit row (reconcile:33 `ac>ex`). Absolute row numbers are not modelled: only
\* the two comparisons matter, and each is one boolean per worker.
\*   accEx    = the newest accept is newer than the newest exit-relevant row
\*              (what reconcile:33 tests)
\*   accStart = the newest accept is newer than the newest start row
\*              (the accept belongs to the latest run)
\*   ever     = an accept row exists at all (what old R1 called reviewed)
\*
\* The turn has two ways to end: `stopped` is a final stop, `parked` is the stop
\* that passed on a live tracked waiter (stop-gate:34). While parked the parent is
\* asleep and its workers keep running; the tracked waiter exits once nothing runs
\* (reconcile:59-71) and the host re-invokes the parent (stop-gate:19-20,34), so
\* the model wakes with parked' = FALSE. A nohup waiter is untracked: it exits the
\* same way but never wakes the parent, which is what broken-R6 exposes.
EXTENDS Naturals, FiniteSets
CONSTANTS W, MAXBLOCKS, MAXRUNS,
          GUARD_STATUS, \* spawn:275: status "running" + pid answers refuses a respawn (TRUE = code)
          ROWORDER,     \* "rowfirst" = exit row before status (code); "statusfirst" = pre-PR-25
          RUNCHECK,     \* reconcile:30: a running worker is outstanding whatever its accepts (TRUE = code)
          NEWERROW,     \* reconcile:33: ac > ex (FALSE = any accept row counts)
          STARTROW,     \* spawn:478: the start row clears the accept (TRUE = code)
          NUDGEIGNORED, \* reconcile:33: nudge and scout rows are not exit rows (TRUE = code)
          OPENAT,       \* blocks spent before fail-open (code: OPENAT = MAXBLOCKS)
          GATE_ACCEPTS, \* FALSE = the gate never honours an accept row (break for R3 only)
          EARLY,        \* "any" = a parent may accept before the exit row exists; "end" = only at a terminal pc
          TRACKEDONLY   \* stop-gate:21-30,34: only a host-listed waiter passes (FALSE = break for R6)

VARIABLES pc, status, alive, accEx, accStart, ever, reviewed, timedout,
          nruns, blocks, stopped, failopen, parked, waiter
vars == <<pc, status, alive, accEx, accStart, ever, reviewed, timedout,
          nruns, blocks, stopped, failopen, parked, waiter>>

\* pc: none | guarded (passed :275, before :478) | started (:478, before :481)
\*     | running | leaving (worker done, before :656) | rowDone (:656, before :659)
\*     | statusDone (:659 before the row, only in "statusfirst") | killed (:431, before :437)
\*     | finished | crashed (kill -9: no row, no status write)
Statuses == {"none", "running", "done", "failed", "timeout", "killed"}
Pcs == {"none", "guarded", "started", "running", "leaving", "rowDone",
         "statusDone", "killed", "finished", "crashed"}
Waiters == {"none", "tracked", "untracked"} \* tracked = a background_tasks entry

Init == /\ pc = [w \in W |-> "none"] /\ status = [w \in W |-> "none"]
        /\ alive = [w \in W |-> FALSE]
        /\ accEx = [w \in W |-> FALSE] /\ accStart = [w \in W |-> FALSE]
        /\ ever = [w \in W |-> FALSE] /\ reviewed = [w \in W |-> FALSE]
        /\ timedout = [w \in W |-> FALSE]
        /\ nruns = [w \in W |-> 0] /\ blocks = 0
        /\ stopped = FALSE /\ failopen = FALSE
        /\ parked = FALSE /\ waiter = "none"

\* --- the gate's own view (bin/reconcile:24-34) ----------------------------
Running(w) == status[w] = "running" /\ alive[w]   \* reconcile:30 kill -0
Accepted(w) == IF NEWERROW THEN accEx[w] ELSE ever[w]
GateAccepted(w) == GATE_ACCEPTS /\ ~(RUNCHECK /\ Running(w)) /\ Accepted(w)
Outstanding == {w \in W : pc[w] # "none" /\ ~GateAccepted(w)}

\* --- the parent's turn and the waiter (bin/stop-gate:19-30,34) ------------
TurnOpen == ~stopped /\ ~parked                       \* the parent may act
LiveWaiter == waiter # "none"
LiveTrackedWaiter == waiter = "tracked"
\* :21-30 reads only background_tasks, so only a tracked waiter can pass;
\* ~TRACKEDONLY is the break for R6 (a gate that also honours a nohup waiter)
WaiterPass == LiveTrackedWaiter \/ (~TRACKEDONLY /\ waiter = "untracked")

\* --- spawn, one code step per action -------------------------------------
\* :275 status guard; claim_id :397-407 adds the atomic same-id claim; run from none, finished or crashed
GuardPass(w) ==
  /\ TurnOpen
  /\ nruns[w] < MAXRUNS
  /\ \/ pc[w] \in {"none", "finished", "crashed"}   \* :275 lets these through
     \/ ~GUARD_STATUS /\ pc[w] \in {"leaving", "rowDone", "statusDone", "killed"} \* break: respawn mid-exit
  /\ pc' = [pc EXCEPT ![w] = "guarded"]
  /\ UNCHANGED <<status, alive, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* :478 the start row, "<id> running": a respawn is unreviewed from here on
StartRow(w) ==
  /\ TurnOpen /\ pc[w] = "guarded"
  /\ accEx' = [accEx EXCEPT ![w] = IF STARTROW THEN FALSE ELSE accEx[w]]
  /\ accStart' = [accStart EXCEPT ![w] = FALSE]   \* the start row is always newer than any accept
  /\ reviewed' = [reviewed EXCEPT ![w] = FALSE]
  /\ nruns' = [nruns EXCEPT ![w] = nruns[w] + 1]
  /\ pc' = [pc EXCEPT ![w] = "started"]
  /\ UNCHANGED <<status, alive, ever, timedout, blocks, stopped, failopen,
                  parked, waiter>>

\* :481 status "running $$" (and the old handoff and timeout marker are removed)
WriteRunning(w) ==
  /\ ~stopped /\ pc[w] = "started"
  /\ status' = [status EXCEPT ![w] = "running"]
  /\ alive' = [alive EXCEPT ![w] = TRUE]
  /\ timedout' = [timedout EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "running"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, nruns, blocks, stopped,
                  failopen, parked, waiter>>

\* the worker ends on its own, or the DEVKIT_TIMEOUT guard kills it (:623-630)
WorkerExits(w) ==
  /\ ~stopped /\ pc[w] = "running"
  /\ pc' = [pc EXCEPT ![w] = "leaving"]
  /\ UNCHANGED <<status, alive, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>
TimeoutKill(w) ==
  /\ ~stopped /\ pc[w] = "running"
  /\ timedout' = [timedout EXCEPT ![w] = TRUE]
  /\ pc' = [pc EXCEPT ![w] = "leaving"]
  /\ UNCHANGED <<status, alive, accEx, accStart, ever, reviewed,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* :431-437 a signal or an interrupted run: killed row, then status "killed"
KillWorker(w) ==
  /\ ~stopped /\ pc[w] = "running"
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "killed"]
  /\ UNCHANGED <<status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>
KilledStatus(w) ==
  /\ ~stopped /\ pc[w] = "killed"
  /\ status' = [status EXCEPT ![w] = "killed"]
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "finished"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* kill -9 of spawn: no row, no status write; the pid in the status file is dead
Kill9(w) ==
  /\ ~stopped /\ pc[w] \in {"guarded", "started", "running", "leaving", "rowDone", "statusDone"}
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "crashed"]
  /\ UNCHANGED <<status, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* rows written while the run is open that reconcile:33 must ignore (nudge, scout)
Nudge(w) == \* written while the run is open; ignored by reconcile:33
  /\ ~stopped /\ pc[w] = "running" /\ ~NUDGEIGNORED
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<pc, status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>
ScoutWarn(w) == \* spawn:642 "<id> scout changed files"; also ignored by :33
  /\ ~stopped /\ pc[w] \in {"running", "leaving"} /\ ~NUDGEIGNORED
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<pc, status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* spawn:511 isolation-violation, written after the worker ends and before :656
IsoWarn(w) ==
  /\ ~stopped /\ pc[w] = "leaving"
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<pc, status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* :656 the terminal row, :659 the status write: the order is the whole point
ExitRow(w) ==
  /\ ~stopped
  /\ \/ pc[w] = "leaving" /\ ROWORDER = "rowfirst"
     \/ pc[w] = "statusDone"
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = IF pc[w] = "leaving" THEN "rowDone" ELSE "finished"]
  /\ UNCHANGED <<status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>
WriteStatus(w) ==
  /\ ~stopped
  /\ \/ pc[w] = "leaving" /\ ROWORDER = "statusfirst"
     \/ pc[w] = "rowDone"
  /\ status' = [status EXCEPT ![w] = IF timedout[w] THEN "timeout" ELSE "done"]
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = IF pc[w] = "leaving" THEN "statusDone" ELSE "finished"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>
\* :657 write failed while the run is done: state is forced to failed, no row
FailExitRow(w) ==
  /\ ~stopped /\ pc[w] = "leaving"
  /\ status' = [status EXCEPT ![w] = "failed"]
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "finished"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* bin/ledger:176-196: an append; refuses a worker's own or a sibling id and checks a lead's base, no check that the run exited
\* EARLY="end": the parent accepts once the run's end is visible (row or status)
\* EARLY="any": it may accept a run that is still in flight or mid-exit
\* The parent accepts only on its own turn: while parked it is asleep and the host holds the turn.
Accept(w) ==
  /\ TurnOpen /\ nruns[w] > 0
  /\ \/ EARLY = "any" /\ pc[w] # "none"
     \/ EARLY = "end" /\ pc[w] \in {"rowDone", "statusDone", "killed", "finished", "crashed"}
  /\ accEx' = [accEx EXCEPT ![w] = TRUE]
  /\ accStart' = [accStart EXCEPT ![w] = TRUE]
  /\ ever' = [ever EXCEPT ![w] = TRUE]
  /\ reviewed' = [reviewed EXCEPT ![w] = TRUE]
  /\ UNCHANGED <<pc, status, alive, timedout,
                  nruns, blocks, stopped, failopen, parked, waiter>>

\* :19-30 the parent starts ONE waiter while work runs; tracked = the host lists
\* it in background_tasks, untracked = nohup/detached (never in that list)
StartWaiter(tracked) ==
  /\ TurnOpen
  /\ waiter = "none"
  /\ \E w \in W : Running(w)
  /\ waiter' = IF tracked THEN "tracked" ELSE "untracked"
  /\ UNCHANGED <<pc, status, alive, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen, parked>>

\* The waiter polls until nothing runs (reconcile:59-71). A tracked exit re-invokes
\* the parent (stop-gate:19-20,34), so the parked turn wakes; an untracked exit
\* cannot wake anyone and leaves the turn parked with any outstanding work.
WaiterExits ==
  /\ ~stopped /\ LiveWaiter
  /\ \A w \in W : ~Running(w)
  /\ waiter' = "none"
  /\ parked' = IF LiveTrackedWaiter THEN FALSE ELSE parked
  /\ UNCHANGED <<pc, status, alive, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>

\* bin/stop-gate:31-34,49-70: allow when nothing is outstanding (:32), else pass at
\* once on a live waiter (:34, counter and ledger untouched), else count and fail open
StopAttempt ==
  /\ TurnOpen
  /\ IF Outstanding = {} THEN stopped' = TRUE /\ parked' = FALSE /\ UNCHANGED <<blocks, failopen>>
     ELSE IF WaiterPass THEN parked' = TRUE /\ UNCHANGED <<stopped, blocks, failopen>>
     ELSE IF blocks < OPENAT THEN blocks' = blocks + 1 /\ UNCHANGED <<stopped, parked, failopen>>
     ELSE stopped' = TRUE /\ parked' = FALSE /\ failopen' = TRUE /\ UNCHANGED blocks
  /\ UNCHANGED <<pc, status, alive, accEx, accStart, ever, reviewed, timedout,
                  nruns, waiter>>

Done == stopped /\ UNCHANGED vars

Next == \/ \E w \in W : GuardPass(w) \/ StartRow(w) \/ WriteRunning(w) \/ WorkerExits(w)
               \/ TimeoutKill(w) \/ KillWorker(w) \/ KilledStatus(w) \/ Kill9(w)
               \/ Nudge(w) \/ ScoutWarn(w) \/ IsoWarn(w) \/ ExitRow(w)
               \/ WriteStatus(w) \/ FailExitRow(w) \/ Accept(w)
        \/ \E tracked \in BOOLEAN : StartWaiter(tracked)
        \/ WaiterExits \/ StopAttempt \/ Done
Spec == Init /\ [][Next]_vars

\* R1: the parent stops for good without fail-open only when every worker it spawned was accepted
\* (a pass on a live tracked waiter parks the turn instead; R6 guards that case)
StopNeedsAccept == (stopped /\ ~failopen) => \A w \in W : nruns[w] > 0 => (~Running(w) /\ ever[w])
\* R2: an accept that predates the latest start row never counts as accepted
StaleAcceptIgnored == \A w \in W : GateAccepted(w) => accStart[w]
\* R3: a finished worker whose latest run was accepted is not counted outstanding
NoFalseBlock == \A w \in W : (pc[w] = "finished" /\ reviewed[w] /\ ~Running(w)) => GateAccepted(w)
\* R4: fail-open happens only after the blocks are spent, and only with work outstanding
FailOpenAfterBlocks == failopen => (blocks = MAXBLOCKS /\ Outstanding # {})
\* R5: the parent cannot end its turn for good while a worker runs or its latest run is unaccepted;
\* the exception is a live tracked waiter, whose pass parks the turn and is guarded by R6
NoEndTurnWhileRunningOrUnaccepted ==
  (stopped /\ ~failopen) => \A w \in W : nruns[w] > 0 => (~Running(w) /\ accEx[w] /\ accStart[w])
\* R6: a stop that passes under a waiter is never final while work is outstanding: no state
\* where the turn is over, work is outstanding, no fail-open, and no live tracked waiter
WaiterWakesParent ==
  ((stopped \/ parked) /\ ~failopen /\ Outstanding # {}) => LiveTrackedWaiter
TypeOK == /\ pc \in [W -> Pcs] /\ status \in [W -> Statuses]
          /\ alive \in [W -> BOOLEAN] /\ timedout \in [W -> BOOLEAN]
          /\ accEx \in [W -> BOOLEAN] /\ accStart \in [W -> BOOLEAN]
          /\ ever \in [W -> BOOLEAN] /\ reviewed \in [W -> BOOLEAN] /\ nruns \in [W -> 0..MAXRUNS]
          /\ blocks \in 0..MAXBLOCKS
          /\ waiter \in Waiters /\ parked \in BOOLEAN

====
