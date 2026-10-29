# grill
Record each resolved decision with bin/ledger (phase=grill).

## When to Use
- The request has several readings, no stated scope, or no checkable finish condition.
- Before a feature or any long-running loop. Skip when goal, scope and acceptance check are already stated; ledger that you skipped.

## Steps
1. Read the code and docs first. Never ask what the repo can answer.
2. List unknowns: goal, scope, non-goals, constraints, acceptance check, risks.
3. Ask ONE question per turn, most blocking first. Attach your recommended answer and its tradeoff so the user can reply "yes".
4. Use the project's own words (GLOSSARY.md or domain terms). If a term is overloaded, pin its meaning before moving on.
5. Stop when every unknown is resolved or explicitly deferred: goal in one sentence, non-goals listed, a command or observation that proves done.
6. Play back the plan in at most 10 lines; get an explicit ok before any edit.

## Red Flags
- Questions the codebase could answer, or with no recommendation attached.
- "I'll batch five questions" (answer 1 changes question 2).
- "I can guess what they mean" (a wrong guess costs a build; a question costs a turn).
- Finish condition is "looks good".

## Verification
- One ledger row per resolved decision; playback shown and approved; the acceptance check is runnable or specifically observable.
