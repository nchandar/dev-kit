# performance
Record baseline and result numbers with bin/ledger (phase=perf).

## When to Use
- A measured slowness, a stated budget, or a change on a known hot path. Not for guessing.

## Steps
1. Define the metric and target (latency p95, throughput, memory, startup) and how it is measured.
2. Measure the baseline first, with a repeatable command; record it.
3. Profile; find the dominant cost. Optimize only that.
4. Change one thing, re-measure, keep it only if it moves the metric beyond noise. Name the limiter, the noise floor and what else the number could measure (library/deep/explain-the-number).
5. Look first for algorithmic and I/O wins (N+1 queries, repeated work, missing index, unbounded loops) before micro-optimizing.
6. Add a regression check (benchmark or budget test) if the target matters long term.

## Red Flags
- Optimizing without a number; several changes at once.
- Trading readability for an unmeasured gain.

## Verification
- Before and after numbers from the same command are in the ledger; behavior tests still pass.
