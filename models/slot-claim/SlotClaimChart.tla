------------------------------ MODULE SlotClaimChart ------------------------------
\* Chart-only projection of SlotClaimTimed: 2 actors, and Init drops the
\* pre-lowering slot.
\* One model action = one command block a reviewer can open in bin/spawn.
\*
\* Promises, one sentence each:
\*  (I1) No two live spawners both believe they hold the same slot.
\*       INVARIANT NoDoubleHold
\*  (I2) When a claim returns success the number of live slots is at most CAP,
\*       including a CAP lowered while a higher-numbered slot is still live.
\*       INVARIANT HeldCap. (The stricter LiveCount <= Cap fails between the
\*       pid write and the recount; see README.md. That overshoot is bounded
\*       because every other claimer counts the dir and blocks.)
\*  (I3) A reclaimer never removes a slot whose owner is live (the pid fence).
\*       INVARIANT HoldersHaveSlot
\*
\* Code map (bin/spawn in this repo):
\*  slot_live      :301-308  LivePid + slotstart
\*  slot_lock      :310-320  AcquireRead (kept atomic; see exclusions)
\*  claim mkdir    :324      Mkdir
\*  claim lock     :326      AcquireRead for reclaim / the implicit lock in "made"
\*  write pid      :328      WritePid
\*  count others   :330-333  CountPass / CountBlocked
\*  write start    :334      WriteStart
\*  verify pid     :336      VerifyHold / VerifyFail
\*  stale read     :339-341  AcquireRead's seen
\*  fence mv       :343      FenceMove
\*  fence compare  :344-346  FenceRm / FenceRestore / FenceNothing
\*  release lock   :337,348  every next-state clears lock
\*  cleanup        :389      Release
\*  process death  : any kill  Die (runs no EXIT trap)
\* --------------------------------------------------------------------------
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS Actors, Other, NoPid, Cap

Procs   == Actors \cup {Other}
Scannable == 1..Cap          \* claim's while n <= CAP
HighSlot  == Cap + 1         \* a slot made before CAP was lowered; never scanned now
AllSlots  == 1..HighSlot

VARIABLES alive, holds, lock, slotdir, slotpid, slotstart, pc, stage, seen, fenced

vars == <<alive, holds, lock, slotdir, slotpid, slotstart, pc, stage, seen, fenced>>

\* slot_live: a live pid, or (after kill -9 of spawn) a live worker via wpid.
\* wpid and the ps lstart comparison are excluded; see README.md.
LivePid(p) == p \in Procs /\ alive[p]

\* A lock is free, or its owner is dead (slot_lock steals only from a dead owner).
CanLock(s) == lock[s] = NoPid \/ (lock[s] \in Procs /\ ~alive[lock[s]])

