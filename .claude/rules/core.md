---
paths:
  - "Packages/**/Sources/MyAppCore/**"
  - "Packages/**/Tests/MyAppCoreTests/**"
---

# MyAppCore

Core holds every decision the app makes, because it is the one module the coverage floor
measures. Everything here serves that: a test must reach every branch without waiting,
and without depending on the machine's clock, language, or luck. Core may import
`Foundation`, `Observation`, and `os` (logging is neither UI nor OS integration); the
banned modules are listed in `AGENTS.md` › Architecture.

## Test first

- A behavior change in Core starts with a failing Swift Testing test in
  `Tests/MyAppCoreTests`. Run `just test-fast <SuiteName>` and see it fail (a compile
  error for a symbol that does not exist yet counts): a test that has never failed
  proves nothing, however obvious the failure seems.
- Write the smallest implementation that passes, rerun `just test-fast`, then refactor
  while it stays green. Finish with `just test`: `test-fast` skips the 80% line / 75%
  function floors, which only `just test` enforces.
- Below a floor, add tests for the code you added. Never lower the floor, exclude a
  path, or move logic out of Core to dodge it.
- The test and its implementation land in the same commit; a red test is never
  committed alone.
- A Core test uses plain `import MyAppCore`, never `@testable import`: it exercises the
  API the rest of the app calls, so an internal can be renamed without touching a test.
  A test that seems to need an internal is testing a detail (test the behavior it
  produces) or has found a declaration another module needs — make that `package`
  (`swift.md` › Access Control).
- Logic that wants to live in `MyAppUI`, `MyAppPlatform`, or `App/` belongs here
  instead: if a view needs an `if`, or an adapter seems to need a test for a decision,
  the condition moves into Core. An adapter's contract run is evidence for the adapter,
  never the red test this loop starts from.

## Inject what Core would read from the world

These are standard-library and Foundation values, so they are plain parameters, not
ports. A port exists only when the answer comes from a framework Core may not import.

