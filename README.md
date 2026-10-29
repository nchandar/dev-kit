# agent-harness

Skills and small bash tools that work the same under Claude Code, Codex and OpenCode. Plain `SKILL.md` folders, no Node or Python, no tmux. An agent picks the right workflow for the task, follows its checklist, logs every step, and can hand work to another agent on any of the three CLIs.

## How it works
```
you ask  ->  agent picks a skill by task type  ->  copies its checklist into its task list
                                                        |
        reads small files from library/ only when a step needs them (tdd, verify, doubt ...)
                                                        |
   every step logged to .harness/tasks/<id>/ledger.tsv  ->  big or independent work goes to
   workers (claude, codex or opencode, headless, max 2)  ->  short handoff comes back
```
- **Skills** are the workflows. Each opens with a numbered checklist the agent copies verbatim; a skipped step stays listed with a reason.
- **Library** holds the deeper how-to (17 short files). Nothing loads until a checklist step names it, so the always-loaded cost stays near 3 KB.
- **Ledger** is an append-only TSV per task. A killed session resumes from its last `next` row.
- **Workers** are headless one-shots with their own briefs and handoff files, so the main context stays clean.

An animated walkthrough of the ledger and the automation, with a why for every step, is in `docs/architecture.html`. Open it in a browser; GitHub only shows the source.

## Requirements
- bash 3.2 or newer (macOS `/bin/bash` 3.2.57 passes a syntax check on every tool)
- git 2.31 or newer (the push guard uses `GIT_CONFIG_COUNT`); tested with 2.56
- standard Unix tools only: awk, sed, grep, cut, tr, seq, mktemp, ps, pkill, readlink
- at least one agent CLI; tested versions: claude 2.1.308, codex 0.165.0, opencode 2.2.1
- optional: herdr for worker tabs; OpenCode v2 needs `opencode service start` once
- not needed: Python, Node, jq, tmux, gh, timeout

## Install
1. `git clone https://github.com/nchandar/agent-harness ~/agent-harness`
2. `~/agent-harness/install.sh` (links `~/.agents/harness` and the `dev-*` skills into `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`; safe to rerun, never replaces a real file)
3. OpenCode v2 only: run `opencode service start` once in a normal terminal.
4. `~/.agents/harness/bin/spawn --doctor` names any missing CLI or flag.
5. Optional: a global rules file (`AGENTS.md` in `~/.agents/`, `~/.codex/`, `~/.config/opencode/`, and `~/.claude/CLAUDE.md`). The skills work without it.

## Skills
### dev-feature: build something or refactor
Checklist: clarify (reads a research report if one exists, else straight to the grill) > spec > quality bar > plan into thin slices > per slice: failing test, then code > independent slices in parallel worktrees > review > verify > ship (asks before any push). A refactor variant pins behavior first and compares output to a baseline.
Try: "add rate limiting to the API", "refactor the parser into two modules".

### dev-debug: fix a bug or failing test
Checklist: restate expected vs actual > reproduce with a command > root cause at file:line > a fresh scout tries to disprove it > failing regression test > smallest fix > verify the original repro plus an adjacent case.
Try: "login test fails on CI", "this crashes on empty input".

### dev-research: answer a question or explain a system
Checklist: grill you on the question > research with evidence for every claim > checkpoint (you agree or disagree; disagreement means grill again and research more, up to 3 rounds) > `report.md` ending in a `## Build handoff` that dev-feature can start from > for systems, `report.html`. Changes no project code.
Try: "compare Redis and Postgres for our queue", "explain how data flows through this app".

### dev-review: review a diff
Checklist: pin the base > two scouts in parallel, Standards (repo rules, smells) and Spec (each requirement met, partial, missing, extra) > blast-radius check beyond the diff > merged findings with file:line > optional doubt pass.
Try: "review my branch against main".

### dev-spawn: hand work to another agent
Checklist: choose scout (report only) or ship (edits code) > write a standalone brief > worktree per parallel writer > run on claude, codex or opencode > read only the handoff > accept it only with evidence.
Try: "open a codex instance and run the migration check", "have opencode review this diff", "run these two in parallel on claude and codex".

### dev-learn: turn learnings into library improvements
Checklist: list the queued learnings > dedupe against the library > classify (principle, recipe or project-specific) > generalize and scrub > draft on a branch in a separate worktree > lint and tests > show you the diff and ask > merge only after you approve. The live library is never touched before that.
Try: "learn from this", or when `reconcile` says learnings are queued.

## State, memory and learning
- **Ledger** (`ledger.tsv`): what happened and why. Append-only, never deleted.
- **`state.md`** (per task): the current picture: findings, decisions that shape direction, direction, open questions, learnings. Rewritten at checkpoints. Pointers, not copies: `bin/state check` flags bullets with no pointer and text copied from ledger rows.
- **`.harness/memory.md`** (per project): durable how-to-build, gotchas and architecture notes. Updated at closeout.
- **Learnings** are captured as they appear (`- [ ] lesson | scope: project|general|recipe | ref: pointer`). At closeout, project ones go to `memory.md`; general and recipe ones go to a local inbox (`bin/learn queue`). `dev-learn` then drafts library changes on a branch and merges only after you approve.
- All of it is local and git-ignored: `ledger start` adds `.harness/` to the repo's `info/exclude`. The inbox lives outside any repo.

