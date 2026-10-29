# agent-harness

Skills and small bash tools that work the same under Claude Code, Codex and OpenCode. Plain `SKILL.md` folders, no Node or Python, no tmux.

## Install
1. `git clone https://github.com/nchandar/agent-harness ~/agent-harness`
2. `~/agent-harness/install.sh` (links `~/.agents/harness` and the `dev-*` skills into `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`; safe to rerun)
3. OpenCode v2 only: run `opencode service start` once in a normal terminal.
4. `~/.agents/harness/bin/spawn --doctor` shows which CLIs are installed and still accept our flags.
5. Optional: a global rules file (`AGENTS.md` in `~/.agents/`, `~/.codex/`, `~/.config/opencode/`, and `~/.claude/CLAUDE.md`). Mine lives in my dotfiles; the skills work without it.

## Requirements
- bash 3.2 or newer (macOS /bin/bash 3.2.57 passes a syntax check on every tool)
- git 2.31 or newer (the push guard uses GIT_CONFIG_COUNT); tested with 2.56
- standard Unix tools only: awk, sed, grep, cut, tr, seq, mktemp, ps, pkill, readlink
- at least one agent CLI; tested versions: claude 2.1.308, codex 0.165.0, opencode 2.2.1
- optional: herdr for worker tabs; OpenCode v2 needs `opencode service start` once
- not needed: Python, Node, jq, tmux, gh, timeout

Check a new machine with `~/.agents/harness/bin/spawn --doctor`; it names any missing CLI or flag.

## Skills
| Skill | Use it for |
|---|---|
| `dev-feature` | new behavior or a refactor: grill, spec, slices, test-first, review, verify, ship |
| `dev-debug` | a bug or failing test: repro, root cause, doubt, regression test, fix |
| `dev-research` | a question or "how does X work": grill, research, checkpoint, `report.md` with a build handoff, animated HTML explainer |
| `dev-review` | a diff: Standards and Spec scouts in parallel, blast radius |
| `dev-spawn` | hand work to another agent on claude, codex or opencode |

Each skill opens with a checklist and reads small files from `library/` only when a step needs them (tdd, verify, doubt, explain-html and 13 more).

## Tools (`bin/`)
`ledger` per-task TSV log, `reconcile` open tasks and workers, `spawn` headless worker on any CLI, `run` quiet command runner, `lint-budget` size and naming caps.

## Cross-agent and herdr
- "Open a codex instance and run X" becomes `bin/spawn --prompt "X" <id> codex`. Workers skip permissions but cannot push.
- With herdr running, each worker gets a tab (closed on success, kept when failed) and shows in the Agents panel. `HARNESS_VIEW=off` disables it.
- Other switches: `HARNESS_MODEL`, `HARNESS_SAFE=1`, `HARNESS_TIMEOUT` (900 s), `HARNESS_MAX_WORKERS` (2).

## Reports and explainers
- `dev-research` writes `.harness/tasks/<id>/report.md` (question, answer, evidence, options, recommendation, open questions, `## Build handoff`). `dev-feature` reads it and grills only on what it leaves open.
- For a system or data flow it also writes `report.html`: an animated diagram with play, pause and step controls, a one-line why per step, and small tables for components and decisions. Self-contained and offline. Recipe: `library/explain-html.md`.

## State
Everything a run writes goes to `<repo>/.harness/tasks/<id>/` (gitignored), so parallel sessions never collide. New terminal: `bin/reconcile`.

## Tests and evals
- `tests/run-all.sh`: every script suite with a fake CLI, no tokens.
- `evals/e2e.sh <claude|codex|opencode>`: real scenario with that CLI as the main agent opening two others.

## Measured
- Always loaded: about 3 KB (global rules plus five skill descriptions). A route adds one skill (2 to 3 KB) and the library files it names.
- Cross-agent run, main plus two parallel workers, herdr tabs on: Claude main 117 s, Codex main 96 s, about 0.7 GB extra memory each. Both 7/7 on `evals/e2e.sh`.

## Limits
OpenCode cannot start its service from a sandboxed shell. Worker `--resume` is not built.
