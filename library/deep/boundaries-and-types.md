# boundaries-and-types

## When to Load
- Wiring validation, error handling, config parsing or framework adapters.
- Designing types or a signature in a statically typed language.

## Pattern
1. Ask: is this data crossing a boundary now (CLI, config, network, DB row, env)? If not, do not validate again.
2. Parse raw input into domain types once, at the edge. Inside, trust the types and propagate errors.
3. Keep logic in pure functions (state in, result out); the shell only calls them. Extract if it can be pure.
4. Do not leak transport, storage or wire types through the public surface.
5. Wrap same-primitive concepts (UserId vs OrderId) in distinct types; validate at creation.
6. Make illegal states unrepresentable; match all variants exhaustively.
7. Derive types from the owning schema (proto, OpenAPI, migration), not a hand-written copy.

## Red Flags
- Null checks deep in call chains after the edge already validated.
- Business rules inside handlers or framework glue.
- Two string args that can be swapped without a compile error.
- A hand-written type duplicating a schema.

Source: pstack/principle-boundary-discipline + principle-type-system-discipline
