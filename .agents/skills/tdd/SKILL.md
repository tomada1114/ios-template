---
name: tdd
description: >
  Red-green-refactor workflow for this repository: write a failing Swift Testing
  test in MyAppCoreTests first, prove it fails, implement the minimum in
  MyAppCore to pass, then refactor and re-verify the coverage floor. Use
  PROACTIVELY when: implementing a feature, changing behavior, fixing a bug,
  adding logic, new function, new type, TDD, test-first.
---

# TDD Workflow

TDD is mandatory for all production Swift code (`docs/architecture.md` › Testing).
Never write implementation before a failing test exists.

## Step 0: Decide Where the Code Lives

- **Logic, state, view models** → `Packages/MyAppKit/Sources/MyAppCore` — this is
  the default. Core is coverage-gated, so code here is forced to stay tested.
- **Rendering only** → `Packages/MyAppKit/Sources/MyAppUI`, as a thin view over a
  Core view model. If a view needs an `if`, the condition belongs in Core.
- **Persistence or an OS service** → a `Sendable` port (protocol) in `MyAppCore` plus
  its adapter in `Packages/MyAppKit/Sources/MyAppPlatform` (SwiftData, UserNotifications,
  …). Test the Core side against the port's fake in `Tests/MyAppTestSupport`
  (`docs/architecture.md` › Testing); the adapter itself is translation only and sits
  outside the coverage floor, so anything it would need a test for belongs in Core
  instead. Whether the framework really behaves as the adapter assumes is the port's
  contract function run against the adapter in `Tests/MyAppPlatformTests` — under
  `just test` when the framework runs on the host (SwiftData with an in-memory store
  does), otherwise on a simulator or device and reported in the PR. It is evidence for
  the adapter, never the red test this loop starts from.
- If you are about to put logic in `MyAppUI`, `MyAppPlatform`, or `App/`, stop and move
  it to Core.

## Step 1: RED — Write the Failing Test First

Add the test to `Packages/MyAppKit/Tests/MyAppCoreTests` using Swift Testing:

- `@Test` functions inside a `@Suite`; `@MainActor` on suites touching view models
- `#expect` / `#require`; error paths assert the thrown error's **payload**
  with `#expect(throws:)`, not just its type
- Use `@Test(arguments:)` instead of copy-pasted variations
- Cover the edge-case checklist: boundaries (at / just inside / just outside),
  repeated operations, both branches of every conditional

## Step 2: Prove It Fails

```bash
cd Packages/MyAppKit && swift test
```

Confirm the new test fails (a compile error for a not-yet-existing symbol counts).
**Do not skip this run** — a test that has never failed proves nothing.

## Step 3: GREEN — Implement the Minimum

Write the smallest implementation in `MyAppCore` that makes the test pass.
Follow `docs/architecture.md`: typed errors, no force-unwrap/`try!`, value
types first, `///` docs on public API.

```bash
cd Packages/MyAppKit && swift test
```

All tests must pass — the new ones and every existing one.

## Step 4: REFACTOR — With the Gate On

Clean up (naming, extraction, dead code) while tests stay green, then run the
full local gate including the coverage floor:

```bash
just check   # verify-hooks → fmt → lint → test-scripts → check-harness → test → build
```

If coverage dropped below the floor, write more tests for the code you added —
NEVER lower the floor, exclude paths, or move logic out of Core to dodge it.

## Step 5: Commit

Tests and their implementation land in the **same commit** (**REQUIRED:**
`smart-commit`). Red tests are never committed alone.

## Anti-patterns (hard prohibitions)

- Implementation first, tests "later"
- Weakening an assertion to make a test pass — fix the code
- Testing implementation details instead of behavior and contracts
- `sleep`-based assertions or order-dependent tests
- Skipping Step 2 because the failure "is obvious"
