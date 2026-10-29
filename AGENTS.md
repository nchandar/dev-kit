# Harness

Lean, agent-agnostic. Installed at `~/.agents/harness/`; the `bin/` tools and `library/` folder live there. Pick the route below, read ONLY that skill, copy its checklist verbatim into your task list (skipped steps stay, with a reason). Skills name the `library/<x>.md` files to read at the step that needs them.

## Routes
- dev-feature: build or refactor: clarify, spec, slices, test-first, review, verify, ship.
- dev-debug: bug or failing test: repro, root cause, doubt, regression test, fix.
- dev-research: question or spike; report as .md/.html; changes no code.
- dev-review: Standards + Spec scouts in parallel, blast radius.
- dev-spawn: delegate to headless sub-agents (max 2, depth 1).
If a route matches, you MUST use it; never implement directly. Unclear request: library/grill first.

## Session start (every new terminal; workers skip it, HARNESS_TASK is already set)
1. `bin/reconcile` lists this repo's open tasks, one line each. Never share a task with another live session.
2. Resume one (read its `next` row via `bin/reconcile <id>`, write a `start` row) or begin new work: `bin/ledger start <slug>` prints your task id.
3. Keep the id. Prefix every harness command with `HARNESS_TASK=<id>` (or pass `-t <id>`). `<task>` below means `.harness/tasks/<id>`; all run files (spec, plan, briefs, handoffs, reports) live there, so parallel sessions and repos never collide.

## Always
- Ledger: `bin/ledger <phase> <decision> <reason> [evidence] [result]` after every step. One append-only TSV file per task at `<task>/ledger.tsv` (columns: time phase decision reason evidence result), never edited or deleted; a wrong call gets a new row that supersedes it. `HARNESS_LEDGER_MIRROR` also reports to a supervisor. Before stopping write a `next` row with the first runnable step; when finished `bin/ledger done "<summary>"`.
- Context guard: bulk output stays out of your context. Commands: `bin/run <cmd>` (log + short summary, no agent). Reading, review, independent work: a dev-spawn worker on any CLI ("open a codex instance and run X"). Take back summaries and paths only.
- Done means `library/verify` evidence, never "it builds".
- State assumptions; stop and ask on conflicting requirements; push back on bad ideas; keep it simple; touch only what was asked.
- Only the main agent spawns. Workers never spawn and report up via handoff files.

## Library (read on demand)
grill spec plan tdd debug-method doubt verify quality-bar architecture docs-grounding simplify security performance observability git-ship ui-browser

## Maintaining this file
Anything needing more than a line goes in a skill or library file, never here. `bin/lint-budget` enforces the caps; if it fails, shrink or move content, do not raise the caps.
