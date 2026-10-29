# spec
Record the approved spec path with bin/ledger (phase=spec).

## When to Use
- New feature or significant change with no written requirements. Skip for one-file fixes with obvious scope.

## Steps
1. Start from the grill output. Write `<task>/spec.md` (max 40 lines): goal, users, non-goals, requirements, acceptance criteria, constraints, open questions.
2. Make each requirement testable: "given X, when Y, then Z" or a command with expected output.
3. Name the interfaces touched (API, CLI, data shape, UI) and what must not change.
4. List assumptions explicitly; the user can veto any.
5. Get approval, then freeze it. Changes later go through the ledger as a decision, not a silent edit.

## Red Flags
- Requirements phrased as implementation ("use Redis") without a reason.
- No non-goals (scope will creep).
- Acceptance criteria that cannot fail.
- Building without a spec because "it's obvious".

## Verification
- Every requirement has an acceptance check; the user approved; spec path is in the ledger.
