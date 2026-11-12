#!/usr/bin/env python3
"""Project LeadClaim.tla for the chart: a chart is readable only at a few dozen
states, so the chart copy drops Die and the stale/dead initial states. The TLC
verdicts still stand on the full spec; this copy only draws the happy flow.

usage: gen-chart.py          write LeadClaimChart.tla
       gen-chart.py --check  say whether it differs
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
BASE = (HERE / "LeadClaim.tla").read_text()

EDITS = [
    ("MODULE LeadClaim ", "MODULE LeadClaimChart "),
    ("Next == NoDieNext \\/ \\E a \\in Actors : Die(a)", "Next == NoDieNext"),
    ("Init == InitBase /\\ (InitNoLead \\/ InitOtherLive \\/ InitOtherDead \\/ InitDeadLock)",
     "Init == InitBase /\\ InitNoLead"),
]


def build():
    src = BASE
    for old, new in EDITS:
        if src.count(old) != 1:
            raise SystemExit(f"projection: replacement matches {src.count(old)} times: {old[:80]}")
        src = src.replace(old, new)
    return src


if __name__ == "__main__":
    out = HERE / "LeadClaimChart.tla"
    new = build()
    if "--check" in sys.argv:
        print("same" if out.exists() and out.read_text() == new else "would change")
    else:
        out.write_text(new)
        print(f"wrote {out.name}")
