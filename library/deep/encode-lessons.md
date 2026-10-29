# Encode Lessons in Structure

## When to Load
- A correction or instruction has appeared more than once.
- A repeated failure has a mechanically detectable cause.

## Pattern
1. Name the recurring mistake and the point where it enters the system.
2. Prefer a lint rule, schema constraint, metadata field, runtime guard, or script that prevents it.
3. Put the check at the earliest reliable boundary, and make its failure actionable.
4. If judgment cannot be automated, elevate the rule and show one concrete failure case.
5. Remove redundant prose after a structural control owns the rule.

## Red Flags
- Repeating a rule in prompts, comments, and reviews instead of enforcing it.
- Adding a warning that can be ignored when a failing check is possible.

Source: pstack/principle-encode-lessons-in-structure
