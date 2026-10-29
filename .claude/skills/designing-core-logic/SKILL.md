---
name: designing-core-logic
description: >
  Covers how logic in MyAppCore is shaped: time, the current date, identifiers, Locale,
  and randomness injected rather than read (Clock, any Clock<Duration>, Date(), UUID(),
  Locale.current, SystemRandomNumberGenerator), tunable numbers gathered in one Tuning
  type, action-shaped methods on @MainActor @Observable view models, reentrancy after an
  await, AppModel and the composition root in App/, why the code is split into Core, UI,
  and Platform, and the patterns this template deliberately does not adopt. Use when
  adding a type, a view model, a timer, a debounce, a delay, a formatted string, a
  threshold, or anything random to MyAppCore, wiring a view model into AppModel, or when
  reaching for a coordinator, a use-case class, a DI container, a reducer, or an event
  bus.
---

# Designing Core Logic

**Owns:** how a type or view model in `MyAppCore` is shaped so its logic stays
deterministic under `swift test` — what it is handed rather than reads, where tunable
numbers live, what its entry points look like, and which patterns are not adopted.
**Does not own:** the test-first loop itself (`tdd`); error types and `throws`
(`designing-errors`); storage behind a port — the repository, SwiftData, and
preferences (`persisting-data`); an OS service or the HTTP client behind a port
(`integrating-system-apis`); the module boundaries and import rules
(`AGENTS.md` › Architecture, `.claude/rules/swift.md`).

## Why this exists

The 80% coverage floor on `MyAppCore` only means something if a test can reach every
branch without waiting, without depending on the machine's clock, language, or luck.
Anything Core would read from the world — the time, a fresh identifier, the locale, a
random number — is therefore an input, the same way `TodoListViewModel` is handed an
`any TodoRepository` instead of opening a store.

These are standard-library and Foundation values, not OS integrations, so they are
injected as plain parameters. They do not need a port in `MyAppPlatform`; add a port
only when the answer really comes from a framework Core may not import.

## Inject time

- **Waiting** (a delay, a debounce, a timeout, a periodic tick): take a clock, not
  `Task.sleep(for:)` against the real one. `platforms: [.iOS(.v27), .macOS(.v27)]` in
  the local package's `Package.swift` makes `Clock`, `ContinuousClock`, and
  `SuspendingClock` available without an availability check: they arrived in iOS 16.0
  and macOS 13.0 (<https://developer.apple.com/documentation/swift/clock>, checked
  2026-09-30).

  ```swift
  @MainActor @Observable
  public final class AutosaveViewModel {
      private let clock: any Clock<Duration>
      private let tuning: Tuning

      public init(clock: any Clock<Duration> = ContinuousClock(), tuning: Tuning = .default) {
          self.clock = clock
          self.tuning = tuning
      }

      public func textChanged() async throws {
          try await clock.sleep(for: tuning.autosaveDelay)
          // ...
      }
  }
  ```

  Use a generic `C: Clock` parameter instead of `any Clock<Duration>` only when a
  profiler shows the existential matters; the existential keeps the type's signature
  readable.
