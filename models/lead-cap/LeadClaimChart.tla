----------------------------- MODULE LeadClaimChart ---------------------------
\* A model of bin/spawn claim_lead at HEAD (65810a9, :305-327), its caller's
\* refusal paths (:328-336) and cleanup (:449).
\*
\* Promises, one sentence each:
\*  (I1) At most MAX accepted lead places are live at any instant.
\*       INVARIANT LeadsBounded. A claimant's candidate is a live dir from
\*       publish (:313) to its decision (:325), so another counter sees it and
\*       blocks: a safe over-block, never an extra place.
\*  (I2) A live claimant keeps its candidate dir from mkdir until it accepts
\*       or is refused, and a live accepted lead keeps its claim dir.
\*       INVARIANTS NoLostCandidate, NoLostLeadPlace.
\*  (I3) The cap count counts live claims only, never a stale dir.
\*       INVARIANT CountsOnlyLive.
\*  (I4) A dead claim, or a lock left by a dead spawner, never blocks new
\*       leads forever (under fair scheduling and no new deaths).
\*       PROPERTIES StaleClaimReclaimed, DeadLockStolen on FairSpec.
\*  (I5) Under fair scheduling a refused candidate is removed under the lock,
\*       so a live claimant is never refused while no accepted place is live.
\*       PROPERTY Progress on FairSpec.
\*
\* Code map (bin/spawn at 65810a9):
\*  slot_live        :280-288  LiveDir (wpid + ps lstart excluded, see README)
\*  slot_lock        :289-299  LeadClaimStart (one atomic take/steal)
\*  same-id read     :311-312  LeadSameIdRefuse
\*  rm -rf; mkdir    :313      LeadPublish
\*  start + pid      :315-316  LeadWritePid / LeadPublishFail
\*  count live others:317-321  LeadCountOthers (also rm -rf of dead dirs)
\*  verify own pid   :322      LeadVerifyOwn / LeadVerifyFail
\*  nlead < MAX      :325      LeadAccept (under the lock)
\*  nlead >= MAX     :325      LeadRefuse (rm -rf then unlock, under the lock)
\*  rm -f lock       :326      the unlock after a successful cap test
\*  cleanup          :449      LeadRelease
\*  process death    : any kill  Die (no EXIT trap after kill -9)
\* --------------------------------------------------------------------------
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS Actors, Other, NoPid, Max

Procs == Actors \cup {Other}
Claiming == {"made", "published", "counted", "verified"}

VARIABLES alive, leaddir, leadpid, lock, stage, nlead, holds

vars == <<alive, leaddir, leadpid, lock, stage, nlead, holds>>

\* slot_live: a dir is live iff its pid answers. A missing start file still
\* counts as live (:283); the ps lstart reuse check is excluded (README).
LiveDir(p) == leaddir[p] /\ leadpid[p] \in Procs /\ alive[leadpid[p]]

