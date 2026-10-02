---
paths:
  - "Packages/**/Tests/**"
  - "LaunchUITests/**"
---

## Where a Test Goes

Four kinds of test, split by what is under test (`docs/architecture.md` › Testing):

1. **A decision → a Core test with the fake.** Anything that branches, clamps, formats,
   orders, or remembers lives in `MyAppCore` and is tested in `Tests/MyAppCoreTests`
   against the port's fake, `InMemoryTodoRepository` (see "Fakes, not mocks" below).
   These run under `just test` and in CI's `test` job on every push, and are what the 80%
   line- and 75% function-coverage floors measure. This is the default: if an adapter
   looks like it needs a test for a decision, move the decision into Core instead.
2. **Translation over a framework that runs on the host → a Platform test under plain
   `swift test`.** SwiftData and Foundation run on the host Mac, so an adapter over them
   is tested in `Tests/MyAppPlatformTests`, run by `just test` and CI's `test` job like
   any other suite — SwiftData with an in-memory store (`.inMemory`), never the on-disk
   one; a test that must reopen a store uses `.file(URL)` in its own temporary directory
   (Hygiene, below). There is no opt-in trait and no separate human-run recipe here: a
   Platform test is a gated test.
3. **Translation through an iOS-only API → a test inside `#if os(iOS)` in
   `Tests/MyAppPlatformTests`.** `swift test` builds the package for macOS, where that
   test compiles away; `just test-ios` runs it on the iOS Simulator (CI's
   `Package Tests (iOS Simulator)` job). What only a real permission prompt, a
   device, or push delivery shows is not a test at all: the pull request carries the
   evidence (a screenshot, the log lines from `just logs`).
4. **What only the assembled app shows → `LaunchUITests`.** The one XCTest target holds
   the launch guarantee: the app starts on the iOS Simulator, shows its list, and the
   core interaction — adding an item — round-trips through `App/`'s real wiring
   (`LaunchTests.swift`). It launches the app with `-uiTesting`, which opens an in-memory
   store, so every run starts empty. A new test belongs there only when what it proves
   is that wiring — scene lifecycle, the composition root handing over the real adapter —
   and nothing smaller can fail for it. A decision is a Core test, a view is covered
   through its Core view model, and an adapter's translation is a Platform test. It
   waits on a predicate with a timeout (`waitForExistence(timeout:)`), never `sleep`.

A test of kind 3 never becomes the only test of a decision: only `just test-ios` runs
it — `just check` leaves that recipe out, and the coverage floor never measures it — so
a decision it alone covers is untested on every local run. Adapters stay
translation-only, and outside the coverage floor, precisely so that stays true.

## Framework and Structure

- Swift Testing only (`@Test`, `#expect`, `#require`, `@Suite`); XCTest is reserved for the
  XCUITest launch target in `LaunchUITests/`
- Test names are backticked sentences (`` func `load publishes the stored items in display order`() ``)
- Use `@Test(arguments:)` for input/output variations; don't copy-paste test bodies
- Group related tests in a `@Suite`; annotate `@MainActor` suites that touch view models
- Shared values and builders for one subject's suites go in one fixture enum beside them
  — `TodoListViewModelFixture` is the worked example: fixed dates and identifiers, and a
  view model whose clock and identifier source are pinned
- TDD is required: write the failing test first, then implement to green (the `tdd` skill)
- A Core test uses plain `import MyAppCore`, never `@testable import`: it exercises the
  public API the rest of the app calls, so an internal can be renamed without touching a
  test. A test that seems to need an internal is either testing a detail (test the
  behavior it produces) or has found a declaration another module legitimately needs —
  make that `package`, which every target in `Packages/MyAppKit` sees (`swift.md` ›
  Access Control)

## What to Test

- Test *behavior and contracts*, not implementation details
- Always test the happy path AND the error path for every public API
- Error-path tests assert the thrown error's payload with `#expect(throws:)`, not just its
  type — `TodoRepositoryError.corruptedRecord(item.id)`, not any `TodoRepositoryError`

## An Independent Oracle

The expected value comes from somewhere other than the code under test: a literal worked
out by hand, a case table in `@Test(arguments:)` pairing each input with its answer, or
an invariant that must hold whatever the input (a round-trip through the repository
returns what went in). Never compute it by calling the implementation, and never
re-derive it with the implementation's own formula: after loading items created at
minute 2 and minute 1, `#expect(model.items == stored.sorted(by: TodoItem.isOrderedBefore))`
passes with any bug `isOrderedBefore` has, where `#expect(model.items == [first, second])`
does not.

