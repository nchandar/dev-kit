# blast-radius

## When to Load
- reviewing or shipping a change you do not yet trust; "what could this break".

## Pattern
1. Read the diff: symbols added, changed, deleted, and what now behaves differently.
2. Find the ONE fact the change is safe because of (e.g. "this call only drops dead entries").
3. Look past grep: library source and pinned version, timing/teardown order, data shapes from APIs, configs, saved data.
4. Score that fact: 1 asserted, 2 cited file:line, 3 failure path walked and unreachable, 4 ran real code that fails loud, 5 reproduced in the running app.
5. Take it to level 4 when cheap: a small script calling the exact function with the shipped library.
6. After a rename or changed default, rg the old name and old values (also "max N" near the noun) in README, ARCHITECTURE, AGENTS and tests; a numeric cap in a spec gets a test in the same slice.
7. Report: what it does; the safe-because fact and its level; risks (file:line, likelihood, cost); cleared items; cheapest pre-merge check.

## Red Flags
- a convincing writeup with no run. Write "unproven" instead.

Source: pstack/blast-radius
