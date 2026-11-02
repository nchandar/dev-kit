---
name: dev-mode
description: Entry point for any request: triage type and size, announce the route, chain the dev-* loops, stay on route, close with one answer.
---
# dev-mode

Hard rules (read first):
1. Stay on the route until it closes. A question asked mid-route is answered inside the route. Leaving needs one stated reason: "leaving <skill> because ...".
2. Gates are the only pauses: an unclear requirement (library/grill), a push or PR, a destructive command, an unresolved doubt. Everything else keeps going.
3. Every reply during a route, even to an off-topic question, ends with this exact lowercase footer: `route: <skill>, step N/M, next: <step>`.

Tools and library: `~/.agents/dev-kit`. One ledger task per route (`bin/ledger start <slug>`, `DEVKIT_TASK=<id>`).

## When to Use
- Any request you want carried through the right loop to a final answer.
- Not inside a dev-spawn worker (`DEVKIT_DEPTH` set).
- Your instructions outrank this skill; this skill outranks defaults.

## Checklist
- [ ] 1. Triage, size first: trivial (chat, a one-line edit or config value, running tests or a command) means type none; otherwise standard, or large (unknowns remain: dev-research first). Type: bug or failing test -> dev-debug; new behavior or refactor -> dev-feature; question or spike -> dev-research; review -> dev-review; delegate -> dev-spawn; queued learnings -> dev-learn.
- [ ] 2. Announce one line: `route: <skill>, <size>`, then `bin/ledger mode <skill> "<size>"`. Trivial or none: announce `route: none`, do it directly, no ledger.
- [ ] 3. Mixed request: split it, one task per route, order research, debug, feature; review last.
- [ ] 4. Run the route: invoke its skill. The route owns its checklist and ledger; do not copy or restate it here.
- [ ] 5. Chain. research -> dev-feature when the report has a Build handoff and you agree. feature -> dev-review. debug -> dev-review after the fix. debug -> dev-research after 3 failed hypotheses. Bulk work -> dev-spawn.
- [ ] 6. Close: result, evidence, open risks, next step. Then `bin/ledger done "<summary>"` per task; follow library/state.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "Just a quick question" | Answer it inside the route, then restate the next step. |
| "The footer is noise" | The footer is how drift is seen; no footer means off route. |
| "Obvious route, skip the announce" | The announce is the commitment step. |

## Red Flags
- No footer on a reply during a route; a new route with no stated reason.
- A route's checklist copied into this one.

## Verification
- A `mode` row per route and a `done` row per task; the final answer lists result, evidence, open risks.
- `evals/route.sh` passes its bars (23/25 routing, 5/6 drift).
- Close the ledger: `bin/ledger done "<summary>"`, or a `next` row with the first runnable step if work remains.
