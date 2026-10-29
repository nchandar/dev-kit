# Consider Design Options

## When to Load
- A novel interaction or architecture has no local precedent.
- A new requirement would otherwise become a bolt-on.
- Choosing core types, data structures, or shared concurrent state.

## Pattern
1. Read the affected design, then restate the problem as if the new requirement existed from day one.
2. Sketch two or three materially different options and compare their user flow, complexity, and failure modes.
3. Define data shapes before control flow; trace dominant reads, writes, and ownership.
4. Prefer the option that preserves future choices while keeping today's path explicit.
5. Isolate shared mutable state unless concurrent changes are harmless by design.
6. Build foundations that help every later slice, then ship the chosen redesign in small coherent increments.
7. Update every contract, example, type, and rationale touched by the decision.

## Red Flags
- Selecting the first workable approach without comparison.
- New behavior scattered as conditionals across existing callers.
- Premature abstraction where three explicit cases would be clearer.

Source: pstack/principle-exhaust-the-design-space; principle-redesign-from-first-principles; principle-foundational-thinking
