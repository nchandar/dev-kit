# spec-driven

## When to Load
- A feature has unclear, broad, or multi-capability requirements and needs a shared approval point.
- You are about to plan or build after writing requirements, or requirements changed during delivery.

## Pattern
1. Start with the outcome, user, and reason. State assumptions first, because an unstated guess becomes a requirement after code exists.
2. Recast each request as an observable condition: “given an expired link, when it is opened, then access is denied and the renewal path is shown.” A condition that cannot fail cannot guide a build.
3. Separate requirements from implementation choices. Record stable constraints and interfaces, but leave room for the smallest design that proves the outcome.
4. Define non-goals and boundaries: always do, ask first, never do. They make scope decisions repeatable when adjacent changes appear.
5. Include the real build, test, lint, and run commands plus where code and tests belong. A spec should let a new contributor verify it without guessing the local workflow.
6. When capabilities have distinct consumers or checks, write a capability map first: stable module ids, responsibilities, one-way dependencies, and build order. Approve it before module specs, because planning cannot repair a wrong boundary cheaply.
7. Give each module or feature explicit success criteria, open questions, and an owner boundary. Change the spec before changing implementation.
8. Save the spec, summarize assumptions and open questions, then pause for human approval. Do not plan, create tasks, or write code in the same turn: approval is the point where misunderstanding is still inexpensive.
9. After approval, turn each criterion into a slice and check. If scope or design changes, update and re-approve rather than letting code become the specification.

## Red Flags
- “Done” is a feeling, a mockup, or an implementation instruction rather than a failing or passing condition.
- One large spec blends capabilities that could be tested, shipped, or removed independently.
- Planning or coding starts before the written spec has an explicit approval.
- Commands, constraints, assumptions, or open questions live only in chat or someone’s memory.

Source: agent-skills/spec-driven-development
