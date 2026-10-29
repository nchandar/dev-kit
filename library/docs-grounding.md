# docs-grounding
Record each fact you relied on, with its source, using bin/ledger (phase=docs).

## When to Use
- Using a library, framework, API or CLI flag you have not verified in this repo, or where versions matter.

## Steps
1. Detect the exact version in use (lockfile, `--version`, go.mod, pyproject).
2. Read the official docs or the tool's own `--help` for that version. Do not guess flags or signatures from memory.
3. Check for deprecations and breaking changes between your assumed and actual version.
4. Implement from what you read; cite the doc URL or help line in a code comment only when non-obvious.
5. Mark anything you could not verify as UNVERIFIED in the ledger.
6. Conflict between docs and observed behavior: trust a minimal run you executed, ledger it, and say so.

## Red Flags
- "I remember the API" for a fast-moving library; copying a Stack Overflow answer of unknown version.
- Fabricated flags. Unsourced claims of "best practice".

## Verification
- Each external fact has a source (URL, help line or run output) in the ledger; the code ran against the pinned version.
