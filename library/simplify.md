# simplify
Record what was removed or reshaped with bin/ledger (phase=simplify).

## When to Use
- Code works but is harder to read, change or test than it should be; during review, never mixed with a behavior change.

## Steps
1. Pin behavior first: tests green, baseline output saved.
2. Find friction: deep nesting, duplicated shapes, mystery names, dead code, speculative options, needless indirection.
3. One simplification at a time; rerun tests after each; keep each as its own commit.
4. Prefer deleting over restructuring, and boring over clever.
5. Respect repo conventions; they win over your taste.
6. Ask: would a staff engineer say "why didn't you just..."? If 100 lines would do, do not keep 1000.

## Red Flags
- Behavior change smuggled into a "cleanup".
- Renaming and restructuring unrelated code; deleting code you do not understand.

## Verification
- Tests and baseline output identical before and after; diff only removes or reshapes.
