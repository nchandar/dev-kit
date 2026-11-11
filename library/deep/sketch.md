# sketch

## When to Load
- Code that crosses a function or module boundary, before writing it.

## Pattern
1. Write the caller's usage first, a few lines of how code will call the new thing.
2. Derive types, signatures and module layout from that usage, bodies "not implemented".
3. Draw two structurally different designs, not two tweaks of one.
4. Screen each: the next contributor sees only files it opened, copies the nearest example, takes the shortest path that compiles, so prefer the design where a wrong change looks wrong.
5. Prefer the smaller public surface that hides more complexity.
6. Show the chosen design on an explain-html page (library/explain-html) for confirmation, skip when trivial, and commit the sketch alone.
7. Implement against the sketch; a needed deviation is a signal, ask whether the sketch, the requirement or the implementation is wrong.
8. Scrap and redo smaller (subtract first, back to step 3) when the same workaround repeats, unrelated edge cases each need a special branch, types need any or casts to compile, or callers must know internals.

## Red Flags
- One candidate only.
- Sketch treated as paperwork.
- Patching a wrong shape.
