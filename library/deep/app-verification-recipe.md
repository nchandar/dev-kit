# app-verification-recipe

## When to Load
- A repo has a user-facing surface (web, mobile, CLI, API) and no recorded way to drive it.

## Pattern
1. Learn from the repo, not the user: surface, start command, ports, env, seed data, existing Playwright/Cypress specs.
2. Write .devkit/verify-<app>.md (local, git-ignored) with five parts: Launch, Doctor, Drive, Evidence, Cleanup.
3. Launch: exact command; ready = a usable page or prompt, from an empty data dir. Doctor: one read-only check (process up, right build, port is ours).
4. Drive: real selectors/commands (ARIA labels, data-attributes, routes), not coordinates; use the user path, never test-only endpoints.
5. Evidence: action AND resulting state (screenshot, response body, console log, exit code); store outside the teardown path.
6. Cleanup: stop only what you started; never kill by process name; keep the evidence.
7. Run the recipe once on one feature before relying on it. List 3-5 features as follow-ups.

## Red Flags
- Driving the app through test-only endpoints or screen coordinates.
- Evidence stored where cleanup deletes it.
