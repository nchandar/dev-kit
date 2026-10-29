# state
Ledger: bin/ledger phase=state (when you refresh state.md or close out).

## When to Use
- At three checkpoints: after the grill, after each research round or slice, and at a pause. Then again at closeout. Not after every step: the ledger already records steps.

## Steps
Ask yourself one thing: what would a cold-start agent need to continue that the ledger rows and handoffs do not already say?
1. Edit `<task>/state.md` in place; rewrite, do not append. Sections: Findings, Decisions that shape direction, Direction (at most 3 lines), Open questions, Learnings.
2. Point, never copy. Every Findings, Decisions and Learnings bullet ends with a pointer: `L14` (ledger row), `handoffs/a.md:3`, `report.md`, a `path:line`, or a URL. If a ledger row already says it, give only the gist and the pointer, under 140 characters.
3. Do not restate the goal (link `spec.md`) or the next action (the ledger `next` row owns it).
4. Learnings: the moment you find something reusable, add `- [ ] lesson | scope: project|general|recipe | ref: pointer`. project means true only of this repo; general means an engineering lesson any project would want; recipe means a repeatable procedure with commands (build, deploy, setup).
5. Run `bin/state check` and fix what it reports.
Closeout, before `bin/ledger done`:
6. Final pass: drop stale Findings, keep Open questions honest.
7. Project learnings go into `.harness/memory.md` (Build and run, Gotchas, Architecture notes; at most 80 lines; each bullet a pointer or a `command`), then mark them `[x]`.
8. `bin/learn queue` sends general and recipe learnings to the local inbox. Tell the user "N learnings queued, run dev-learn". The shared library changes only with their approval.
9. A new session reads `.harness/memory.md` first; rewrite a line when you find it stale.

## Red Flags
- state.md turning into a diary. It is the current picture, not a log.
- A finding with no pointer, or text pasted from a handoff or a ledger row.
- Learnings left `[ ]` at closeout, or scope guessed: a project quirk filed as general.
- Secrets, tokens or personal paths in state.md or memory.md; they may be quoted into the library later.

## Verification
- `bin/state check` passes; `bin/reconcile <id>` shows the direction and the learning counts; no learning is left open at closeout.
