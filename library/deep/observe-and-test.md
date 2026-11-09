# observe-and-test

## When to Load
- A runtime path (request, job, pipeline) is touched, debugged, refactored or reviewed.
- You need a fact the code does not show: did it retry, drop, skip?

## Pattern
1. Debug: read the signals that already exist (logs, metrics, traces) before adding any. Add only the missing fact, as an event with a stable name and named fields. Keep it if it is cheap and always-on; otherwise remove it and ledger why.
2. Test: capture signals in memory (a list the code appends to, reset per test). Assert the event name and its fields. Never assert call counts or message wording; that pins how, not what.
3. Refactor: run the same scenarios before and after and compare the captured events. Identical names, fields and order means behavior held; a diff is a change to explain.
4. Prove the test bites: remove the signal, watch the test fail, restore it. A signal no test can lose will rot.
5. Record the signal and its test with `bin/ledger` (phase=observe).

## Worked example
A job retries, then silently drops.
- Debug: the log shows 3 attempts and nothing after. Add `event=job_dropped attempt=3 run_id=<id>` at the drop.
- Test: run a job against a failing provider, then assert the capture holds one `job_dropped` with `attempt=3` and `run_id` set.
- Red first: before the fix there is no event, so the test fails; after, it passes. Delete the log line and it fails again.
- Refactor later: rerun the scenario; the capture must still be `job_attempt` x3 then `job_dropped`, same fields.

## Red Flags
- Asserting on log text or how many times a logger ran.
- A signal added with no test, or a test that passes with the signal removed.
- Shared capture state that leaks between tests.

See library/observability, library/verify.
