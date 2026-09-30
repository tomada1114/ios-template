# Architecture

This is the design document for the template: how an app cut from it is layered, which
patterns it uses and why, and where a new piece of code goes. `AGENTS.md` holds the rules
and the commands; this file holds the reasoning behind them. The worked example
throughout is the to-do list the template ships — small enough to read in one sitting,
but with every seam a real app needs: a domain value, a view model, a repository port,
a SwiftData adapter, a fake, a contract test, and a UI test.

## Decisions at a glance

| Decision | Choice | Why |
|---|---|---|
| Minimum OS | iOS 18 (`project.yml`, `Package.swift`) | `@Observable`, SwiftData, `ContentUnavailableView`, and the iOS 18 SwiftData and tab APIs without `#available` branches, while still reaching most devices in use. Raising it is an app's decision; lowering it below 17 loses `@Observable` and SwiftData |
| Presentation pattern | MVVM with `@MainActor @Observable` view models in Core | The view model is plain Swift that `swift test` drives in milliseconds, so every decision a screen makes is unit-tested and coverage-gated; the view stays a thin renderer |
| Persistence | SwiftData, behind a Core-declared repository port | First-party (no dependency), migrations built in, and the port keeps it replaceable: Core never imports SwiftData |
| Module layout | One local Swift package, `MyAppKit`, with `MyAppCore` / `MyAppUI` / `MyAppPlatform` | Module boundaries the compiler enforces, and a package `swift test` can run without a simulator |
| Project file | XcodeGen (`project.yml`); `MyApp.xcodeproj` is generated and gitignored | No merge conflicts in a `.pbxproj`, and the whole app target is reviewable as text |
| Language mode | Swift 6, warnings as errors | Data-race safety is checked from the first line; there is never a "migrate later" |
| Dependencies | None | Every third-party package is a supply-chain and upgrade cost; adding one is a human's decision (`AGENTS.md` › Security and human approval) |

Patterns deliberately **not** adopted: The Composable Architecture (a dependency and a
learning curve for what `@Observable` plus ports already give), Combine for state (the
Observation framework replaces it), singletons or a global service locator (the
composition root passes everything explicitly), and Core Data (SwiftData is its
successor on this OS floor).

## Layers

```
App/                         composition root — @main, builds adapters, hands them to Core
 ├─ MyAppUI                  SwiftUI views: render Core state, forward user intents
 │   └─ MyAppCore            domain values, view models, ports (protocols), wording, logging
 └─ MyAppPlatform            adapters behind Core ports: SwiftData today, OS services later
     └─ MyAppCore
Tests/MyAppTestSupport       each port's fake and contract function (test code only)
```

- **Core ← UI** and **Core ← Platform**; both ← `App/`. `MyAppUI` and `MyAppPlatform`
  are siblings and never import each other. A view therefore cannot reach SwiftData, and
  an adapter cannot reach a view — the only place both halves meet is `App/`.
- **Core imports no UI, persistence, or OS-integration framework** — SwiftUI, UIKit,
  AppKit, Cocoa, SwiftData, CoreData, CloudKit, UserNotifications, CoreLocation, Photos,
  PhotosUI, StoreKit, WidgetKit. It is enforced twice: `.swiftlint.yml`'s
  `no_ui_import_in_core` and `ArchitectureBoundaryTests`, whose lists change together.
  `Foundation`, `Observation`, and `os` are allowed.
- **`App/` holds no logic.** It decides which adapter each port gets, and nothing else.
- **Shared presentation values live in `MyAppUI`**, in `DesignSystem/DesignTokens.swift`
  (spacing, radius, hit target, motion), never in Core; `docs/design-system.md` records
  why each has its value.

### Why the package also builds for macOS

