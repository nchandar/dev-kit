---- MODULE StopGate ----
\* Stop-gate accept protocol, re-synced to HEAD (65810a9).
\* Code: bin/stop-gate:13-27 (counter, fail-open),
\*   bin/reconcile:23-33 (gate_task: :30 running check, :33 ac>ex over spawn rows
\*   except nudge/scout), bin/spawn:275 (status guard), :397-407 claim_id (atomic
\*   same-id claim), :478 (start row), :481 (status running), :623-630 timeout guard,
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
          EARLY         \* "any" = a parent may accept before the exit row exists; "end" = only at a terminal pc

VARIABLES pc, status, alive, accEx, accStart, ever, reviewed, timedout,
          nruns, blocks, stopped, failopen
vars == <<pc, status, alive, accEx, accStart, ever, reviewed, timedout,
          nruns, blocks, stopped, failopen>>

\* pc: none | guarded (passed :275, before :478) | started (:478, before :481)
\*     | running | leaving (worker done, before :656) | rowDone (:656, before :659)
\*     | statusDone (:659 before the row, only in "statusfirst") | killed (:431, before :437)
\*     | finished | crashed (kill -9: no row, no status write)
Statuses == {"none", "running", "done", "failed", "timeout", "killed"}
Pcs == {"none", "guarded", "started", "running", "leaving", "rowDone",
         "statusDone", "killed", "finished", "crashed"}

Init == /\ pc = [w \in W |-> "none"] /\ status = [w \in W |-> "none"]
        /\ alive = [w \in W |-> FALSE]
        /\ accEx = [w \in W |-> FALSE] /\ accStart = [w \in W |-> FALSE]
        /\ ever = [w \in W |-> FALSE] /\ reviewed = [w \in W |-> FALSE]
        /\ timedout = [w \in W |-> FALSE]
        /\ nruns = [w \in W |-> 0] /\ blocks = 0
        /\ stopped = FALSE /\ failopen = FALSE

\* --- the gate's own view (bin/reconcile:23-33) ----------------------------
Running(w) == status[w] = "running" /\ alive[w]   \* reconcile:30 kill -0
Accepted(w) == IF NEWERROW THEN accEx[w] ELSE ever[w]
GateAccepted(w) == GATE_ACCEPTS /\ ~(RUNCHECK /\ Running(w)) /\ Accepted(w)
Outstanding == {w \in W : pc[w] # "none" /\ ~GateAccepted(w)}

\* --- spawn, one code step per action -------------------------------------
\* :275 status guard; claim_id :397-407 adds the atomic same-id claim; run from none, finished or crashed
GuardPass(w) ==
  /\ ~stopped
  /\ nruns[w] < MAXRUNS
  /\ \/ pc[w] \in {"none", "finished", "crashed"}   \* :275 lets these through
     \/ ~GUARD_STATUS /\ pc[w] \in {"leaving", "rowDone", "statusDone", "killed"} \* break: respawn mid-exit
  /\ pc' = [pc EXCEPT ![w] = "guarded"]
  /\ UNCHANGED <<status, alive, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>

\* :478 the start row, "<id> running": a respawn is unreviewed from here on
StartRow(w) ==
  /\ ~stopped /\ pc[w] = "guarded"
  /\ accEx' = [accEx EXCEPT ![w] = IF STARTROW THEN FALSE ELSE accEx[w]]
  /\ accStart' = [accStart EXCEPT ![w] = FALSE]   \* the start row is always newer than any accept
  /\ reviewed' = [reviewed EXCEPT ![w] = FALSE]
  /\ nruns' = [nruns EXCEPT ![w] = nruns[w] + 1]
  /\ pc' = [pc EXCEPT ![w] = "started"]
  /\ UNCHANGED <<status, alive, ever, timedout, blocks, stopped, failopen>>

\* :481 status "running $$" (and the old handoff and timeout marker are removed)
WriteRunning(w) ==
  /\ ~stopped /\ pc[w] = "started"
  /\ status' = [status EXCEPT ![w] = "running"]
  /\ alive' = [alive EXCEPT ![w] = TRUE]
  /\ timedout' = [timedout EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "running"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, nruns, blocks, stopped, failopen>>

\* the worker ends on its own, or the DEVKIT_TIMEOUT guard kills it (:623-630)
WorkerExits(w) ==
  /\ ~stopped /\ pc[w] = "running"
  /\ pc' = [pc EXCEPT ![w] = "leaving"]
  /\ UNCHANGED <<status, alive, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>
TimeoutKill(w) ==
  /\ ~stopped /\ pc[w] = "running"
  /\ timedout' = [timedout EXCEPT ![w] = TRUE]
  /\ pc' = [pc EXCEPT ![w] = "leaving"]
  /\ UNCHANGED <<status, alive, accEx, accStart, ever, reviewed,
                  nruns, blocks, stopped, failopen>>

\* :431-437 a signal or an interrupted run: killed row, then status "killed"
KillWorker(w) ==
  /\ ~stopped /\ pc[w] = "running"
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "killed"]
  /\ UNCHANGED <<status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>
KilledStatus(w) ==
  /\ ~stopped /\ pc[w] = "killed"
  /\ status' = [status EXCEPT ![w] = "killed"]
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "finished"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>

\* kill -9 of spawn: no row, no status write; the pid in the status file is dead
Kill9(w) ==
  /\ ~stopped /\ pc[w] \in {"guarded", "started", "running", "leaving", "rowDone", "statusDone"}
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "crashed"]
  /\ UNCHANGED <<status, accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>

