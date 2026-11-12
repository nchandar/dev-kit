#!/usr/bin/env python3
"""Generate the broken copies of LeadClaim.tla, one mechanism removed each.

Each variant is the base spec with a named string replacement, so the break is
one visible diff. gen-variants.py --check says whether a copy would change.

  NoLock      no repo-wide lock: publish and count run concurrently
  CountFirst  the old protocol: count live others, unlock, then publish (7e98b33^)
  NoLockSteal a dead owner's lock is never stolen
  CountStale  the cap test counts every claim dir, dead or alive, and reclaims none
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
BASE = (HERE / "LeadClaim.tla").read_text()

# (name, [(old, new), ...])
VARIANTS = {
    "NoLock": [
        ("  /\\ alive[a] /\\ stage[a] = \"try\" /\\ CanLock\n  /\\ lock' = a",
         "  /\\ alive[a] /\\ stage[a] = \"try\" /\\ CanLock\n  /\\ lock' = lock"),
        ("  /\\ alive[a] /\\ stage[a] = \"published\" /\\ lock = a",
         "  /\\ alive[a] /\\ stage[a] = \"published\""),
        ("  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ lock = a /\\ nlead[a] < Max",
         "  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ nlead[a] < Max"),
        ("  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ lock = a /\\ nlead[a] >= Max",
         "  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ nlead[a] >= Max"),
    ],
    "CountFirst": [
        # count live others while holding the lock, before publishing the candidate
        ("  /\\ alive[a] /\\ stage[a] = \"published\" /\\ lock = a",
         "  /\\ alive[a] /\\ stage[a] = \"locked\" /\\ lock = a"),
        ("Claiming == {\"made\", \"published\", \"counted\", \"verified\"}",
         "Claiming == {\"made\", \"published\", \"counted\", \"verified\", \"unlocked\"}"),
        # the unlock after the count: from here the count is stale
        ("LeadVerifyOwn(a) ==",
         "LeadUnlock(a) ==\n"
         "  /\\ alive[a] /\\ stage[a] = \"counted\" /\\ lock = a\n"
         "  /\\ lock' = NoPid\n"
         "  /\\ stage' = [stage EXCEPT ![a] = \"unlocked\"]\n"
         "  /\\ UNCHANGED <<alive, leaddir, leadpid, nlead, holds>>\n\n"
         "LeadVerifyOwn(a) =="),
        # publish after the count (and after the unlock): the old count-then-start
        ("  /\\ alive[a] /\\ stage[a] = \"locked\" /\\ ~LiveDir(a)",
         "  /\\ alive[a] /\\ stage[a] = \"unlocked\" /\\ ~LiveDir(a)"),
        # verify the pid after the publish, not after the count
        ("  /\\ alive[a] /\\ stage[a] = \"counted\" /\\ leadpid[a] = a",
         "  /\\ alive[a] /\\ stage[a] = \"published\" /\\ leadpid[a] = a"),
        ("  /\\ alive[a] /\\ stage[a] = \"counted\" /\\ leadpid[a] # a",
         "  /\\ alive[a] /\\ stage[a] = \"published\" /\\ leadpid[a] # a"),
        # the cap test runs after the unlock, on the stale count
        ("  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ lock = a /\\ nlead[a] < Max",
         "  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ nlead[a] < Max"),
        ("  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ lock = a /\\ nlead[a] >= Max",
         "  /\\ alive[a] /\\ stage[a] = \"verified\" /\\ nlead[a] >= Max"),
        ("  \\/ LeadAccept(a) \\/ LeadRefuse(a) \\/ LeadRelease(a)",
         "  \\/ LeadUnlock(a) \\/ LeadAccept(a) \\/ LeadRefuse(a) \\/ LeadRelease(a)"),
    ],
    "NoLockSteal": [
        ("CanLock == lock = NoPid \\/ (lock \\in Procs /\\ ~alive[lock])",
         "CanLock == lock = NoPid"),
    ],
    "CountStale": [
        ("  /\\ nlead' = [nlead EXCEPT ![a] = LiveOthers(a)]\n"
         "  /\\ leaddir' = [p \\in Procs |-> IF p = a \\/ LiveDir(p) THEN leaddir[p] ELSE FALSE]\n"
         "  /\\ leadpid' = [p \\in Procs |-> IF p = a \\/ LiveDir(p) THEN leadpid[p] ELSE NoPid]",
         "  /\\ nlead' = [nlead EXCEPT ![a] = Cardinality({p \\in Procs : p # a /\\ leaddir[p]})]\n"
         "  /\\ UNCHANGED <<leaddir, leadpid>>"),
    ],
}


def build(name):
    src = BASE.replace("MODULE LeadClaim ", "MODULE LeadClaim%s " % name, 1)
    for old, new in VARIANTS[name]:
        if src.count(old) != 1:
            raise SystemExit("%s: replacement matches %d times:\n%s" % (name, src.count(old), old[:120]))
        src = src.replace(old, new)
    return src


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "write"
    for name in VARIANTS:
        out = HERE / ("LeadClaim%s.tla" % name)
        if mode == "--check":
            old = out.read_text() if out.exists() else ""
            if old != build(name):
                print("%s: would change" % name)
        else:
            out.write_text(build(name))
            print("wrote %s" % out.name)


if __name__ == "__main__":
    main()
