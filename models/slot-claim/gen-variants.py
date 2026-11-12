#!/usr/bin/env python3
"""Generate the timing variant and the broken variants from SlotClaim.tla.

Each break is a precondition swap, never a new step; the module name follows
the file name, as TLA+ requires. Run from anywhere: paths resolve from this
file."""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
BASE = (HERE / "SlotClaim.tla").read_text()
BASE_HEAD = (
    "\\* A model of bin/spawn at ee31498^ (the pre-fix order: mkdir, then the lock,\n"
    "\\* then the pid). Kept as the counterexample the live replay reproduces; the\n"
    "\\* current code is modelled by SlotClaimLockFirst.tla."
)
if BASE_HEAD not in BASE:
    sys.exit("SlotClaim.tla: base header line moved; update BASE_HEAD")


def write(name, why, pairs):
    s = BASE.replace("MODULE SlotClaim ---", "MODULE %s ---" % name)
    s = s.replace(BASE_HEAD, "\\* %s" % why)
    for old, new in pairs:
        if old not in s:
            sys.exit("%s: patch target missing:\n%s" % (name, old))
        s = s.replace(old, new)
    (HERE / (name + ".tla")).write_text(s)


# The intended timing of the pre-fix model: the 1s grace at :340 holds, so a
# dir without a pid yet (a live claimant between mkdir and its pid write) is
# never reclaimed.
write("SlotClaimTimed", "Timing variant of the pre-fix model: the 1s grace at :340 holds, so a dir with no pid is never reclaimed.", [
    ('''  /\\ alive[a] /\\ stage[a] = "try" /\\ slotdir[pc[a]] /\\ CanLock(pc[a])''',
     '''  /\\ alive[a] /\\ stage[a] = "try" /\\ slotdir[pc[a]] /\\ slotpid[pc[a]] # NoPid /\\ CanLock(pc[a])'''),
])

write("SlotClaimNoFence", "BROKEN VARIANT: reclaimer removes unconditionally, no pid-fence compare.", [
    ('''  /\\ alive[a] /\\ stage[a] = "fenced" /\\ fenced[a] = seen[a]''',
     '''  /\\ alive[a] /\\ stage[a] = "fenced" /\\ TRUE  \\* fence compare removed'''),
    ('''  /\\ alive[a] /\\ stage[a] = "fenced" /\\ fenced[a] # seen[a] /\\ fenced[a] \\in Procs''',
     '''  /\\ alive[a] /\\ stage[a] = "fenced" /\\ FALSE'''),
    ('''  /\\ alive[a] /\\ stage[a] = "fenced" /\\ fenced[a] # seen[a] /\\ fenced[a] = NoPid''',
     '''  /\\ alive[a] /\\ stage[a] = "fenced" /\\ FALSE'''),
])

write("SlotClaimNoLock", "BROKEN VARIANT: claim writes its pid without taking the per-slot lock.", [
    ('''  /\\ alive[a] /\\ stage[a] = "made" /\\ CanLock(pc[a])''',
     '''  /\\ alive[a] /\\ stage[a] = "made" /\\ FALSE  \\* slot_lock removed from claim'''),
    ('''  /\\ alive[a] /\\ stage[a] = "made" /\\ lock[pc[a]] = a /\\ slotdir[pc[a]]''',
     '''  /\\ alive[a] /\\ stage[a] = "made" /\\ slotdir[pc[a]]  \\* no claim lock'''),
    ('''  /\\ alive[a] /\\ stage[a] = "made" /\\ lock[pc[a]] = a /\\ ~slotdir[pc[a]]''',
     '''  /\\ alive[a] /\\ stage[a] = "made" /\\ ~slotdir[pc[a]]'''),
    ('''  /\\ alive[a] /\\ stage[a] = "made" /\\ lock[pc[a]] # a /\\ ~CanLock(pc[a])''',
     '''  /\\ alive[a] /\\ stage[a] = "made" /\\ FALSE'''),
])

write("SlotClaimNoRecount", "BROKEN VARIANT: claim skips the live-others recount before returning success.", [
    ('''  /\\ alive[a] /\\ stage[a] = "wrote" /\\ LiveOthers(a) < Cap''',
     '''  /\\ alive[a] /\\ stage[a] = "wrote"  \\* CAP recount removed'''),
    ('''  /\\ alive[a] /\\ stage[a] = "wrote" /\\ LiveOthers(a) >= Cap''',
     '''  /\\ alive[a] /\\ stage[a] = "wrote" /\\ FALSE'''),
])

write("SlotClaimNoLiveness", "BROKEN VARIANT: reclaimer fences and removes without checking the pid is dead.", [
    ('''  /\\ alive[a] /\\ stage[a] = "read" /\\ SeenDeadOrEmpty(a)''',
     '''  /\\ alive[a] /\\ stage[a] = "read"  \\* slot_live check removed'''),
])
print("generated SlotClaimTimed, SlotClaimNoFence, SlotClaimNoLock, SlotClaimNoRecount, SlotClaimNoLiveness")
