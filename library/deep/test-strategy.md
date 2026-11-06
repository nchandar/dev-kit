# test-strategy

## When to Load
- Designing the test suite for a new feature or module, or deciding what level a test belongs at.
- A suite is slow, flaky, brittle on refactors, or full of mocks.

## Pattern
1. Many small tests, fewer medium, very few end-to-end. Small = one process, no network, no disk, no sleeps: milliseconds, so they run on every change. Medium = real DB or local service. Large = whole system. Each step up is slower and fails for more reasons, so push every check to the lowest level that can catch it.
2. Test what callers can observe: return values, persisted state, emitted output. Do not assert that method X was called; that locks in how, not what, and breaks on harmless refactors.
3. Prefer real code, then fakes, then stubs, then mocks. A mock only proves your guess about a dependency.
4. Mock at system boundaries only: network, clock, randomness, third-party APIs, sometimes the filesystem. Never mock your own modules or pure logic.
5. Test what you own and what can break: branches, edge cases (empty, zero, max, bad input), error paths. Skip trivial getters, framework behavior, and third-party code. Coverage is a hint, not a goal.
6. Name each test as a spec line: "rejects an empty title", not "test1" or "validateTitle works". A failing name should say what broke.
7. Keep tests DAMP, not DRY: each test shows its own setup and expected value in full, so the reader needs no helper hunt. Share only noise (a builder with sane defaults), and override just the fields the test cares about.
8. Use literal expected values, never ones recomputed with the code's own logic.
9. Isolate: each test builds and cleans its own state; no order dependence.
10. Flaky test policy: a flake is a bug. Quarantine it the same day, with the user's approval, an owner and a ledger row, find the cause (shared state, real clock, async race, ordering), fix or delete. Never retry-until-green; it hides real races.
11. A never-happens assertion (no charge, no email, no call) needs a twin case where it does happen; otherwise the test cannot see the call.
12. What a mocked external service receives is behavior; assert the payload against the requirement, not against a value the code computed.
13. Tests and evals that read local state (inbox, home dir, env) set their own state dir, so real data cannot leak in.
14. Agent-eval assertions check properties (route named, footer present), not exact outcomes; never loosen a property to pass.

## Red Flags
- Mocks of internal classes, or assertions on call counts.
- Snapshots nobody reads; permanent skips.
- A giant shared fixture that every test mutates.
- Unit tests green while the app breaks: too few integration checks.
- Tests that sleep to wait for async work.

Source: agent-skills/test-driven-development
