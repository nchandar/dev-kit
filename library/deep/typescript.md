# typescript

## When to Load
- Reading or editing .ts or .tsx files.

## Pattern
1. Model variants as a union with a `kind` literal; no bags of optional fields.
2. External data is `unknown`; parse once at the edge (schema lib + inferred type if the repo has one) into a named type.
3. Brand same-primitive ids (`string & {readonly __brand:"UserId"}`); mint only through a guard that verifies, never `as`.
4. Ban `as`; prefer `satisfies` to check without widening. A guard that lies is worse than `as`. Exception: the guard that mints a brand.
5. Narrow in this order: discriminant switch, `in`, typeof/instanceof, custom guard.
6. End switches with `const _x: never = v;` so a new variant fails compile.
7. Build the illegal value out of the type (`[T, ...T[]]` for non-empty); keep `T[]` while operations stay total.
8. Derive types (Pick, ReturnType, typeof) before declaring new interfaces; pass objects, not long positional args (except hot paths).
9. Use structured logging, not console.log, in shipped code.

## Red Flags
- `as` used to silence the compiler.
- Unparsed `unknown` or `any` passed inward.

Source: pstack/typescript-best-practices
