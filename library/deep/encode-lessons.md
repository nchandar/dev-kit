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
6. Fix at the highest level that works: remove the wrong path by design, then types, then a lint whose error names the replacement, then a test, then docs last.
7. Prove each new check fails on a real past mistake before trusting it. Run the same command locally and in CI.
8. Keep a rule table: rule, enforcer. A repeated rule with no enforcer gets fixed in the same change; drop a rule once its mistake cannot happen.

## Red Flags
- Repeating a rule in prompts, comments, and reviews instead of enforcing it.
- Adding a warning that can be ignored when a failing check is possible.

Source: pstack/principle-encode-lessons-in-structure