\* rows written while the run is open that reconcile:33 must ignore (nudge, scout)
Nudge(w) == \* written while the run is open; ignored by reconcile:33
  /\ ~stopped /\ pc[w] = "running" /\ ~NUDGEIGNORED
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<pc, status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>
ScoutWarn(w) == \* spawn:642 "<id> scout changed files"; also ignored by :33
  /\ ~stopped /\ pc[w] \in {"running", "leaving"} /\ ~NUDGEIGNORED
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<pc, status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>

\* spawn:511 isolation-violation, written after the worker ends and before :656
IsoWarn(w) ==
  /\ ~stopped /\ pc[w] = "leaving"
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<pc, status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>

\* :656 the terminal row, :659 the status write: the order is the whole point
ExitRow(w) ==
  /\ ~stopped
  /\ \/ pc[w] = "leaving" /\ ROWORDER = "rowfirst"
     \/ pc[w] = "statusDone"
  /\ accEx' = [accEx EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = IF pc[w] = "leaving" THEN "rowDone" ELSE "finished"]
  /\ UNCHANGED <<status, alive, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>
WriteStatus(w) ==
  /\ ~stopped
  /\ \/ pc[w] = "leaving" /\ ROWORDER = "statusfirst"
     \/ pc[w] = "rowDone"
  /\ status' = [status EXCEPT ![w] = IF timedout[w] THEN "timeout" ELSE "done"]
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = IF pc[w] = "leaving" THEN "statusDone" ELSE "finished"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>
\* :657 write failed while the run is done: state is forced to failed, no row
FailExitRow(w) ==
  /\ ~stopped /\ pc[w] = "leaving"
  /\ status' = [status EXCEPT ![w] = "failed"]
  /\ alive' = [alive EXCEPT ![w] = FALSE]
  /\ pc' = [pc EXCEPT ![w] = "finished"]
  /\ UNCHANGED <<accEx, accStart, ever, reviewed, timedout,
                  nruns, blocks, stopped, failopen>>

\* bin/ledger:176-196: an append; refuses a worker's own or a sibling id and checks a lead's base, no check that the run exited
\* EARLY="end": the parent accepts once the run's end is visible (row or status)
\* EARLY="any": it may accept a run that is still in flight or mid-exit
Accept(w) ==
  /\ ~stopped /\ nruns[w] > 0
  /\ \/ EARLY = "any" /\ pc[w] # "none"
     \/ EARLY = "end" /\ pc[w] \in {"rowDone", "statusDone", "killed", "finished", "crashed"}
  /\ accEx' = [accEx EXCEPT ![w] = TRUE]
  /\ accStart' = [accStart EXCEPT ![w] = TRUE]
  /\ ever' = [ever EXCEPT ![w] = TRUE]
  /\ reviewed' = [reviewed EXCEPT ![w] = TRUE]
  /\ UNCHANGED <<pc, status, alive, timedout,
                  nruns, blocks, stopped, failopen>>

\* bin/stop-gate:13-27: allow when nothing is outstanding, else count and fail open
StopAttempt ==
  /\ ~stopped
  /\ IF Outstanding = {} THEN stopped' = TRUE /\ UNCHANGED <<blocks, failopen>>
     ELSE IF blocks < OPENAT THEN blocks' = blocks + 1 /\ UNCHANGED <<stopped, failopen>>
     ELSE stopped' = TRUE /\ failopen' = TRUE /\ UNCHANGED blocks
  /\ UNCHANGED <<pc, status, alive, accEx, accStart, ever, reviewed, timedout, nruns>>

Done == stopped /\ UNCHANGED vars

Next == \/ \E w \in W : GuardPass(w) \/ StartRow(w) \/ WriteRunning(w) \/ WorkerExits(w)
               \/ TimeoutKill(w) \/ KillWorker(w) \/ KilledStatus(w) \/ Kill9(w)
               \/ Nudge(w) \/ ScoutWarn(w) \/ IsoWarn(w) \/ ExitRow(w)
               \/ WriteStatus(w) \/ FailExitRow(w) \/ Accept(w)
        \/ StopAttempt \/ Done
Spec == Init /\ [][Next]_vars

\* R1: the parent stops without fail-open only when every worker it spawned was accepted
StopNeedsAccept == (stopped /\ ~failopen) => \A w \in W : nruns[w] > 0 => (~Running(w) /\ ever[w])
\* R2: an accept that predates the latest start row never counts as accepted
StaleAcceptIgnored == \A w \in W : GateAccepted(w) => accStart[w]
\* R3: a finished worker whose latest run was accepted is not counted outstanding
NoFalseBlock == \A w \in W : (pc[w] = "finished" /\ reviewed[w] /\ ~Running(w)) => GateAccepted(w)
\* R4: fail-open happens only after the blocks are spent, and only with work outstanding
FailOpenAfterBlocks == failopen => (blocks = MAXBLOCKS /\ Outstanding # {})
\* R5: the parent cannot end its turn while a worker runs or its latest run is unaccepted
NoEndTurnWhileRunningOrUnaccepted ==
  (stopped /\ ~failopen) => \A w \in W : nruns[w] > 0 => (~Running(w) /\ accEx[w] /\ accStart[w])
TypeOK == /\ pc \in [W -> Pcs] /\ status \in [W -> Statuses]
          /\ alive \in [W -> BOOLEAN] /\ timedout \in [W -> BOOLEAN]
          /\ accEx \in [W -> BOOLEAN] /\ accStart \in [W -> BOOLEAN]
          /\ ever \in [W -> BOOLEAN] /\ reviewed \in [W -> BOOLEAN] /\ nruns \in [W -> 0..MAXRUNS]
          /\ blocks \in 0..MAXBLOCKS

====
