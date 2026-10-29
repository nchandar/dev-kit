# Contributing

For people and AI agents. Goal: change the harness without breaking it. Overview and install: `README.md`.

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
| `bin/` | Tools: ledger, reconcile, spawn, state, learn, run, lint-budget |
| `tests/` | One script suite per tool, plus `run-all.sh` |
| `evals/` | Real-agent end-to-end checks (cost tokens) |
| `docs/` | `flow.svg` (the README animation) and `architecture.html` (animated walkthrough) |

## 3. The budgets
Enforced by `bin/lint-budget`:
| Cap | Limit |
|---|---|
| `AGENTS.md` size | 6144 B |
| Skill descriptions, total | 4096 B (each one line) |
| Skill file | 150 lines |
| Skill count | 4 to 6 |
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
| The task flow (stages or tools) | `docs/flow.svg` and `docs/architecture.html` |

## 5. Adding things
| Add | How |
|---|---|
| Skill | Max 6 total. Folder `skills/dev-<name>/`, one-line description, required sections, `library/state` closeout; add a route to `AGENTS.md` and a README entry |
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
| `reconcile` | Open-task and learning listing |
| `run` | Log plus short summary wrapper |
| `spawn` | Worker launch, caps, push guard, with a fake agent |
| `state` | `state.md` and `memory.md` rules |

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
- `.harness/` stays ignored: ledgers and briefs hold paths and prompts.
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
