# Contributing

For people and AI agents. Goal: change dev-kit without breaking it. Overview and install: `README.md`.

## 1. Before you change anything
Both must pass before every commit:
```
tests/run-all.sh      # all suites with fake CLIs, then the lint; no tokens
bin/lint-budget       # caps, names, references, public-safety scan
```
Requirements: bash 3.2 or newer, git 2.31 or newer. Standard Unix tools only (no Python, Node, jq).

## 2. Layout
| Path | Purpose |
|---|---|
| `AGENTS.md` | Always-loaded routes and rules; `CLAUDE.md` is a symlink to it |
| `skills/dev-*/SKILL.md` | The workflows (checklist, rationalizations, red flags) |
| `library/principles.md` | Digest, read first; points to deep files |
| `library/*.md` | Core how-to files, read when a checklist step names them |
| `library/deep/` | Long tail, loaded only when a trigger matches |
| `library/recipes/` | Repeatable procedures with commands, plus `index.md` |
| `bin/` | Tools: ledger, reconcile, spawn, state, learn, run, lint-budget, stop-gate |
| `tests/` | One script suite per tool, plus `run-all.sh` |
| `evals/` | Real-agent end-to-end checks (cost tokens) |
| `docs/` | `flow.svg` (README hero), `architecture.svg` (detailed, animated) and `architecture.html` (interactive walkthrough) |

## 3. The budgets
Enforced by `bin/lint-budget`:
| Cap | Limit |
|---|---|
| `AGENTS.md` size | 6144 B |
| Skill descriptions, total | 4096 B (each one line) |
| Skill file | 150 lines |
| Skill count | 4 to 12 |
| Core library file | 80 lines |
| Core library, total | 32768 B |
| `library/deep/` file / total | 45 lines / 65536 B |
| `library/recipes/` file / total | 45 lines / 49152 B |

- Names: `dev-` prefix, and `name:` equals the folder.
- Each tier also needs its required sections and resolvable `library/...` references.
- Lint fails: shrink or move content. Do not raise a cap without a stated reason.

## 4. Keep things aligned
One home per rule. Point to it elsewhere, never copy.
| If you change | Also update |
|---|---|
| A skill checklist or description | The skills table in `README.md` |
| A tool flag or behavior | Its test suite, the `README.md` commands table, `spawn --doctor` if it checks the flag |
| A library rule | Its home file, and the pointer in `library/principles.md` |
| `AGENTS.md` routes | `README.md` (skills, usage)  |
| A recipe | Its line in `library/recipes/index.md` |
| The task flow, tools or tiers | `docs/flow.svg`, `docs/architecture.svg`, `docs/architecture.html` and `ARCHITECTURE.md` |

## 5. Adding things
| Add | How |
|---|---|
| Skill | Max 8 total (raised from 6 because the set keeps growing; the descriptions cap bounds what is always loaded). Folder `skills/dev-<name>/`, one-line description, required sections, `library/state` closeout; add a route to `AGENTS.md` and a README entry, unless it is an explicit-only support skill such as `dev-create-formal-verification-skill` |
| Library file | Prefer extending one. New file needs When to Use, Steps, Red Flags, Verification and a `bin/ledger` line |
| Deep file | `library/deep/<name>.md` with When to Load and Red Flags; add a pointer in `principles.md` |
| Recipe | `library/recipes/<name>.md` with When to Load, Steps, Gotchas, Verified; add `name: trigger` to `index.md` |
| Tool | Write `tests/<tool>.test.sh` first, then `bin/<tool>`; add it to the README tools table |

Preferred route for library content: `dev-learn`. It drafts on a branch in a separate worktree and needs approval to merge.

## 6. Testing
- Test first. Never weaken a test to get green.
- Suites use fake CLIs, so they cost nothing. Each runs alone: `tests/<name>.test.sh`.

| Suite | Covers |
|---|---|
| `install` | `install.sh` under a fake HOME |
| `learn` | The local learning inbox |
| `ledger` | Per-task ledgers |
| `lint-budget` | Lint fixtures, pass and fail cases |
| `parallel-sections` | Crash copies stay out of the repo tree while a scan runs |
| `reconcile` | Open-task and learning listing |
| `run` | Log plus short summary wrapper |
| `spawn` | Worker launch, caps, push guard, with a fake agent |
| `state` | `state.md` and `memory.md` rules |
| `stop-gate` | Parent Stop hook: blocks on unaccepted workers, budget, fail-open |
| `pstack-adoption` | Wiring of the pstack-derived skills and deep files |

### Parallel-safe suites
`tests/run-all.sh` runs suites concurrently (by default `min(cores, 4)` at once), so every suite must:
- make its own `mktemp -d` and write only there, never into the repo tree (`repo-tree-write` in `tests/pitfalls.test.sh`; a justified exception carries a `# repo-write-ok: <why>` tag);
- avoid process-wide `pkill`/`pgrep -f` without a marker only its own file contains, fixed ports, and a shared HOME or git config;

Knobs: `DEVKIT_TEST_JOBS=N` sets how many suites run at once (`1` runs serially, for debugging; invalid values exit 2). `DEVKIT_TEST_CORES=N` stands in for the detected core count (a test seam). The start order comes from `tests/run-all.weights` (`name seconds` per line, longest first); a suite not listed starts after those, in glob order, so listing a new slow suite is optional and only shortens the wall time.

Real-agent evals cost a few cents each. Run them after changing skills, `spawn` or the learning flow:
| Script | Checks |
|---|---|
| `evals/e2e.sh <claude\|codex\|opencode>` | Main agent opens two other agents in parallel |
| `evals/e2e-learn.sh <claude\|codex\|opencode>` | State, memory, closeout, and `dev-learn` stopping at the approval gate |

## 7. macOS bash 3.2 gotchas
- Empty arrays fail under `set -u`: expand as `${a[@]+"${a[@]}"}`.
- `awk` with `FNR==NR` breaks when the first file is empty.
- BSD awk has no `\b` and no `{n}` intervals.
- Piping an installer through `head` kills it (SIGPIPE).
- `sed -i` needs a suffix argument on macOS; avoid it or use a temp file.

## 8. Keep it public-safe
- Never commit secrets, tokens, keys, personal paths, emails or machine config.
- `.devkit/` stays ignored: ledgers and briefs hold paths and prompts.
- The lint fails on home paths, emails (except `example.com`) and secret-shaped strings.
- Build test fixtures for those patterns at runtime; never store them in files.

## 9. The learning loop
- Capture lessons in `state.md` as `- [ ] lesson | scope | ref`.
- `bin/learn queue` sends general and recipe ones to the local inbox.
- `dev-learn` turns them into library edits, only after approval.
- Do not paste generic advice into the library by hand.

## 10. Commits and pull requests
- Conventional messages (`fix(tests): ...`), small atomic commits.
- The author is the only contributor: no AI co-author or "generated with" lines.
- Ask before any push, and say whether to squash (recommend one commit for a small change).
- Never push to main without approval. A PR states a summary, risks and a test plan.
