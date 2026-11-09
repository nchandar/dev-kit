# model-check

## When to Load
- A change touches ordering, concurrency, lease, slot, retry, idempotent rerun or small state, and a test would only cover the cases someone wrote.
- You need a chart of a flow a reader can argue with, backed by every interleaving within a bound.
- Not for a single actor, a UI flow you can click through, or plain logic: a test is cheaper and closer to the code.

## Steps
1. Pick the promise, not the easiest area: a rule whose break harms users and that tests rarely reach. Write it as one sentence, then as a TLA+ INVARIANT. If the model has no variable for it, add the variable.
2. Point every step of the model at code a reviewer can open. What the model treats as one step must be one step in the code. Use the repo's words for states and actions.
3. Choose the tool by the question: TLC on a small TLA+ design is the default for bad orderings; stateful property tests (fast-check, Hypothesis) when the real code is cheap to drive and you want inputs; Quint and Apalache only when the user names them.
4. Keep the constants small: check at 3 workers (or the narrowest bound that shows the race), and draw the chart at 2 workers, because a chart is readable at about 20 arrows and statechart caps it at 500 states.
5. Run plain TLC before any chart:

   ```sh
   java -XX:+UseParallelGC -cp tla2tools.jar tlc2.TLC -workers 1 -config SPEC.cfg SPEC.tla
   ```

   The jar is at `~/.local/share/tla/tla2tools.jar` or `$TLA2TOOLS`. Quote the real line: "No error has been found" or the invariant TLC names.
6. When Bun and pstack's statechart are present, draw the chart from the same spec and config:

   ```sh
   STATECHART=${STATECHART:-$HOME/github/ref/plugins/pstack/skills/statechart}
   bun "$STATECHART/scripts/statechart.ts" SPEC.tla --config SPEC.cfg --view view.mjs --out DIR
   ```

   Without them, draw a Mermaid chart by hand from the TLC trace and label it hand-drawn.
7. Every rule must fail on a broken variant: remove a check or reorder a step in a copy, watch TLC report that rule, then drop the break. A rule never seen failing is untested.
8. Never weaken a rule, a constant or a bound to get a pass. Report the failure with TLC's shortest trace in the code's words.
9. A model finding is a hypothesis until you replay the trace against the real code, one action per step, as a test or a live repro. If the replay cannot fail, the model is wrong until you show otherwise.
10. Record covered files and functions plus the sync commit with library/deep/verify-sync, and log each run with `bin/ledger` (phase=verify).

## Red Flags
- A model whose steps hide two steps of the code.
- A pass with no broken variant ever seen failing.
- Constants shrunk until a found bug disappears.
- A counterexample reported as a code bug without a replay.
- A hand-drawn chart presented as exhaustive.
