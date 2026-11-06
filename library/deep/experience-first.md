# experience-first

## When to Load
- designing or building anything a person sees or calls (UI, CLI, library API).

## Pattern
1. Name the user (end user, importing colleague, next maintainer) and the core loop.
2. Justify each control and option by that loop; cut what does not serve it. Three polished features beat ten rough ones.
3. If feel is the question (layout, motion, flow), prototype 2-3 versions in throwaway HTML and compare before production code.
4. Finish the details: transitions, alignment, spacing, feedback on every action, loading/empty/error states.
5. When convenience and delight conflict, choose delight, but say what it costs.

## Red Flags
- option added "just in case"
- error state is a raw exception
- no prototype for a novel interaction.

Source: pstack/principle-experience-first