- **Waiting** (a delay, debounce, timeout, tick): take `any Clock<Duration>` defaulting
  to `ContinuousClock()` and call `clock.sleep(for:)`, never `Task.sleep` against the
  real clock (`RetryingAPIClient`'s backoff wait). A generic `C: Clock` only when a
  profiler shows the existential matters.
- **Now:** a long-lived view model takes `now: @Sendable () -> Date` defaulting to
  `{ Date() }` (`TodoListViewModel.init`); a pure function takes the `Date` as an
  argument (`TodoItem`'s `createdAt`). Never `Date()` or `Date.now` inside a branch.
- **Identity:** `makeID: @Sendable () -> UUID`, so a test knows the identifier a new
  item gets.
- **Calendar and time zone** travel with now: take a `Calendar` (it carries its
  `timeZone`), because "today" depends on it.
- **Locale:** anything that formats or compares human-facing text takes a `Locale`
  (default `.current` at the initializer) and passes it on explicitly —
  `value.formatted(.number.locale(locale))`.
- **Randomness:** a method that draws takes `using generator: inout some
  RandomNumberGenerator`, as `shuffled(using:)` does
  (`RetryPolicy.delay(afterAttempt:using:)`'s jitter); a `@MainActor` view model that
  owns one stores `any RandomNumberGenerator`, defaulting to
  `SystemRandomNumberGenerator()`, and an actor that owns one stores
  `any RandomNumberGenerator & Sendable` (`RetryingAPIClient`).
- **In tests:** pinned values (`TodoListViewModelFixture` pins `now` and `makeID`),
  `Calendar(identifier: .gregorian)` with `TimeZone(identifier: "UTC")`,
  `Locale(identifier: "en_US_POSIX")` plus a second locale when localization is the
  behavior under test. The standard library ships no test clock and no seeded
  generator, so a manually advanced `Clock` (`ManualClock`) and a SplitMix64 generator
  (`SplitMix64`) live in `Tests/MyAppTestSupport`, never `Sources/`. A test starts the
  work in a `Task`, awaits `clock.nextSleep()` — which returns once the code under test
  is parked in a sleep, with no polling — then advances the clock or cancels the task;
  a suite that does so carries `.timeLimit`, since a wait that never comes would
  otherwise hang. The `RetryPolicy…Tests` suites are the worked example. A zero
  `Duration` through `Tuning` often needs no clock.

## One `Tuning` type

The first number an app wants to tweak — a delay, threshold, limit, retry count —
creates one `public struct Tuning: Sendable, Equatable` in Core with a
`` static let `default` ``; no tunable is a literal in a method body. Types take a
`Tuning` in their initializer (default `.default`) so a test reaches a boundary
quickly. Durations are `Duration`, counts `Int`, and each property's `///` says why it
has that value: `Tuning.retry`, the `RetryPolicy` that `RetryingAPIClient` takes, is
the worked example. A domain invariant is not a tunable (`TodoItem.normalizedTitle(_:)`'s
non-blank rule is what the type means): ask whether changing it is a product tweak or
changes the type's meaning. Past a screenful, nest structs by feature under the one
root type.

## View models

- `@MainActor @Observable public final class`, importing `Observation` and `Foundation`
  (`TodoListViewModel`). State is `public private(set) var`; derived state is computed
  (`canAdd`, `showsEmptyState`); the only settable property is what a control binds to
  (`draftTitle`).
- Entry points are actions named for what the user did or the app saw — `load()`,
  `addDraft()`, `toggle(_:)`, `delete(atOffsets:)` — not setters and not a generic
  `send(_:)`, so a test calls one and asserts the resulting state.
- An action that waits is `async`; the view calls it from `.task` or `Task { }`.
  Construction has no side effects and spawns no task (nothing is read until
  `load()`), which is also what lets a re-render build and discard a pushed screen's
  model.
- `AppModel` builds every view model, never a view or `App/`: a model every scene
  shares is a stored property built from the ports `App/` passes (`todoList`); a pushed
  screen's model comes from one `make…ViewModel(…)` per route
  (`makeTodoDetailViewModel(id:)`). A screen showing what a shared model holds takes
  that model plus an identifier, not a copy, so both screens show one state.
  `AppModelTests` builds each route's model over the fakes.
- Domain rules live in value types (`TodoItem`) the view model delegates to.
- Why, reentrancy after an `await`, and the composition root: the `designing-core-logic`
  skill's `references/view-models.md`.

## Deliberately not adopted

| Pattern | Why not |
|---|---|
| An architecture framework (TCA, a Redux store, an MVVM kit) | Zero dependencies; `@Observable` plus actions already gives testable state |
| A generic `send(_ action:)` reducer | Methods are discoverable, typed, and testable one at a time |
| Use-case or interactor classes, presenters, per-layer DTOs | The action is the use case; copies between layers have no consumer |
| A protocol per type "for testability" | A port exists only at a storage or OS boundary; a pure rule is tested directly |
| A DI container or service locator | `App/` hands ports to `AppModel`, which builds each model by a named method |
| Coordinators or routers | SwiftUI navigation state, owned by Core's `NavigationModel`, suffices at this size |
| An event bus or `NotificationCenter` between Core types | Direct calls; an OS notification is observed through a port |

The reasoning behind the layers themselves is the `designing-core-logic` skill's
`references/design-reasons.md`. An app that adopts one of these rewrites its row here
(and that file's entry, if it has one) in the same pull request, saying what the current
shape could not solve (`AGENTS.md` › Before changing the architecture).

## Errors

- Every error a caller can observe is declared in Core beside the port or model that
  throws it (`TodoRepositoryError` in `TodoRepository.swift`): view models switch on it
  and the fake throws it, so it cannot live in Platform.
- One `enum` per failure domain, `Error, Equatable, Sendable`, with cases named for what
  the caller learns (`.notFound`, `.storageFailure`), not which API failed. Payloads are
  `Sendable` values a caller decides on — identifiers, small enums, durations — never an
  `NSError` or `any Error`, which are not `Equatable`, often not `Sendable`, and leak the
  adapter's mechanism.
- No user content in a payload: no titles, typed text, paths, or URLs. Errors travel
  into logs, crash reports, and test output; `TodoRepositoryError` carries an
  identifier, never a title. Log once, where the error is handled, with the privacy
  rules in `swift.md` › Logging.
- `throws(E)` when the caller decides by `E`'s cases (a port, an action with per-case
  recovery): the `catch` is exhaustive and a new case breaks every caller that must
  handle it. Plain `throws` when the caller only propagates or reports, or the body
  calls throwing APIs of unrelated types. Never a catch-all case like
  `.unknown(any Error)` to make a typed throw compile.
- An empty result is not a failure (`fetchAll()` returns `[]`). Absence throws only where
  the port promises the caller must hear about it: `delete(id:)` reports `.notFound` so a
  stale caller finds out, and `TodoListViewModel.delete(_:)` then treats it as harmless.
- Each case has an error-path test (`testing.md` › What to Test); a Core test makes the
  fake throw it with `fail(_:with:)`.

### Cancellation

`CancellationError` means the caller no longer wants the result; it is not a failure.

- Never catch it into an error case, a log line, or an error state: put
  `catch let error as CancellationError { throw error }` before a general `catch`.
- A long loop calls `try Task.checkCancellation()` rather than returning a half result.
- `throws(E)` cannot throw `CancellationError`, so a typed function that awaits
  cancellable work either stays on plain `throws` or gives `E` a `.cancelled` case the
  caller treats as a no-op (`HTTPClientError`).
- A port that cannot observe cancellation gets no such case (a local store works on its
  own actor; `TodoRepositoryError` has none). The `@MainActor` action awaiting it reads
  `Task.isCancelled` after the `await`, whatever came back, and makes it a no-op — no
  failure, no log, state restored — as `TodoListViewModel.load()` does.
- A test asserts it with `#expect(throws: CancellationError.self)`.

## Wording and localization

- Core owns every fixed string a person reads and returns it as a
  `LocalizedStringResource` (`TodoListStrings`, `TodoListFailure.message`), so the
  wording sits under the coverage floor. The one catalog is
  `Sources/MyAppCore/Resources/Localizable.xcstrings`; `MyAppUI` has none.
- Declare each as `TodoListStrings.emptyDescription` does:
  `LocalizedStringResource("todoList.empty.description", defaultValue: "…", bundle:
  .module, comment: "…")`.
  - `bundle: .module`: the default `.main` has no catalog, so the string reads right
    in English and never translates.
  - `defaultValue`: `swift test` copies the catalog uncompiled, so a test's English
    comes from here.
  - An explicit `feature.purpose` key, so the English can change without re-keying.
  - A `comment`, the translator's only context.
- One whole sentence per state with interpolated arguments, never a prefix glued to a
  swapped fragment: a translation must be free to reorder around its arguments.
- Declare each as a computed property, so it is rebuilt with the current locale on every
  read. Never name a generated string symbol: SwiftPM's build does not generate them,
  so `just test` fails to compile.
- A button label starts with a verb ("Add", "Retry"), and ends in an ellipsis when the
  action needs more input; capitalization follows the design lock's copy style.
- A new or changed key lands in the code, the catalog, and `LocalizationTests.everyCase()`
  together; `LocalizationTests` fails until they agree. Its scan is text: it misses a
  resource built from a bare literal or `String(localized:)`, which review catches.
  Edit the catalog in Xcode, or by hand in the format Xcode writes — two-space indent,
  `" : "` separators, sorted keys, no trailing newline (`.editorconfig`'s
  `[*.xcstrings]` keeps an editor from fighting it). A used key has a `comment` and an
  `en` `stringUnit` with `"state" : "translated"`, and no `extractionState`.
- A count inside a sentence is a plural variation, not `"\(count) items"`; the first one
  extends `LocalizationTests`' `CatalogLocalization` to read `variations`.
- English is the only shipped language. A second one is a design change
  (`AGENTS.md` › Before changing the architecture) the owner approves before any
  translation lands.
- Finding catalog drift, what each build does with the catalog, and the open questions a
  second language raises: the `designing-core-logic` skill's `references/localization.md`.

## Pinned by tests

- A `PreferenceKeys` name or default is pinned by `PreferenceKeysTests`: a rename is a
  stored-data migration (`AGENTS.md` › What is contract and what is private), not an
  edit to that test.
- A `SecureKeys` name is pinned by `SecureKeysTests`, for the same reason and a harder
  one: a Keychain item outlives the app's deletion, so a rename also strands the old
  secret on the device.
- A route, a deep link, or the URL scheme: `DeepLinkTests` holds Core's scheme to the
  one `project.yml` registers; run `just uitest` too.
- The stored navigation path — `AppRoute`'s stored names and `StoredNavigationPath`'s
  envelope — is pinned by `NavigationModelRestorationTests`' literal payload: a build in
  the wild has stored those bytes, so a change keeps reading them (a new version beside
  the old), never an edit to that literal.
- `LocalizationTests` holds the catalog (above); `AppLogTests` holds `AppLog.subsystem`
  to the bundle identifier.
