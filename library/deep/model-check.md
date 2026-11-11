# model-check

## When to Load
- A change touches ordering, concurrency, lease, slot, retry, idempotent rerun or small state, and a test would only cover the cases someone wrote.
- You need a chart of a flow a reader can argue with, backed by every interleaving within a bound.
- Not for a single actor, a UI flow you can click through, or plain logic: a test is cheaper and closer to the code.
- The build and drift passes live in dev-create-formal-verification-skill and dev-maintain-formal-verification-skill; this file holds the tool choice and commands.

## Steps
1. Pick the promise, not the easiest area: a rule whose break harms users and that tests rarely reach. Write it as one sentence, then as a TLA+ INVARIANT. If the model has no variable for it, add the variable.
2. Point every step of the model at code a reviewer can open. What the model treats as one step must be one step in the code; a helper called once is one action, and its dropped interleavings go in the exclusions. Use the repo's words for states and actions.
3. Choose the tool by the question: TLC on a small TLA+ design is the default for bad orderings; a stateful property test against a small executable reference model (library/deep/property-check) for sequential or crash-free logic the code can drive; for linking a spec to the code, use the decision rule in library/deep/spec-to-code; Quint and Apalache only when the user names them.
4. Keep the constants small: check at 3 actors (or the narrowest bound that shows the race), and draw the chart at 2 actors, because a chart is readable at a few dozen arrows and above 500 states tlachart draws only the paths to broken rules; the 500 states are not a readability budget (476 states drew 644 arrows), so project away crash actions for the chart. Cap the run: a small bound per change and a larger bound scheduled; log the bound and seconds, measured on our own models, not copied.
5. List what the model leaves out: timers, lock or lease expiry, process stalls, retries, commands that are not atomic. A pass holds only without them. When a timeout is the only guard, check an untimed variant (a violation there is stall-dependent until the replay fails) and a timed variant that states the assumption. Replay with a stall injected past each expiry and say so in the reply.
6. Run plain TLC before any chart (Java 11+; checked on 27; `tla2tools.jar` from the TLA+ releases page):

   ```sh
   java -XX:+UseParallelGC -cp "${TLA2TOOLS:-$HOME/.local/share/tla/tla2tools.jar}" tlc2.TLC -workers 1 -deadlock -config SPEC.cfg SPEC.tla
   ```

   Quote the real line: "No error has been found" or the invariant TLC names. No Java or jar: report blocked and ask; do not install unasked. Terminal states are not deadlocks, hence `-deadlock`. Spec too big to exhaust: run it under a time quota, `timeout 60 java ... tlc2.TLC -simulate num=1000 -seed N -depth D -config SPEC.cfg SPEC.tla` (`num` bounds the traces; without it nothing prints until the quota), record the seed and depth, and never report a simulate pass as holds: it samples behaviors.
7. With Bun and `tlachart` installed (MIT), draw the chart from the same spec and config. `tlachart` installs to `~/.bun/bin`, so that folder must be on PATH, and `--out` must be new or empty, and the chart cfg needs `CHECK_DEADLOCK FALSE` or a terminal path reads as a broken rule. `--view` is an optional module that names the states for the reader:

   ```sh
   tlachart SPEC.tla --config SPEC.cfg --view VIEW.mjs --out DIR
   ```

   No `tlachart`: report the chart blocked and ask; do not install unasked. The TLC result still stands.
   Optional: when `pele` (MIT, `bun add pele`) is installed, `bin/chart-svg DIR/chart.mmd DIR/chart.svg` writes the SVG page and prints a render error as plain text; without `pele`, present `DIR/chart.mmd` as is.
8. Every rule must fail on a broken variant: remove a check or reorder a step in a copy, watch TLC report that rule, then drop the break. One break may fail several rules: name the first, then rerun a single-invariant cfg to name the one the mechanism owns. A rule never seen failing is untested.
9. Never weaken a rule, a constant or a bound to get a pass. Report the failure with TLC's shortest trace in the code's words.
10. A model finding is a hypothesis until you replay the trace against the real code, one action per step, as a test or a live repro; to inject a stall without editing the code, shadow one command (a wrapper that sleeps after a call) over functions extracted byte-identical to the source, and show the diff. If the replay cannot fail, the model is wrong until you show otherwise.
11. Record covered files and functions plus the sync commit with library/deep/verify-sync, and log each run with `bin/ledger` (phase=verify).

## Red Flags
- A model whose steps hide two steps of the code.
- A pass with no broken variant ever seen failing.
- A safe verdict for a lock or lease whose expiry or stall is not modeled.
- Constants shrunk until a found bug disappears.
- A counterexample reported as a code bug without a replay.
