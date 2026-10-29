# doubt
Record each objection and its disposition with bin/ledger (phase=doubt).

## When to Use
- Irreversible or high-stakes steps (migration, auth, deletion, public API), a root cause you feel very sure about, or unfamiliar code. Skip trivial, reversible work.

## Steps
1. CLAIM: state the conclusion in 1 to 3 sentences plus the evidence you hold.
2. EXTRACT: brief a fresh-context scout with ONLY the claim and the artifact (diff or paths). Never include your reasoning or conclusion bias.
3. DOUBT: instruct "find the strongest reason this is wrong; try to disprove, not approve." Run via dev-spawn as a scout.
4. RECONCILE: per objection record confirmed (fix it), refuted (evidence: command or file:line) or unresolved (ask the user).
5. STOP after 2 rounds; still contested means escalate to the user.

## Red Flags
- Briefing the scout with your conclusion, or dismissing objections without evidence.
- More than 2 rounds; using doubt on every trivial step.
- "I already checked": the same context shares the same blind spots.

## Verification
- Every objection has a disposition backed by evidence; confirmed ones were fixed and re-verified.
