---
name: dev-spawn
description: Use when work is bulk, independent or needs a second opinion from another agent.
disable-model-invocation: true
---
# dev-spawn

Paths: the `bin/` tools and the `library/` folder live in `~/.agents/dev-kit/`; run tools by that path.

Task: no `DEVKIT_TASK` set? Run `~/.agents/dev-kit/bin/ledger start <slug>` first (it prints your id) and prefix dev-kit commands with `DEVKIT_TASK=<id>`. `<task>` below is `.devkit/tasks/<id>` at the repo root; never write run files anywhere else. Also read `.devkit/memory.md` if it exists.

Open the host todo list (todowrite, TodoWrite or TaskCreate, whichever exists; else a checklist in <task>/state.md) with this checklist verbatim, and tick items as steps finish. A skipped step stays listed with a reason. Run `bin/ledger` after every step (phase=spawn).

## When to Use
- Output would exceed about 50 lines, much reading is needed, work is independent, or you need an unbiased second pair of eyes.
- A long task nobody watches: also follow library/deep/overnight.
- Not for small edits, or a step whose result you need in context to decide the next one.

**You own:** delegated work and the decision to accept or reject each handoff.

**Reads:** always library/principles (step 0), library/state. For a long task nobody watches: library/deep/overnight.

## Checklist
- [ ] 0. Skim library/principles (about 700 tokens); open a deep file only when its trigger matches.
- [ ] 1. Pick the shape: scout (report only, no code change) or ship (edits code).
- [ ] 2. Write the brief to `<task>/briefs/<id>.md`, standalone, max 40 lines: goal and why, in-scope files, non-goals, facts already known, the output wanted, the done-check command, and either a `route: dev-x` line (the worker follows that playbook's checklist; column-0 line outside code fences, indented only as fallback, first usable wins, column-0 beats indented) or its own `## Checklist`. spawn gives every worker a checklist anyway and the worker ticks it in its host todo list.
- [ ] 3. Parallel writers each get `--worktree` (branch `devkit/<id>`). Scouts need none.
- [ ] 4. Run: `bin/spawn [--shape scout] [--worktree] [--model M] <id> <claude|codex|opencode> <task>/briefs/<id>.md`, each worker as its OWN background command so every finish notifies you (never wait on a group: the slowest hides the rest). When one finishes, read its handoff and check its output exists before trusting PASS. Copy any `learnings` from accepted handoffs into `state.md` (library/state). Short ask? `--prompt "text"` instead of a brief file. Live workers are capped (limits in the ARCHITECTURE.md env table); extras queue; a hung worker is killed after `DEVKIT_TIMEOUT`.
- [ ] 5. Read only `<task>/handoffs/<id>.md`; open the `.log` only if it failed. Several workers in one batch: say nothing about a single handoff while others still run; when all have finished or dropped out, give ONE combined answer, never per-worker commentary.
- [ ] 6. Accept a report only if it ends `PASS`, `ISSUES` or `BLOCKED` with evidence (command, file:line) and spawn printed `checklist: n/n` (missing or open items: read the handoff, then reject or ask). No evidence: reject and respawn once; a second miss is a gap, and a gap is not a pass. Then `bin/ledger accept "<id> accepted|rejected" <reason>`; the Stop hook blocks you until every worker you spawned has one; `bin/reconcile --wait` waits for running ones.
- [ ] 7. Dropout: continue with the others and note it. Run `bin/reconcile` to see all states.
- [ ] 8. Ledger what you accepted or rejected. Merge ship branches yourself; discard worktrees you do not merge. After merging or discarding, run `bin/spawn --prune -t <task> --yes`. Closeout: follow library/state. Then close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.

## Phrases to commands
Any CLI can be the main agent and any CLI the worker; it is always the same bash command. If the user does not name a CLI, use the one you are running in.
| User says | You run |
|---|---|
| "open a codex instance and run X" | `bin/spawn --prompt "X" <id> codex` |
| "have opencode review this diff" | scout brief naming the diff command, then `bin/spawn --shape scout <id> opencode <brief>` |
| "run these two in parallel on claude and codex" | two spawns, each as its own background command (within the worker cap) |
| "use a cheap model for this" | add `--model <name>` (name as that CLI expects it) |
| "run the tests" | `bin/run <cmd>`: no agent; full output to a log, you read the summary |
| a CLI misbehaves or is new | `bin/spawn --doctor` (installed, flags still valid; OpenCode v2 needs `opencode service start` once) |
Workers run interactive in a herdr tab (`DEVKIT_MODE=auto`); headless is only the fallback when herdr is down. Never pick -p/exec/run by hand. Edits stay inside the worktree; wider access is the user's call.

## Worker rules (put in every brief)
Do not spawn agents. Do not contact other workers. Write your report to the handoff path with: result (PASS|ISSUES|BLOCKED), evidence, files changed, open questions, next step, learnings (reusable lessons, each with a pointer), then a `## Checklist` section with every item ticked. Run `bin/ledger` for your own decisions.

**Hand off to:** the calling route with the accepted handoffs.

**Reply:** one combined answer after every worker has finished or dropped out: accepted and rejected handoffs, evidence, gaps.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Quicker to do it myself" | Fine when tiny. For big reads it fills your context. |
| "Let workers coordinate" | They report up through files only; you coordinate. |
| "A worker can spawn a helper" | Only if its prompt allows it, up to DEVKIT_MAX_DEPTH. |
| "Same tree for two writers" | They clobber each other. Use worktrees. |

## Red Flags
- A brief that says "look into it" with no done-check; reading worker logs instead of reports.
- More than 2 workers; a scout reporting a `violation` status and being ignored.

## Verification
- `bin/reconcile` shows no forgotten running or killed ids; one claim per report was spot-checked before relying on it.
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
