# explain-the-number

## When to Load
- Before measuring, or before reporting or acting on a speedup, regression, latency, throughput or eval score.

## Pattern
1. Before running, write the result that would change a decision and the noise floor. If run spread exceeds the effect, stop.
2. Ask "why not double?" Name the limiter (core, lock, disk, network, the load generator) from a profile or counters, not from reading code.
3. List what else the number could measure: errors, cached or skipped work, code that never ran, an untuned side, noise, a piece too small to matter end to end.
4. Rule out each with evidence.
5. Keep run count, spread and limiter next to the number.
6. For evals: did every trial do the task, and does the gap hold across trials and models?

## Red Flags
- A run started with no decision attached.
- A single run, no spread, no named limiter.
- A gain larger than the time the changed part took.

Source: pstack/principle-explain-the-number
