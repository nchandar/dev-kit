# spec-to-code

## When to Load
- You have a TLA+ or Quint model and ask what links it to the code after the replay.
- A spec change and a code change can land apart, and you want a test or a gate to notice.
- This is a decision rule for which link, if any, to build, not a procedure.

## Steps
1. Ask what the model must catch that a test cannot. No answer: keep the one-off replay (library/deep/model-check step 10) and stop.
2. Keep spec traces as a standing test only when both hold: the model is small enough to enumerate, and the code has a seam, meaning an injectable call or an observable event; a command block inside one function is not one. MongoDB Realm Sync generated tests from a TLA+ state graph and the translation took 2 weeks; treat 2 weeks as the cost of one model.
3. Trace validation only when both hold: every spec action maps to an observable event (a message, a log line), and tests that emit those traces already exist. Then compare the trace against the model in CI. Microsoft CCF did this and reports about 2 engineer-months over 4 months.
4. Never attempt trace validation for the internal state of a multithreaded process. MongoDB's server attempt ran about 10 weeks with no match: the spec was too abstract and one tool served one spec.
5. When neither rule holds, stop: a one-off replay is the honest link. Say what stays unlinked.
6. Record the choice, the cost it implies and the covered files with `bin/ledger` (phase=verify), in the coverage record of library/deep/verify-sync.

## Red Flags
- Trace validation chosen because the spec exists, not because actions map to events.
- A generated suite nobody reads, aimed at a model the code has outgrown.
- Internal multithreaded state compared to a spec trace.
- "2 weeks" or "2 engineer-months" promised without naming the model they were measured on.
- A standing test that only checks the spec against itself.