## Fakes, not mocks

A port declared in `MyAppCore` (a `Sendable` protocol whose adapter lives in
`MyAppPlatform`) is substituted in tests by a **fake**, never a mock. A fake is a real,
working implementation of the protocol that lives in `Tests/MyAppTestSupport`, answers
from data the test hands it, and records what it was asked in a plain value — the calls
it received — which the test reads afterwards with `#expect`. It declares no
expectations up front, verifies nothing itself, and needs no framework:
`InMemoryTodoRepository` is the worked example to copy — `fail(_:with:)` to make an
operation throw, `calls` and `snapshot` to read what happened, `onSave(_:)` and
`onFetch(_:)` to act while a save or a fetch is in flight. It is `package`, not
`public`, and matches its port's shape — an
actor for an async port (`InMemoryTodoRepository`), a final class over a `Mutex` for a
synchronous one (`InMemoryPreferences`) — so it is `Sendable` the honest way, never
`@unchecked Sendable`. Every test of a given port
uses that one fake, so the port's test-time behavior is defined in one place rather than
re-stubbed per test. Asserting on the recorded calls is for the cases where *asking* is
the behavior (not asking the repository before `load()`); otherwise assert on the state
the answer produced, not on the interaction that produced it.

## One Contract Suite per Port

A fake stands in for the adapter only while both keep the port's promises, so those
promises are asserted once, against both. The contract suite is a function over the
protocol, not over either implementation, and every clause it checks is one the port's
`///` states (add the clause there first). `TodoRepository` is the worked example
(`docs/architecture.md` › Repositories):

- The fakes and one contract function per port live in the `MyAppTestSupport` target
  (`Tests/MyAppTestSupport`), which both test targets depend on — never one test target
  depending on another. It is test code: no product exports it, and
  `ArchitectureBoundaryTests` fails if a shipped module imports it.
- `TodoRepositoryContract.check(_:)` takes `some TodoRepository` that starts empty and
  asserts with `#expect` every promise the port states: ordering, save as insert or
  replace, delete, and `notFound` for a missing identifier. Its `violations(of:)` returns
  what `check(_:)` asserts on, so a Core test hands it an implementation that breaks a
  clause and sees the contract report it — the proof the contract is not vacuous.
- `MyAppCoreTests/TodoRepositoryContractTests.swift` runs it against
  `InMemoryTodoRepository`, and against the deliberately broken implementations: CI runs
  it, so the fake cannot drift from the port.
- `MyAppPlatformTests/SwiftDataTodoRepositoryTests.swift` runs the same function against
  `SwiftDataTodoRepository` with an in-memory store, beside the adapter-only cases, under
  `just test` and in CI.

## Edge Cases (always consider these)

- **Boundary values**: values at, just inside, and just outside every bound (an empty or
  whitespace-only title)
- **Repeated operations**: idempotence and repeats (toggle twice, delete what is already
  gone, a double tap on Add)
- **State transitions**: initial state, after one operation, after error recovery (a
  failed load, then a retry)
- **Reentrancy**: a `@MainActor` method that `await`s can be re-entered before it
  resumes — drive the interleaving through the fake's `onSave(_:)`
  or `onFetch(_:)` (`docs/architecture.md` › View models)
- **Both branches** of every conditional in Core (the coverage floors measure lines and functions, not branches, so they will not notice a missed one — write the test for each branch yourself)

## Hygiene

- Tests are independent: no shared mutable state, no ordering assumptions — Swift Testing
  runs them in parallel by default
- No `sleep` or timing-based assertion in a unit test; that flakiness belongs to no one.
  When time must pass, the type under test takes its time as a parameter (`now:`, a
  `Clock`, a delay — the `designing-core-logic` skill), and the test hands it a pinned
  value, a zero `Duration`, or a manually advanced test clock — never `Task.sleep` to
  wait for something to happen
- A test that touches the file system gets its own directory:
  `FileManager.default.temporaryDirectory.appending(path: "MyAppTests-\(UUID().uuidString)")`,
  created in the test and removed in a `defer`. Never a fixed shared path, the checkout,
  or the home directory — parallel tests would collide, and a leftover file changes the
  next run
- NEVER weaken an assertion to make a test pass — fix the code
