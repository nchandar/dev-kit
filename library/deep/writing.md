# writing

## When to Load
- Writing or reviewing a README, spec, PR body, commit message, comment, or error text.

## Pattern
1. Pick one mode per document: tutorial (learn by doing), how-to (steps to a goal), reference (dry facts), explanation (why and trade-offs). Never mix them.
2. Cut every word that does no work. Use the short word: "use", not "utilize".
3. One instruction per sentence. Split instructions over 20 words and other sentences over 25.
4. Write commands in the present tense, active voice. Put the condition before the step.
5. Put the warning before the step it guards. Put the common case first, exceptions after.
6. Name things by their real symbol, file, flag, or command. Use one name per thing everywhere.
7. Keep "the" and "a". Make every "it", "this", and "they" point at one noun.
8. Keep "only" and "not" next to the word they change. Use periods, not semicolons or em dashes.
9. Prefer specific facts over sterile claims: "a column rename fails the build".
10. Remove AI tells: "delve", "pivotal", "serves as", "not just X but Y", forced triples, vague "experts say".
11. Remove filler openers and closers, praise, decorative emojis, and bold on every noun.
12. Use sentence-case headings that carry the point. Use numbered lists for sequences only.
13. Vary sentence length. Take a view where the mode allows it.
14. A PR body is a briefing a reviewer reads in under a minute: what changed, why, risk, test plan.
15. Make every count or path claim true at the commit that lands it.

## Red Flags
- A doc that follows every rule yet reads like a machine wrote it: rewrite the sentence.

Source: pstack/technical-writing