`Package.swift` lists `.macOS(.v15)` next to `.iOS(.v18)` so `swift test` runs the whole
package on the host Mac: seconds instead of a simulator boot, and the only way
`scripts/coverage.sh` can read coverage from `swift test`. The cost is that every target
must compile for macOS too. Core does by construction; in `MyAppUI` and `MyAppPlatform`
an iOS-only API (`.navigationBarTitleDisplayMode`, `UIApplication`, a `UIKit` type) goes
behind `#if os(iOS)`. The app itself is iOS-only — `project.yml` builds it for the iOS
Simulator, and CI's `app` job proves it compiles and launches there.

## View models

A view model is a `@MainActor @Observable final class` in Core. The template's is
`TodoListViewModel`.

- **Action-shaped.** The view calls one method per user intent — `addDraft()`,
  `toggle(_:)`, `delete(atOffsets:)` — and never mutates published state itself. State is
  `public private(set)`; the only settable property is what a control binds to
  (`draftTitle`).
- **Derived state lives here.** `canAdd`, `showsEmptyState`, `showsLoadFailure`,
  `showsProgress` are computed in Core so the view has no `if` of its own worth testing.
- **Wording lives here.** Core returns `LocalizedStringResource` from its String Catalog
  (`TodoListStrings`, `TodoListFailure.message`); a view renders it with `Text(_:)` and
  shows user data with `Text(verbatim:)`.
- **Time and identity are injected** (`now: () -> Date`, `makeID: () -> UUID`) so a test
  pins both. The same goes for anything nondeterministic an app adds: a `Clock`, a
  `Locale`, a random number generator.
- **Construction has no side effects.** Nothing is read until `load()`; the view calls it
  from `.task` on first appearance.
- **Ownership.** `App/` creates the view model in `@State` (so it outlives any one view
  tree) and passes it down; the view holds it with `@Bindable` only to bind controls.

### Reentrancy

A `@MainActor` method that `await`s can be re-entered by the next tap before it resumes.
The view model is written for that:

- An in-flight add sets `isAdding`, which disables Add, so a double tap stores one item.
- After an `await`, a row is found again by identifier rather than by a remembered index —
  the list may have changed in between (`toggle(_:)`).
- The draft is cleared only if it still holds what was submitted, so text typed while a
  save was in flight survives (`addDraft()`).

Each of these has a test in `TodoListViewModelTests` that drives the interleaving through
the fake's `onSave` hook.

## Repositories

A repository is a **port**: a `Sendable` protocol Core declares, in Core's vocabulary.
`TodoRepository` is the worked example.

```swift
public protocol TodoRepository: Sendable {
    func fetchAll() async throws(TodoRepositoryError) -> [TodoItem]
    func save(_ item: TodoItem) async throws(TodoRepositoryError)
    func delete(id: TodoItem.ID) async throws(TodoRepositoryError)
}
```

- **Value types only across the port.** `TodoItem` is a Core struct; the SwiftData
  `@Model` (`TodoRecord`) is internal to `MyAppPlatform` and never crosses. That is what
  keeps SwiftData's non-`Sendable` model objects on the adapter's actor and lets every
  Core test run without SwiftData.