- **"Now"** (a timestamp, "is this older than a day", a date to format): a long-lived
  view model takes `now: @Sendable () -> Date` defaulting to `{ Date() }`, as
  `TodoListViewModel.init` does; a pure function over a value takes the `Date` as an
  argument (`TodoItem`'s initializer takes `createdAt`). Never call `Date()` or
  `Date.now` inside a branch.
- **Identity** travels the same way: `TodoListViewModel` takes
  `makeID: @Sendable () -> UUID`, so a test knows the identifier a new item will get.
- **Calendar and time zone** travel with "now": take a `Calendar` (which carries its
  `timeZone`) rather than reading `Calendar.current`, because "today" depends on it.
- **Tests:** pass fixed values — `TodoListViewModelFixture` pins `now` and `makeID` —
  and a `Calendar(identifier: .gregorian)` with an explicit `TimeZone(identifier: "UTC")`.
  For a clock, the test target defines its own manually advanced `Clock` (the standard
  library ships none); keep it in `Tests/`, never in `Sources/`. Passing a zero
  `Duration` through `Tuning` is often enough and needs no fake clock at all.

## Inject locale

- Anything that formats or compares human-facing text — a number, a date, a
  case-insensitive sort, a plural — takes a `Locale` (default `.current` at the
  composition root or the initializer's default argument), and passes it on explicitly:
  `value.formatted(.number.locale(locale))`, `date.formatted(.dateTime.locale(locale))`.
- Keep the user-visible *wording* in Core where the coverage floor sees it, as a
  `LocalizedStringResource` like `TodoListStrings` and `TodoListFailure.message`; the
  view only renders it (`localizing-the-app`).
- **Tests:** `Locale(identifier: "en_US_POSIX")` for a stable expected string, plus a
  second locale (`"de_DE"`, `"ja_JP"`) when the behavior under test *is* the
  localization.

## Inject randomness

- Take the generator as a parameter: a method that draws takes
  `using generator: inout some RandomNumberGenerator`, mirroring the standard library's
  own `shuffled(using:)` and `Int.random(in:using:)`. A `@MainActor` view model that owns
  one stores it as `private var generator: any RandomNumberGenerator`, defaulting to
  `SystemRandomNumberGenerator()`; the actor isolation already keeps it race-free.
- **Tests:** Swift's standard library has no seeded generator, so the test target
  defines one — a few lines of SplitMix64 conforming to `RandomNumberGenerator` — and
  asserts on the exact sequence a given seed produces. It lives in `Tests/`; shipping
  code never needs it.

## One `Tuning` type

The template has no tunable yet, so there is no `Tuning` type to copy; the first number
an app wants to tweak creates it, in this shape:

- Every number someone might want to tweak — a delay, a threshold, a limit, a retry
  count — lives in one `public struct Tuning: Sendable, Equatable` in `MyAppCore` with a
  `` static let `default` `` (the backticks are required: `default` is a keyword), never
  as a literal scattered through method bodies.
- Types take a `Tuning` in their initializer (defaulting to `.default`), so a test
  passes a tiny delay or a low limit to reach a boundary quickly.
- Durations are `Duration`, not `TimeInterval`; counts are `Int`. A doc comment on each
  property says why it has that value.
- A domain *invariant* is not a tunable: `TodoItem.normalizedTitle(_:)`'s rule that a
  title is never blank is part of what the type means, enforced by its throwing
  initializer, not a `Tuning` entry. The test: would changing it be a product tweak
  (Tuning) or change what the type means (a parameter or a constant)?
- Split `Tuning` into nested structs by feature once it grows past a screenful; keep it
  one root type so there is one place to look.

## Action-shaped view models

- A view model is `@MainActor @Observable public final class`, importing `Observation`
  and, for its wording, `Foundation` (`TodoListViewModel`). It is the one place a view
  reads state from and sends intent to.
- State is `public private(set) var`; derived state is a computed property (`canAdd`,
  `showsEmptyState`). The only settable property is what a control binds to
  (`draftTitle`). A view never mutates state directly.
- Entry points are **actions named for what the user did or the app saw**: `load()`,
  `addDraft()`, `toggle(_:)`, `delete(atOffsets:)` — not setters, and not a generic
  `send(_ action:)` reducer. Each action is a method a test can call and then assert on
  the resulting state.
- An action that waits is `async` and the view calls it from `.task` or `Task { }`;
  the view model does not spawn untracked tasks from an initializer. Construction has
  no side effects (see `TodoListViewModel.init`: nothing is read until `load()`) —
  which is also what lets a re-render build a pushed screen's model and discard it.
- **Who builds a view model:** `AppModel`, never a view or `App/`. A model every scene
  shares is an `AppModel` stored property built in its initializer from the ports `App/`
  passes (`todoList`); a pushed screen's own model is built by a named
  `make…ViewModel(…)` method, one per route that needs it
  (`makeTodoDetailViewModel(id:)`). A screen that shows what a shared model holds takes
  that model, not a copy of the value — `TodoDetailViewModel` holds the list and an
  identifier — so both screens show one state. `AppModelTests` builds each route's
  model over the fakes. Ownership, reentrancy after an `await`, and the composition
  root: **REQUIRED:** [references/view-models.md](references/view-models.md).
- Domain rules live in value types (`TodoItem`) that the view model holds and delegates
  to; the view model translates between them and what the view shows.

## Deliberately not adopted

Each row is a pattern an implementer may reach for out of habit, with the reason it is
not used here. The reasoning behind the layers themselves — the package split, MVVM, no
dependencies — is **BACKGROUND:** [references/design-reasons.md](references/design-reasons.md).

| Pattern | Why not |
|---|---|
| A third-party architecture framework (TCA, a Redux store, an MVVM kit) | Zero dependencies; `@Observable` plus actions already gives testable state |
| A generic `send(_ action:)` reducer on every view model | Methods are discoverable, typed, and testable one at a time |
| Use-case / interactor classes, presenters, per-layer DTOs | The view model's action *is* the use case; copies between layers add no consumer |
| A repository or protocol per type "for testability" | A port exists only where a storage or OS boundary does (`TodoRepository`); a pure rule (`TodoItem`) is tested directly |
| A dependency-injection container or service locator | `App/` hands the ports to `AppModel`'s initializer, and `AppModel` builds each model by a named method — no registry, no lookup by type, no global |
| Coordinators / routers as separate objects | SwiftUI's own navigation state, owned by a view model, suffices at this size |
| An event bus or `NotificationCenter` between Core types | Direct calls; an OS notification is observed through a port instead |

An app cut from this template that adopts one of these rewrites its row here (and the
matching entry in `references/design-reasons.md`, if it has one) in the same pull
request, stating in the present tense the problem the current shape could not solve and
why the pattern now holds (`AGENTS.md` › Before changing the architecture).
