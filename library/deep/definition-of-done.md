# Definition of Done

## When to Load
- Setting or applying the project-wide release bar.
- A task meets its acceptance criteria and is about to be called complete.

## Pattern
1. Keep task acceptance criteria separate: they prove this change is the requested one.
2. Keep one standing done bar: it proves every change is ready to integrate.
3. Require both before completion, beginning with runtime behavior, regression and edge-case checks.
4. Include scoped quality, integration, documentation, security, observability, and rollback checks as applicable.
5. Tailor the standing bar once for the project; do not renegotiate it per deadline or ticket.
6. Apply the relevant depth by increment, feature, and release, then obtain required human approval.

## Red Flags
- Treating a green test suite as the entire completion bar.
- Changing the bar under delivery pressure.
- Calling work done before runtime verification or required review.

Source: agent-skills/definition-of-done
