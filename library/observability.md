# observability
Record what signals were added and how to read them with bin/ledger (phase=observe).

## When to Use
- A change adds or touches a runtime path (request, job, pipeline), or a bug needed a deep dig to explain.

## Steps
1. Ask the failure questions: what would I need to see at 3am to know this broke, where, and for whom?
2. Logs: structured (key=value or JSON), one event per decision point, with ids to correlate (request, job, user). Levels mean something. Never log secrets or personal data.
3. Metrics: rate, errors, duration (RED) per operation; low-cardinality labels only.
4. Traces or correlation ids across process boundaries.
5. Alerts on symptoms users feel (errors, latency), not on causes; each alert names the first thing to check.
6. If a deciding fact took a deep dig to find, add the cheap always-on signal that would have shown it at first look.
7. Prove it: trigger the failure path once and read the signal you added.

## Red Flags
- Print debugging left in; logging in hot loops; high-cardinality labels.
- Alerts nobody can act on; signals never exercised.

## Verification
- You triggered the failure path and the log, metric or trace showed it; no sensitive data appears in output.