- **`async` everywhere**, because an implementation is an actor with its own executor
  (SwiftData's `@ModelActor`, or the fake), and crossing into it is a suspension point.
- **Typed throws with a closed Core error enum.** `TodoRepositoryError` has three cases;
  the adapter maps every SwiftData error into one of them and logs the detail
  (`.private`), so Core handles a closed set and never learns which store failed. Error
  payloads carry identifiers, never titles — an error can reach a log or a crash report.
- **The ordering is Core's.** `TodoItem.isOrderedBefore(_:_:)` defines display order and
  every implementation sorts by it, so a store's query language never decides behavior.
- **A null object for "no store".** When the on-disk store cannot be opened, `App/` hands
  the view model `UnavailableTodoRepository`, which fails every call. The app launches,
  shows its load failure with a retry, and never pretends an edit was saved. The
  alternatives — crashing, or silently falling back to an in-memory store whose edits
  vanish on relaunch — are both worse for the user.

### The SwiftData adapter

`SwiftDataTodoRepository` is an `actor` annotated `@ModelActor`: SwiftData gives it a
`ModelContext` bound to its own serial executor, so no model object leaves the actor and
the main actor never waits on a write it did not ask for.

- **`make(storage:)`** opens the container — `.onDisk` for the app, `.inMemory` for UI
  tests (`-uiTesting`) and host tests — and maps a failure to `.storageFailure`.
- **A failed save rolls the context back**, or the pending change would be written by
  the next successful save.
- **The schema is versioned from day one** (`TodoSchemaV1`, `TodoMigrationPlan`). The
  stored shape is contract (below): the next change to `TodoRecord` adds `TodoSchemaV2`
  and a migration stage instead of editing V1.
- **`@Attribute(.unique)` on the identifier** makes a save with a known id an update.
  CloudKit sync does not allow unique constraints; an app that turns sync on replaces it
  with a fetch-before-insert in a new schema version, and that choice is an ADR.

### Fakes and contracts

Every port has exactly one fake and one contract function, both in
`Tests/MyAppTestSupport`:

- **`InMemoryTodoRepository`** — a real conforming actor, not a mock: tests hand it data
  and failures (`fail(_:with:)`), then read what happened (`calls`, `snapshot`). No
  expectations are declared up front.
- **`TodoRepositoryContract.check(_:)`** — every promise the port's `///` makes, written
  once over the protocol. `MyAppCoreTests` runs it against the fake and
  `MyAppPlatformTests` against the SwiftData adapter with an in-memory store, both under
  `just test` and in CI. A fake stands in for the adapter only while both keep the same
  promises; this is what checks it. The contract has its own oracle tests — deliberately
  broken implementations it must reject — so it cannot pass vacuously.

`MyAppTestSupport` is a library target only because a test target cannot be depended on.
No product exports it and `ArchitectureBoundaryTests` fails if a shipped module imports
it. Previews use their own small `PreviewTodoRepository` in `MyAppUI` (Debug only).

## Composition root

`App/MyAppApp.swift` is the one place that knows both halves of every port. It picks the
storage from the launch arguments, opens the SwiftData adapter, falls back to the null
object on failure, creates the view model in `@State`, and hands it to the root view. A
second screen or a second port is wired here too; if the wiring grows past a handful of
lines, it moves into an `AppDependencies` value built in `App/` — still no singletons.

## Concurrency

- Swift 6 language mode, complete checking, warnings as errors.
- View models are `@MainActor`; ports are `Sendable` and `async`; adapters and fakes are
  actors. Values crossing actors are `Sendable` structs and enums.
- `@unchecked Sendable` and `nonisolated(unsafe)` are not used to silence a diagnostic —
  doing so needs human sign-off (`AGENTS.md`).
- A closure a test injects (`now`, `makeID`, the fake's `onSave`) is `@Sendable`; capture
  values, not a `@MainActor` static.

## Logging

Shipped code logs through `AppLog` in Core — `os.Logger`, one subsystem (the bundle
identifier, checked against `project.yml` by `AppLogTests`) and one category per concern
(`todos`, `persistence`). `print`, `debugPrint`, and `NSLog` are rejected under
`Packages/*/Sources/` and `App/` by `.swiftlint.yml`'s `no_print_in_sources`: an app
launched from the Home Screen has nowhere to send stdout. Anything user-derived is
interpolated `.private`; identifiers, counts, and operation names are `.public`.
`just logs` streams the subsystem from the booted simulator.

A log message is an autoclosure that needs an explicit `self`, which SwiftFormat's
`redundantSelf` rule strips — log a local constant instead of a `self.` property
(`TodoListViewModel.load()`).

## Localization

Core owns every fixed string a reader sees, in `Sources/MyAppCore/Resources/Localizable.xcstrings`,
through `LocalizedStringResource(_:defaultValue:bundle: .module, comment:)`. English is
the only shipped language (`defaultLocalization: "en"`); adding one is an app's decision.
`swift test` copies the catalog uncompiled, so tests resolve English from `defaultValue`
(the `english` helper in `MyAppCoreTests`); `xcodebuild` compiles it into the app.

## Testing

| Layer | Test | Where | Runs in |
|---|---|---|---|
| Domain values, view models | Swift Testing suites against fakes | `Tests/MyAppCoreTests` | `just test`, CI `test` (coverage-gated) |
| Port promises | the contract function, against the fake | `Tests/MyAppCoreTests` | `just test`, CI `test` |
| Adapters | the contract function, against the real adapter; adapter-only cases | `Tests/MyAppPlatformTests` | `just test`, CI `test` — when the framework runs on the host |
| Module boundaries | `ArchitectureBoundaryTests` | `Tests/MyAppCoreTests` | `just test`, CI `test` |
| Launch and the core interaction | XCUITest | `LaunchUITests/` | `just uitest`, CI `app` (iOS Simulator) |

- **Where a test goes.** A decision is tested in Core. An adapter is tested only for its
  translation, by the contract. An adapter whose framework needs a simulator, a device,
  or a permission prompt (notifications, location, photos) cannot run under `swift test`
  on the host; its contract run happens on a simulator or device, and its output goes in
  the pull request.
- **Coverage floor.** `scripts/coverage.sh` gates `Sources/MyAppCore` at 80% of lines and
  75% of functions. `MyAppUI` and `MyAppPlatform` are outside it by design: views render
  and adapters translate, so neither holds a decision a unit test could catch. The floor
  is raised, never lowered.
- **Swift Testing everywhere except UI automation**, which Apple still offers only in
  XCTest. Test names are backticked sentences; error paths assert the thrown error's
  payload.
- **Fakes, not mocks.** One fake per port in `MyAppTestSupport`, held to the contract.

## What is contract and what is private

Contract is what something outside a change can observe: another module, a user's
device that ran an earlier build, or the user.

| Contract | What depends on it | What changing it requires |
|---|---|---|
| **Core's public API** | `MyAppUI`, `MyAppPlatform`, `App/`, the tests | Update every caller in the same pull request; a new public declaration carries a `///` saying why; a new port is an ADR |
| **The bundle identifier** (`PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`) | The app's data container and Keychain items on every device, App Store Connect, push and other capabilities, `AppLog.subsystem`, `just run`/`just logs` | Fixed once a build has left your machine: a new identifier is a new app, and the user's data stays behind. `project.yml` and `AppLog.subsystem` change together (`AppLogTests`) |
| **The stored schema** (`TodoSchemaV1` and its successors) | Every store already on a user's device | A new `VersionedSchema` plus a `TodoMigrationPlan` stage, with a test that opens a store written by the previous version. Never edit a shipped schema version |
| **`UserDefaults` keys and file formats** | Saved preferences and files on a user's device | Read the old key or format and migrate it in Core, with a test that starts from the old value. The template ships none |

Everything else is private: `internal` declarations, how an adapter talks to its
framework, view structure, file and type layout, test helpers, log messages.

## Where new code goes

**A new screen or feature**

1. Domain values and their invariants in `MyAppCore` (TDD — the `tdd` skill).
2. A port in `MyAppCore` if the feature needs storage or an OS service; its fake and
   contract in `Tests/MyAppTestSupport`.
3. A `@MainActor @Observable` view model in `MyAppCore`, tested against the fake.
4. The adapter in `MyAppPlatform`, with the contract run against it in
   `Tests/MyAppPlatformTests`.
5. The view in `MyAppUI`, rendering the view model; `#Preview` per state; accessibility
   identifiers on what a UI test touches.
6. The wiring in `App/`.

**A new OS integration** (notifications, location, photos, purchases): the same port and
adapter shape. The framework import lives only in `MyAppPlatform`; the permission's
usage-description string goes in `project.yml` as an `INFOPLIST_KEY_…` setting; the
decision of when to ask lives in Core.

**A new stored model**: a new `@Model` in the next schema version, never an edit to a
shipped one.