## Library
Read on demand by checklist steps. Three tiers: the digest `principles.md` (read first), `deep/` (long tail, loaded on a trigger), and `recipes/` (reusable procedures, with an index).
- **Define and plan:** `grill`, `spec`, `plan`
- **Build:** `tdd`, `architecture`, `simplify`, `quality-bar`, `docs-grounding`, `ui-browser`
- **Prove it:** `verify`, `doubt`, `debug-method`
- **Harden and operate:** `security`, `performance`, `observability`
- **Ship and explain:** `git-ship`, `explain-html`

## Usage
- **Just ask.** With the global rules, agents route by task type. To be explicit: `/dev-feature` in Claude Code, or "use dev-debug on this" in Codex and OpenCode.
- **Default order:** grill (one question at a time, each with a recommendation), plan, build test-first, review, verify.
- **New terminal:** `~/.agents/harness/bin/reconcile` lists open tasks and workers; resume a task from its `next` row, or `bin/ledger start <slug>` for new work.
- **Workers:** a hung worker is killed after 900 s; the main agent never waits on a prompt because workers skip permissions, and they can never push.

## Tools (`bin/`)
| Tool | Use |
|---|---|
| `ledger` | `start <slug>` a task; `-t <id> <phase> <decision> <reason> [evidence] [result]` a row; `done` to close |
| `reconcile` | `reconcile` open tasks and queued learnings; `reconcile <id>` resume point, direction, open questions, workers |
| `spawn` | `spawn [--shape scout\|ship] [--worktree] [--model M] <id> <claude\|codex\|opencode> <brief>` or `--prompt "text"`; `--doctor`; `--close-views` |
| `state` | `state check` validates `state.md` and `memory.md` (pointers, size, no copied text) |
| `learn` | `learn queue\|list\|count\|done`: the local learning inbox |
| `run` | `run <cmd>` full output to a log, short summary back |
| `lint-budget` | size caps, `dev-` names, resolvable references, public-safety scan |

## Cross-agent and herdr
- "Open a codex instance and run X" becomes `bin/spawn --prompt "X" <id> codex`. Workers skip permissions but a dead push URL is set on every remote, so they cannot push.
- With herdr running, each worker gets a tab labelled `<id> · <cli> · <shape>` and shows in the Agents panel. It closes on success and stays open, marked blocked, on failure. `HARNESS_VIEW=off` disables it.

| Variable | Effect |
|---|---|
| `HARNESS_VIEW` | `off` disables herdr tabs |
| `HARNESS_VIEW_KEEP`, `HARNESS_VIEW_NOTIFY=all` | keep tabs after success; notify on success too |
| `HARNESS_MODEL` | model name passed to the CLI (cheaper workers) |
| `HARNESS_SAFE=1` | restricted worker permissions instead of skipped |
| `HARNESS_TIMEOUT`, `HARNESS_MAX_WORKERS` | worker timeout (900 s), live workers (2) |

## Reports and explainers
- `dev-research` writes `.harness/tasks/<id>/report.md` (question, answer, evidence, options, recommendation, open questions, `## Build handoff`).
- For a system or data flow it also writes `report.html`: an animated diagram with play, pause and step controls, a one-line why per step, and small tables for components and decisions. Self-contained and offline. Recipe: `library/explain-html.md`.

## State on disk
```
<repo>/.harness/               gitignored
  run/slot.N                   worker slots (repo-wide cap)
  tasks/<slug>-<date>-<rand>/  one per session or job, so parallel sessions never collide
    ledger.tsv  spec.md  plan.json  briefs/  handoffs/  run/  runs/  report.md  report.html
```

## Tests and evals
- `tests/run-all.sh`: every script suite with a fake CLI, no tokens.
- `evals/e2e.sh <claude|codex|opencode>`: real scenario with that CLI as the main agent opening two others.

## Measured
- Always loaded: about 3 KB (global rules plus five skill descriptions). A route adds one skill (2 to 3 KB) and the library files it names.
- Cross-agent run, main plus two parallel workers, herdr tabs on: about 50 to 120 s and 0.7 GB extra memory. 7/7 on `evals/e2e.sh` with Claude and with Codex as the main agent.

## Limits
OpenCode cannot start its service from a sandboxed shell. Worker `--resume` is not built.

## Keep it public-safe
- This repo is public. Never commit secrets, tokens, API keys, `.env` files, personal paths (`/Users/<name>`, `/home/<name>`), email addresses or machine-specific config.
- Use `~`, `$HOME` and `<placeholders>` in docs, examples, briefs and tests.
- `bin/lint-budget` fails on home paths, email addresses (except `example.com`) and secret-shaped strings. Run `tests/run-all.sh` before every commit.
- `.harness/` is gitignored on purpose: ledgers, briefs and handoffs can contain paths and prompts. Never commit it.

## Acknowledgements
Ideas adapted, not copied, from [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (skill anatomy, doubt pass), [mattpocock/skills](https://github.com/mattpocock/skills) (grilling, two-axis review, TDD) and [cursor/plugins](https://github.com/cursor/plugins) (pstack decision log, ralph-loop promise tag, orchestrate handoffs). All MIT.

## License
MIT, see `LICENSE`.