\* claim's live=... loop: other dirs that carry a live pid. Its own dir is skipped;
\* a dir with no pid is skipped (the code's [ -n "$pp" ] || continue).
LiveOthers(a) ==
  Cardinality({s \in AllSlots : s # pc[a] /\ slotdir[s] /\ slotpid[s] # NoPid /\ LivePid(slotpid[s])})
LiveCount ==
  Cardinality({s \in AllSlots : slotdir[s] /\ slotpid[s] # NoPid /\ LivePid(slotpid[s])})

\* --------------------------------------------------------------------------
\* Initial states: no deposit, a dead foreign owner of the high slot, or a live one.
InitBase ==
  /\ holds = [a \in Actors |-> 0]
  /\ lock  = [s \in AllSlots |-> NoPid]
  /\ stage = [a \in Actors |-> "try"]
  /\ pc    = [a \in Actors |-> 1]
  /\ seen  = [a \in Actors |-> 0]
  /\ fenced = [a \in Actors |-> 0]

InitNoHigh ==
  /\ slotdir  = [s \in AllSlots |-> FALSE]
  /\ slotpid  = [s \in AllSlots |-> NoPid]
  /\ slotstart = [s \in AllSlots |-> FALSE]
  /\ alive    = [p \in Procs |-> TRUE]

InitHighDead ==
  /\ slotdir  = [s \in AllSlots |-> s = HighSlot]
  /\ slotpid  = [s \in AllSlots |-> IF s = HighSlot THEN Other ELSE NoPid]
  /\ slotstart = [s \in AllSlots |-> s = HighSlot]
  /\ alive    = [p \in Procs |-> p # Other]

InitHighLive ==
  /\ slotdir  = [s \in AllSlots |-> s = HighSlot]
  /\ slotpid  = [s \in AllSlots |-> IF s = HighSlot THEN Other ELSE NoPid]
  /\ slotstart = [s \in AllSlots |-> s = HighSlot]
  /\ alive    = [p \in Procs |-> TRUE]

Init == InitBase /\ InitNoHigh

\* --------------------------------------------------------------------------
\* claim:324 mkdir succeeds; the actor now owns an empty dir (stage "made").
Mkdir(a) ==
  /\ alive[a] /\ stage[a] = "try" /\ ~slotdir[pc[a]]
  /\ slotdir'  = [slotdir EXCEPT ![pc[a]] = TRUE]
  /\ slotpid'  = [slotpid EXCEPT ![pc[a]] = NoPid]
  /\ slotstart' = [slotstart EXCEPT ![pc[a]] = FALSE]
  /\ stage'    = [stage EXCEPT ![a] = "made"]
  /\ UNCHANGED <<alive, holds, lock, pc, seen, fenced>>

\* claim:326 slot_lock (ln -s) after mkdir succeeded: take the lock.
TakeLock(a) ==
  /\ alive[a] /\ stage[a] = "made" /\ CanLock(pc[a])
  /\ lock' = [lock EXCEPT ![pc[a]] = a]
  /\ UNCHANGED <<alive, holds, slotdir, slotpid, slotstart, pc, stage, seen, fenced>>

\* claim:326 slot_lock success (ln -s) after mkdir failed: take the lock and
\* read the pid (the post-sleep read at :340).
AcquireRead(a) ==
  /\ alive[a] /\ stage[a] = "try" /\ slotdir[pc[a]] /\ slotpid[pc[a]] # NoPid /\ CanLock(pc[a])
  /\ lock' = [lock EXCEPT ![pc[a]] = a]
  /\ seen' = [seen EXCEPT ![a] = slotpid[pc[a]]]
  /\ stage' = [stage EXCEPT ![a] = "read"]
  /\ UNCHANGED <<alive, holds, slotdir, slotpid, slotstart, pc, fenced>>

\* claim:326 slot_lock fails because a live owner holds it: do nothing, n++.
Blocked(a) ==
  /\ alive[a] /\ stage[a] = "try" /\ slotdir[pc[a]] /\ ~CanLock(pc[a])
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ UNCHANGED <<alive, holds, lock, slotdir, slotpid, slotstart, pc, seen, fenced>>

\* claim:326 mkdir succeeded but slot_lock failed: rm the dir, n++.
AbandonMade(a) ==
  /\ alive[a] /\ stage[a] = "made" /\ lock[pc[a]] # a /\ ~CanLock(pc[a])
  /\ slotdir' = [slotdir EXCEPT ![pc[a]] = FALSE]
  /\ slotpid' = [slotpid EXCEPT ![pc[a]] = NoPid]
  /\ slotstart' = [slotstart EXCEPT ![pc[a]] = FALSE]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ UNCHANGED <<alive, holds, lock, pc, seen, fenced>>

\* n++ at :350, or the outer `until claim` retry at :393 (the sleep 1 is excluded).
Advance(a) ==
  /\ alive[a] /\ stage[a] = "wait"
  /\ pc' = [pc EXCEPT ![a] = IF pc[a] < Cap THEN pc[a] + 1 ELSE 1]
  /\ stage' = [stage EXCEPT ![a] = "try"]
  /\ UNCHANGED <<alive, holds, lock, slotdir, slotpid, slotstart, seen, fenced>>

\* claim:328 echo $$ > pid (only while holding the lock).
WritePid(a) ==
  /\ alive[a] /\ stage[a] = "made" /\ lock[pc[a]] = a /\ slotdir[pc[a]]
  /\ slotpid' = [slotpid EXCEPT ![pc[a]] = a]
  /\ stage' = [stage EXCEPT ![a] = "wrote"]
  /\ UNCHANGED <<alive, holds, lock, slotdir, slotstart, pc, seen, fenced>>

\* claim:328 the pid write failed because the dir was reclaimed first:
\* rm the dir (no-op), drop the lock, n++.
WriteFail(a) ==
  /\ alive[a] /\ stage[a] = "made" /\ lock[pc[a]] = a /\ ~slotdir[pc[a]]
  /\ slotdir' = [slotdir EXCEPT ![pc[a]] = FALSE]
  /\ slotpid' = [slotpid EXCEPT ![pc[a]] = NoPid]
  /\ slotstart' = [slotstart EXCEPT ![pc[a]] = FALSE]
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ UNCHANGED <<alive, holds, pc, seen, fenced>>

\* claim:330-332 count live others; CAP not reached -> continue.
CountPass(a) ==
  /\ alive[a] /\ stage[a] = "wrote" /\ LiveOthers(a) < Cap
  /\ stage' = [stage EXCEPT ![a] = "counted"]
  /\ UNCHANGED <<alive, holds, lock, slotdir, slotpid, slotstart, pc, seen, fenced>>

\* claim:333 live >= CAP -> rm -rf the fresh dir, drop the lock, n++.
CountBlocked(a) ==
  /\ alive[a] /\ stage[a] = "wrote" /\ LiveOthers(a) >= Cap
  /\ slotdir' = [slotdir EXCEPT ![pc[a]] = FALSE]
  /\ slotpid' = [slotpid EXCEPT ![pc[a]] = NoPid]
  /\ slotstart' = [slotstart EXCEPT ![pc[a]] = FALSE]
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ UNCHANGED <<alive, holds, pc, seen, fenced>>

\* claim:334 write the start time.
WriteStart(a) ==
  /\ alive[a] /\ stage[a] = "counted"
  /\ slotstart' = [slotstart EXCEPT ![pc[a]] = TRUE]
  /\ stage' = [stage EXCEPT ![a] = "started"]
  /\ UNCHANGED <<alive, holds, lock, slotdir, slotpid, pc, seen, fenced>>

\* claim:336 the pid still names us: this slot is ours.
VerifyHold(a) ==
  /\ alive[a] /\ stage[a] = "started" /\ slotpid[pc[a]] = a
  /\ holds' = [holds EXCEPT ![a] = pc[a]]
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "holding"]
  /\ UNCHANGED <<alive, slotdir, slotpid, slotstart, pc, seen, fenced>>

\* claim:336 the pid no longer names us: n++ and leave the dir as it stands.
VerifyFail(a) ==
  /\ alive[a] /\ stage[a] = "started" /\ slotpid[pc[a]] # a
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ UNCHANGED <<alive, holds, slotdir, slotpid, slotstart, pc, seen, fenced>>

\* cleanup:389 rm -rf "$slot" (no lock).
Release(a) ==
  /\ alive[a] /\ stage[a] = "holding"
  /\ slotdir' = [slotdir EXCEPT ![holds[a]] = FALSE]
  /\ slotpid' = [slotpid EXCEPT ![holds[a]] = NoPid]
  /\ slotstart' = [slotstart EXCEPT ![holds[a]] = FALSE]
  /\ holds' = [holds EXCEPT ![a] = 0]
  /\ stage' = [stage EXCEPT ![a] = "done"]
  /\ UNCHANGED <<alive, lock, pc, seen, fenced>>

\* A process dies at any step: no trap, dir and lock stay behind.
Die(a) ==
  /\ alive[a]
  /\ alive' = [alive EXCEPT ![a] = FALSE]
  /\ UNCHANGED <<holds, lock, slotdir, slotpid, slotstart, pc, stage, seen, fenced>>

\* slot_live :339-341: the read pid is empty or dead -> move the fence.
SeenDeadOrEmpty(a) ==
  seen[a] = NoPid \/ (seen[a] \in Procs /\ ~alive[seen[a]])

\* claim:343 mv pid pid.reap.$$ (the fence), then compare its content.
FenceMove(a) ==
  /\ alive[a] /\ stage[a] = "read" /\ SeenDeadOrEmpty(a)
  /\ fenced' = [fenced EXCEPT ![a] = slotpid[pc[a]]]
  /\ slotpid' = [slotpid EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "fenced"]
  /\ UNCHANGED <<alive, holds, lock, slotdir, slotstart, pc, seen>>

\* claim:344 content == p: rm -rf the slot, drop the lock, n++.
FenceRm(a) ==
  /\ alive[a] /\ stage[a] = "fenced" /\ fenced[a] = seen[a]
  /\ slotdir' = [slotdir EXCEPT ![pc[a]] = FALSE]
  /\ slotpid' = [slotpid EXCEPT ![pc[a]] = NoPid]
  /\ slotstart' = [slotstart EXCEPT ![pc[a]] = FALSE]
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ fenced' = [fenced EXCEPT ![a] = NoPid]
  /\ UNCHANGED <<alive, holds, pc, seen>>

\* claim:345 content != p and a pid was moved: put it back.
FenceRestore(a) ==
  /\ alive[a] /\ stage[a] = "fenced" /\ fenced[a] # seen[a] /\ fenced[a] \in Procs
  /\ slotpid' = [slotpid EXCEPT ![pc[a]] = fenced[a]]
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ fenced' = [fenced EXCEPT ![a] = NoPid]
  /\ UNCHANGED <<alive, holds, slotdir, slotstart, pc, seen>>

\* claim:345 content != p and nothing was moved: leave the dir, drop the lock, n++.
FenceNothing(a) ==
  /\ alive[a] /\ stage[a] = "fenced" /\ fenced[a] # seen[a] /\ fenced[a] = NoPid
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ fenced' = [fenced EXCEPT ![a] = NoPid]
  /\ UNCHANGED <<alive, holds, slotdir, slotpid, slotstart, pc, seen>>

\* slot_live :339-341 says live: no fence, drop the lock, n++.
ReclaimAbort(a) ==
  /\ alive[a] /\ stage[a] = "read" /\ seen[a] \in Procs /\ alive[seen[a]]
  /\ lock' = [lock EXCEPT ![pc[a]] = NoPid]
  /\ stage' = [stage EXCEPT ![a] = "wait"]
  /\ UNCHANGED <<alive, holds, slotdir, slotpid, slotstart, pc, seen, fenced>>

Next ==
  \/ \E a \in Actors :
       \/ Mkdir(a) \/ TakeLock(a) \/ AcquireRead(a) \/ Blocked(a) \/ AbandonMade(a) \/ Advance(a)
       \/ WritePid(a) \/ WriteFail(a) \/ CountPass(a) \/ CountBlocked(a) \/ WriteStart(a)
       \/ VerifyHold(a) \/ VerifyFail(a) \/ Release(a) \/ Die(a)
       \/ FenceMove(a) \/ FenceRm(a) \/ FenceRestore(a) \/ FenceNothing(a)
       \/ ReclaimAbort(a)

Spec == Init /\ [][Next]_vars

\* --------------------------------------------------------------------------
NoDoubleHold ==
  \A a, b \in Actors :
    a # b /\ alive[a] /\ alive[b] /\ holds[a] # 0 => holds[a] # holds[b]

\* Strict "the live-dir count never exceeds CAP at any instant": false between
\* :328 (pid write) and :333 (recount) whenever the spare slot is already live.
\* Kept for the exploratory config; the promise is about a returned claim.
LiveCap == LiveCount <= Cap

\* Slots that a successful claim believes it holds, plus the pre-lowering slot.
HeldSlots ==
  {s \in AllSlots :
     (\E a \in Actors : alive[a] /\ holds[a] = s)
     \/ (s = HighSlot /\ slotdir[s] /\ slotpid[s] \in Procs /\ alive[slotpid[s]])}
HeldCap == Cardinality(HeldSlots) <= Cap

\* A live holder still owns its dir. While a reclaimer's fence file holds the
\* pid (mv at :343, not yet restored at :345) the dir has no pid file, so the
\* pid may sit in that actor's fence instead. A removal or overwrite fails.
HoldersHaveSlot ==
  \A a \in Actors :
    alive[a] /\ holds[a] # 0 =>
      /\ slotdir[holds[a]]
      /\ (slotpid[holds[a]] = a \/ (\E b \in Actors : fenced[b] = a))
==============================================================================
