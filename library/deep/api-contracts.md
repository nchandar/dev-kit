# api-contracts

## When to Load
- Designing or changing a public API, module boundary, event, CLI, or data schema.
- Reviewing compatibility, retries, errors, or a migration that unseen consumers may use.

## Pattern
1. Write the contract before implementation: inputs, outputs, invariants, errors, ordering, retry safety, and ownership. Consumers rely on what they observe.
2. Separate caller input from returned state. Example: `CreateInvoiceInput` has no server-created `id` or `createdAt`; authority and defaults stay clear.
3. Use one success representation and structured error shape everywhere. Give errors stable codes and safe messages, because callers automate on codes and operators read messages.
4. Make names reveal role: resource nouns, consistent casing, `is` or `has` booleans, and explicit enum values. Names become client code.
5. Validate untrusted data at the boundary, including third-party responses; trust typed values inside so rules do not drift.
6. Extend before replacing: add optional fields, tolerated enum values, and operations. Never silently remove, rename, narrow, or change the meaning of an exposed field.
7. Treat undocumented output, timing, order, defaults, and error text as depended on. Hide incidental details or document and preserve them.
8. For lists, define pagination, filters, sort order, and empty results at launch; retrofitting them changes semantics and cost.
9. For state changes, state retry semantics. An idempotency key must represent one intent, be claimed atomically, reject a different payload, define an in-flight response, and outlive redelivery.
10. Prefer one evolving contract. Version only for an unavoidable break, with migration steps and a retirement date; avoid competing versions.
11. Test from a consumer's view: old requests parse, old readers ignore additions, errors retain codes and shape, and retries cannot duplicate effects.

## Red Flags
- Different endpoints return `null`, throw, or return unrelated error bodies for the same class of failure.
- A field changes type, meaning, presence, default, ordering, or precision without a migration.
- A retryable write has a check-then-act deduplication path or accepts the same key for different data.
- “Internal” is used to excuse a contract with undocumented consumers.

Source: agent-skills/api-and-interface-design
