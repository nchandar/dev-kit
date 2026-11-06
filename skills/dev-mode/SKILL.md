---
name: dev-mode
description: Entry point for any request: triage type and size, announce the route, hand off to its playbook, stay on route, close with one answer.
---
# dev-mode

Hard rules (read first):
1. Stay on the route until it closes. Answer mid-route questions inside the route. Leaving needs one stated reason: "leaving <skill> because ...".
2. Only gates pause: an unclear requirement (library/grill), a push or PR, a destructive command, an unresolved doubt.
3. Every reply during a route, even to an off-topic question, ends with this exact lowercase footer: `route: <skill>, step N/M, next: <step>`.

One ledger task per route (`bin/ledger start <slug>`). Playbooks own their steps.

## When to Use
- Any request, except inside a dev-spawn worker (`DEVKIT_DEPTH` set).
- Your instructions outrank this skill; it outranks defaults.

## Checklist
- [ ] 1. Triage, size first: trivial (chat, a one-line edit, running a command; delegation is never trivial) means type none; else standard, or large (unknowns: dev-research first). Type: bug or failing test -> dev-debug; new behavior -> dev-feature; structure-only -> dev-refactor; question or spike -> dev-research; skill or prompt change -> dev-eval; review -> dev-review; delegate -> dev-spawn; queued learnings -> dev-learn. Status ask: ketchup, no route. Vague: library/grill first (sharpen).
- [ ] 2. Announce `route: <skill>, <size>`, then `bin/ledger mode <skill> "<size>"`. Trivial or none: `route: none`, do it, no ledger.
- [ ] 3. Mixed request: one task per route, order research, debug, feature; review last.
- [ ] 4. Read skills/dev-<route>/SKILL.md by path; pass it route, size, request. Do not copy its steps.
- [ ] 5. Follow its Hand off to line.
- [ ] 6. Close with its Reply line (library/deep/ketchup, library/deep/writing). Then `bin/ledger done "<summary>"` per task; follow library/state.

## Rationalizations
| Excuse | Rebuttal |
|---|---|
| "The footer is noise" | No footer means off route. |

## Red Flags
- No footer mid-route; a new route with no stated reason.

## Verification
- A `mode` row per route, a `done` row per task; the answer has result, evidence, open risks.
- `evals/route.sh` meets its bars (29/31 routing, 5/6 drift).