LiveOthers(a) == Cardinality({p \in Procs : p # a /\ LiveDir(p)})

\* slot_lock steals only from a dead owner (reused pids are excluded).
CanLock == lock = NoPid \/ (lock \in Procs /\ ~alive[lock])

\* One sample of "no other live accepted place" for the liveness promise.
NoLiveHold == \A p \in Procs : ~(p \in holds /\ alive[p])

\* --------------------------------------------------------------------------
InitBase ==
  /\ stage = [a \in Actors |-> "try"]
  /\ nlead = [a \in Actors |-> 0]

InitNoLead ==
  /\ leaddir = [p \in Procs |-> FALSE]
  /\ leadpid = [p \in Procs |-> NoPid]
  /\ holds   = {}
  /\ alive   = [p \in Procs |-> TRUE]
  /\ lock    = NoPid

\* a live lead already holds one place (the cap is partly used)
InitOtherLive ==
  /\ leaddir = [p \in Procs |-> p = Other]
  /\ leadpid = [p \in Procs |-> IF p = Other THEN Other ELSE NoPid]
  /\ holds   = {Other}
  /\ alive   = [p \in Procs |-> TRUE]
  /\ lock    = NoPid

\* a lead died without cleanup: its claim dir is stale
InitOtherDead ==
  /\ leaddir = [p \in Procs |-> p = Other]
  /\ leadpid = [p \in Procs |-> IF p = Other THEN Other ELSE NoPid]
  /\ holds   = {}
  /\ alive   = [p \in Procs |-> p # Other]
  /\ lock    = NoPid

\* a spawner died holding the repo-wide lock
InitDeadLock ==
  /\ leaddir = [p \in Procs |-> FALSE]
  /\ leadpid = [p \in Procs |-> NoPid]
  /\ holds   = {}
  /\ alive   = [p \in Procs |-> p # Other]
  /\ lock    = Other

Init == InitBase /\ InitNoLead

\* --------------------------------------------------------------------------
\* :307 until slot_lock "$l": take the repo-wide lock, or steal it from a dead owner.
LeadClaimStart(a) ==
  /\ alive[a] /\ stage[a] = "try" /\ CanLock
  /\ lock' = a
  /\ stage' = [stage EXCEPT ![a] = "locked"]
  /\ UNCHANGED <<alive, leaddir, leadpid, nlead, holds>>

\* :311-312 the same id already has a live claim: release the lock, return 3 (exit 2).
LeadSameIdRefuse(a) ==
  /\ alive[a] /\ stage[a] = "locked" /\ LiveDir(a)
  /\ lock' = NoPid
  /\ stage' = [stage EXCEPT ![a] = "refused"]
  /\ UNCHANGED <<alive, leaddir, leadpid, nlead, holds>>

\* :313 rm -rf a stale same-id dir, then mkdir it: the dir exists with no pid yet.
LeadPublish(a) ==
  /\ alive[a] /\ stage[a] = "locked" /\ ~LiveDir(a)
  /\ leaddir' = [leaddir EXCEPT ![a] = TRUE]
  /\ leadpid' = [leadpid EXCEPT ![a] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "made"]
  /\ UNCHANGED <<alive, lock, nlead, holds>>

\* :315-316 write start and pid: the claim is now live.
LeadWritePid(a) ==
  /\ alive[a] /\ stage[a] = "made" /\ leaddir[a]
  /\ leadpid' = [leadpid EXCEPT ![a] = a]
  /\ stage' = [stage EXCEPT ![a] = "published"]
  /\ UNCHANGED <<alive, leaddir, lock, nlead, holds>>

\* :313 mkdir failed, or :316 the pid write landed on a removed dir: return 1 (exit 4).
LeadPublishFail(a) ==
  /\ alive[a] /\ stage[a] = "made" /\ ~leaddir[a]
  /\ leaddir' = [leaddir EXCEPT ![a] = FALSE]
  /\ leadpid' = [leadpid EXCEPT ![a] = NoPid]
  /\ lock' = NoPid
  /\ stage' = [stage EXCEPT ![a] = "failed"]
  /\ UNCHANGED <<alive, nlead, holds>>

\* :317-321 count live others; every other dir with a dead or empty pid is rm -rf'd.
\* The loop is one command block and runs under the lock, so it is one step here.
LeadCountOthers(a) ==
  /\ alive[a] /\ stage[a] = "published" /\ lock = a
  /\ nlead' = [nlead EXCEPT ![a] = LiveOthers(a)]
  /\ leaddir' = [p \in Procs |-> IF p = a \/ LiveDir(p) THEN leaddir[p] ELSE FALSE]
  /\ leadpid' = [p \in Procs |-> IF p = a \/ LiveDir(p) THEN leadpid[p] ELSE NoPid]
  /\ stage' = [stage EXCEPT ![a] = "counted"]
  /\ UNCHANGED <<alive, lock, holds>>

\* :322 the pid still names us: the claim is ours.
LeadVerifyOwn(a) ==
  /\ alive[a] /\ stage[a] = "counted" /\ leadpid[a] = a
  /\ stage' = [stage EXCEPT ![a] = "verified"]
  /\ UNCHANGED <<alive, leaddir, leadpid, lock, nlead, holds>>

\* :322 the pid does not name us (the dir was lost): rm -rf, unlock, return 1.
LeadVerifyFail(a) ==
  /\ alive[a] /\ stage[a] = "counted" /\ leadpid[a] # a
  /\ leaddir' = [leaddir EXCEPT ![a] = FALSE]
  /\ leadpid' = [leadpid EXCEPT ![a] = NoPid]
  /\ lock' = NoPid
  /\ stage' = [stage EXCEPT ![a] = "failed"]
  /\ UNCHANGED <<alive, nlead, holds>>

\* Fixed order: the cap test runs under the lock, and a refusal removes the
\* candidate before the unlock, so no next claimant can count it.
\* :324-325 nlead < MAX: the place is ours until cleanup; then release the lock.
LeadAccept(a) ==
  /\ alive[a] /\ stage[a] = "verified" /\ lock = a /\ nlead[a] < Max
  /\ holds' = holds \cup {a}
  /\ lock' = NoPid
  /\ stage' = [stage EXCEPT ![a] = "holding"]
  /\ UNCHANGED <<alive, leaddir, leadpid, nlead>>

\* :324 nlead >= MAX: rm -rf the candidate, release the lock, return 2 (exit 4).
LeadRefuse(a) ==
  /\ alive[a] /\ stage[a] = "verified" /\ lock = a /\ nlead[a] >= Max
  /\ leaddir' = [leaddir EXCEPT ![a] = FALSE]
  /\ leadpid' = [leadpid EXCEPT ![a] = NoPid]
  /\ lock' = NoPid
  /\ stage' = [stage EXCEPT ![a] = "refused"]
  /\ UNCHANGED <<alive, nlead, holds>>

\* :447 cleanup: remove only a claim this spawn owns.
LeadRelease(a) ==
  /\ alive[a] /\ stage[a] = "holding"
  /\ leaddir' = [leaddir EXCEPT ![a] = FALSE]
  /\ leadpid' = [leadpid EXCEPT ![a] = NoPid]
  /\ holds' = holds \ {a}
  /\ stage' = [stage EXCEPT ![a] = "done"]
  /\ UNCHANGED <<alive, lock, nlead>>

\* any kill: kill -9 runs no EXIT trap, the dir and the lock stay behind.
Die(a) ==
  /\ alive[a]
  /\ alive' = [alive EXCEPT ![a] = FALSE]
  /\ UNCHANGED <<leaddir, leadpid, lock, stage, nlead, holds>>

\* --------------------------------------------------------------------------
ActorStep(a) ==
  \/ LeadClaimStart(a) \/ LeadSameIdRefuse(a) \/ LeadPublish(a) \/ LeadWritePid(a)
  \/ LeadPublishFail(a) \/ LeadCountOthers(a) \/ LeadVerifyOwn(a) \/ LeadVerifyFail(a)
  \/ LeadAccept(a) \/ LeadRefuse(a) \/ LeadRelease(a)

NoDieNext == \E a \in Actors : ActorStep(a)

Next == NoDieNext

Spec == Init /\ [][Next]_vars

\* FairSpec states the liveness assumption: no actor dies, and every actor that
\* can take a step takes one infinitely often. Die is checked in Spec only.
FairSpec == Init /\ [][NoDieNext]_vars /\ (\A a \in Actors : WF_vars(ActorStep(a)))

\* --------------------------------------------------------------------------
LiveAccepted == {p \in Procs : p \in holds /\ alive[p]}

LeadsBounded == Cardinality(LiveAccepted) <= Max

\* A live claimant keeps its candidate dir from mkdir through the cap test.
NoLostCandidate ==
  \A a \in Actors : alive[a] /\ stage[a] \in Claiming => leaddir[a]

\* A live accepted lead keeps its claim dir, and the pid names it.
NoLostLeadPlace ==
  \A a \in Actors : alive[a] /\ a \in holds => leaddir[a] /\ leadpid[a] = a

\* The count counts live others only, never a stale dir.
CountsOnlyLive ==
  \A a \in Actors : stage[a] = "counted" => nlead[a] = LiveOthers(a)

\* Under FairSpec a stale claim dir is eventually removed by a count.
StaleClaimReclaimed ==
  \A p \in Procs :
    (leaddir[p] /\ leadpid[p] \in Procs /\ ~alive[leadpid[p]]) ~> ~leaddir[p]

\* Under FairSpec a lock left by a dead spawner is eventually taken and released.
DeadLockStolen ==
  (lock \in Procs /\ ~alive[lock]) ~> (lock = NoPid)

\* Progress: if a lead is trying and no live accepted place exists, some lead
\* is eventually accepted. FALSE on the old order (unlock at :323 before the
\* test at :324, candidate alive until :330). This scratch copy puts the cap
\* test and a refusal's removal under the lock (the f6 fix), so it passes.
\* See README "Spurious refusal" and LeadClaim-progress-cap1.log.
Progress ==
  (\E a \in Actors : alive[a] /\ stage[a] = "try")
    ~> (\E p \in Procs : p \in holds)
=============================================================================
