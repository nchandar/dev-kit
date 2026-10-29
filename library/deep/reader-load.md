# Minimize Reader Load

## When to Load
- Code is hard to trace or explain to a new reader.
- Considering a wrapper, adapter, shared state, or abstraction.

## Pattern
1. Trace from the question to its answer; count indirections and hidden state separately.
2. Inline a one-caller wrapper or pass-through layer unless it hides a real decision.
3. Keep each boundary meaningful: it should compress complexity, not repeat arguments and methods.
4. Narrow mutable state: pure return values, then locals, then instance fields, before module or global state.
5. State an invariant at its boundary so consumers do not reconstruct it.
6. Ask whether a reader can find an input and its mutators in 30 seconds.

## Red Flags
- An abstraction exists for a future implementation that does not exist.
- A flat module relies on many mutable globals.
- Adjacent layers expose the same API with different names.

Source: pstack/principle-minimize-reader-load
