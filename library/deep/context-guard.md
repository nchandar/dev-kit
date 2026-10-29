# Guard the Context Window

## When to Load
- Large logs, files, diffs, or fan-out investigation threaten useful context.
- Planning needs many independent reads or commands.

## Pattern
1. Split work into small phases with an explicit file and output budget.
2. Send noisy commands and bulk reading to an isolated log or worker.
3. Return only a decision-ready summary: findings, evidence path, and next action.
4. Keep raw payloads out of the main thread unless a specific detail needs inspection.
5. Re-read only the relevant excerpt when a summary raises a question.

## Red Flags
- Pasting full test output or large files into the working conversation.
- Repeating broad searches after the relevant result is already recorded.
- Delegating without a cap on scope or a required summary format.

Source: pstack/principle-guard-the-context-window
