---
name: dev-spawn
description: Delegate bulk or independent work to headless sub-agents so the main context stays clean; briefs, scout vs ship, worktrees, caps.
---
# dev-spawn

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/harness/`; run tools by that path.

Copy the checklist verbatim into your task list. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=spawn).

## When to Use
- Output would exceed about 50 lines, much reading is needed, work is independent, or you need an unbiased second pair of eyes.
- Not for small edits, or a step whose result you need in context to decide the next one.

## Checklist
- [ ] 1. Pick the shape: scout (report only, no code change) or ship (edits code).
- [ ] 2. Write the brief to `<task>/briefs/<id>.md`, standalone, max 40 lines: goal and why, in-scope files, non-goals, facts already known, the output wanted, the done-check command.
- [ ] 3. Parallel writers each get `--worktree` (branch `harness/<id>`). Scouts need none.
- [ ] 4. Run: `bin/spawn [--shape scout] [--worktree] [--model M] <id> <claude|codex|opencode> <task>/briefs/<id>.md &`, then `wait`. Short ask? `--prompt "text"` instead of a brief file. At most 2 live workers; extras queue; a hung worker is killed after `HARNESS_TIMEOUT` (900 s).
- [ ] 5. Read only `<task>/handoffs/<id>.md`; open the `.log` only if it failed.
- [ ] 6. Accept a report only if it ends `PASS`, `ISSUES` or `BLOCKED` with evidence (command, file:line). No evidence: reject and respawn once; a second miss is a gap, and a gap is not a pass.
- [ ] 7. Dropout: continue with the others and note it. Run `bin/reconcile` to see all states.
- [ ] 8. Ledger what you accepted or rejected. Merge ship branches yourself; discard worktrees you do not merge. Then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

## Phrases to commands
Any CLI can be the main agent and any CLI the worker; it is always the same bash command. If the user does not name a CLI, use the one you are running in.
| User says | You run |
|---|---|
| "open a codex instance and run X" | `bin/spawn --prompt "X" <id> codex` |
| "have opencode review this diff" | scout brief naming the diff command, then `bin/spawn --shape scout <id> opencode <brief>` |
| "run these two in parallel on claude and codex" | two spawns with `&`, then `wait` (cap 2) |
| "use a cheap model for this" | add `--model <name>` (name as that CLI expects it) |
| "run the tests" | `bin/run <cmd>`: no agent; full output to a log, you read the summary |
| a CLI misbehaves or is new | `bin/spawn --doctor` (installed, flags still valid; OpenCode v2 needs `opencode service start` once) |
Workers are headless one-shots, not windows. Edits stay inside the worktree; wider access is the user's call.

## Worker rules (put in every brief)
Do not spawn agents. Do not contact other workers. Write your report to the handoff path with: result (PASS|ISSUES|BLOCKED), evidence, files changed, open questions, next step. Run `bin/ledger` for your own decisions.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Quicker to do it myself" | Fine when tiny. For big reads it fills your context. |
| "Let workers coordinate" | They report up through files only; you coordinate. |
| "A worker can spawn a helper" | Depth is 1; `bin/spawn` refuses inside a worker. |
| "Same tree for two writers" | They clobber each other. Use worktrees. |

## Red Flags
- A brief that says "look into it" with no done-check; reading worker logs instead of reports.
- More than 2 workers; a scout reporting a `violation` status and being ignored.

## Verification
- `bin/reconcile` shows no forgotten running or killed ids; one claim per report was spot-checked before relying on it.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
