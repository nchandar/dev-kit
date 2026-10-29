# model-the-domain

## When to Load
- Adding a branch to an if/else chain, or a second flag that must stay in sync with the first.
- Writing stateful logic, or the same shape assumption shows up in several files.

## Pattern
1. Ask what the code must never allow, and how the data is read. Pick the structure that encodes exactly that.
2. Scattered flags or phases: one state machine or tagged union, with explicit transitions.
3. Branching on kind across files: a lookup table or registry keyed by kind.
4. Loose params passed around: one typed model, built once.
5. Organize modules around one body of domain knowledge, not around steps (load, validate, save); name each module by its role or layer. Step order is not ownership.
6. Pick the structure at write time; later it reads as a refactor and gets deferred.
7. If the current shape is clear and local, keep it boring.

## Red Flags
- A new feature that is "one more branch".
- Phase-named modules repeating the same domain rule.
- An abstraction that adds indirection but removes no branch, duplicate rule or invalid state.

Source: pstack/principle-model-the-domain
