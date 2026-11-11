# property-check

## When to Load
- Default cheap tier for sequential or crash-free logic: state transitions, an ordering inside one actor, a parse or price rule, an idempotent rerun with no second writer.
- The real code is cheap to drive in-process, so thousands of action sequences cost seconds.
- Interleavings, a lease or a second writer: use TLC in library/deep/model-check instead; an expiry timer is an exclusion there unless you model a clock.
- Not for a UI you can click through or plain logic a table of cases covers.

## Steps
1. Write the promise as one sentence, then as a small executable reference model: the states, the actions, and the rule that must hold after every action. Keep the model simpler than the code; a copy proves nothing.
2. Use the target repo's library: the target repo installs fast-check for TypeScript model-based commands or Hypothesis `RuleBasedStateMachine` for Python, with rules, preconditions, invariants and bundles; dev-kit adds no dependency. No framework (a bash repo): a seeded loop with a printed seed and a digest is enough. Duplicated logic: a differential test drives both real copies with the same generated input and fails on disagreement.
3. Drive the real code with the same actions and compare the state with the model after every step. A mismatch is the finding; keep the shortest sequence the tool shrinks to and name the rule it breaks.
4. Inject faults: kill after each step, rerun, and assert the end state matches the model with no double effect. The kill points you list are the coverage you have.
5. Commit the test to the target's suite so a later change fails a test, not a review. A one-off run is a sample, not a guard.
6. Log the model, the action count and the run line with `bin/ledger` (phase=verify).
7. A bug found here: reproduce, fix, then keep the shrunk sequence as the regression test.
8. Name what the model leaves out: concurrency, timing, and retries that need a second writer. Those go to TLC.

## Red Flags
- A reference model that copies the code's branches, so both can be wrong together.
- A property that only asserts no exception.
- Faults injected at the steps you remembered, not every step.
- A pass reported as proof: this samples; the model bounds the sequence, not the state space.
- Concurrency, a lease expiry or a second writer left to this tier.
