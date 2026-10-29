# build-the-lever

## When to Load
- Non-trivial edits, migrations, analyses or checks, especially across many files.
- About to hand-apply the same change repeatedly, or fan work out to delegates.

## Pattern
1. Do the first unit by hand to learn the recipe.
2. Write the smallest script, codemod or generator that does it; never a framework.
3. Prove it: rerun on that unit and diff against the hand result. Make it safe to rerun.
4. If one pass covers every unit, run it yourself instead of fanning out.
5. If delegates are needed, write the recipe, verification contract and do-not-touch list as one file they read, outside their write scope.
6. Checks count too: a rerunnable command beats "I looked".
7. Commit the lever when the work outlives the session.

## Red Flags
- Citing this with no script or generator in the diff.
- Reviewer can only verify by redoing the work.
- Hand edits across dozens of files.

Source: pstack/principle-build-the-lever
