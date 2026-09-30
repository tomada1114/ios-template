---
paths:
  - "Packages/**/*.swift"
  - "App/**/*.swift"
---

## Design

- One logical concern per file. SwiftLint enforces its default limits under `strict: true`
  (warnings fail): a file over 400 lines (`file_length`), a function body over 50 lines
  (`function_body_length`), or more than 5 parameters (`function_parameter_count`) fails
  `just lint` — group related parameters in a struct long before that
- Value types first: reach for `struct`/`enum`; use `class` only for identity or reference semantics
- `MyAppCore` must never import SwiftUI, UIKit, AppKit, Cocoa, SwiftData, CoreData,
  CloudKit, UserNotifications, CoreLocation, Photos, PhotosUI, StoreKit, or WidgetKit —
  it stays free of UI, persistence, and OS-integration frameworks (enforced by
  `.swiftlint.yml`'s `no_ui_import_in_core` and `ArchitectureBoundaryTests`).
  `Foundation`, `Observation`, and `os` are allowed: logging is neither a UI nor an
  OS-integration framework, so Core imports `os` directly (see Logging below)
- Storage and OS services go in `MyAppPlatform`, as an adapter behind a `Sendable` port
  Core declares: value types in and out, translation only, no branching domain logic
  (that belongs in Core, where the coverage floor sees it)
- Views in `MyAppUI` stay thin: no business logic, delegate everything to Core view models
- `MyAppUI` and `MyAppPlatform` are siblings and never import each other; `App/` is the
  composition root that hands a `MyAppPlatform` adapter to a Core view model
- How Core logic is shaped (injected time, locale, and randomness; action-shaped view
  models) is the `designing-core-logic` skill; the reasoning is
  `docs/architecture.md` › View models
- `///` doc comments on all public API; document *why*, not what the signature already says
- A `switch` over an enum `MyAppCore` declares lists every case and has no `default:`
  (group cases with `case .a, .b:` instead), so adding a case is a compile error at each
  switch that must decide about it rather than a silent fall into `default`. An enum the
  SDK owns (an imported C enum, an `NSError` code) is the exception: map the cases you
  know and send the rest to `default:` or `@unknown default:` (the `designing-errors`
  skill). No SwiftLint rule enforces this; review does

## Two platforms at compile time

- `Package.swift` lists `.macOS(.v15)` beside `.iOS(.v18)` so `swift test` runs the
  package on the host. `MyAppUI` and `MyAppPlatform` therefore also compile for macOS
  under `swift build`/`swift test`, not only for the iOS Simulator
- An iOS-only API (`.navigationBarTitleDisplayMode`, `UIApplication`, a `UIKit` type)
  goes inside `#if os(iOS)`
- `cd Packages/MyAppKit && swift build` is the check that catches a missing guard;
  `just build` alone compiles only for iOS and will not
- The why: `docs/architecture.md` › Why the package also builds for macOS

## Persistence

- `@Model` types, `ModelContainer`, and `ModelContext` appear only in
  `Sources/MyAppPlatform/Persistence/` — never in Core, a view, or `App/`, which reaches
  the store through `SwiftDataTodoRepository.make(storage:)`
- The adapter is a `@ModelActor` actor and maps a record to a Core value type inside the
  actor, so no `@Model` object crosses the port
  (`docs/architecture.md` › Repositories › The SwiftData adapter)
- A shipped `VersionedSchema` (`TodoSchemaV1`) is never edited: a change to a stored
  model is a new schema version plus a `TodoMigrationPlan` stage, with a test that opens a
  store the previous version wrote (`docs/architecture.md` › What is contract)

## Access Control

- Narrowest first: `private`, then internal (the default, unwritten), then `package`,
  then `public`
- `package` (Swift 5.9+; `Packages/MyAppKit/Package.swift` is tools-version 6.2) is for
  a declaration another target *in* `Packages/MyAppKit` needs — a sibling module or a
  test target — that is not app API. It replaces `@testable import` in a Core test
  (`testing.md` › Framework and Structure). `App/` is an Xcode target outside the
  package and cannot see it: whatever `App/` calls is `public`
- `package` does not loosen the module boundaries: `MyAppUI` and `MyAppPlatform` still
  never import each other, and a view still does not mutate Core state directly

## Constants

- A view's spacing, corner radius, and hit-target size: `DesignTokens`
  (`Sources/MyAppUI/DesignSystem/DesignTokens.swift`) — `TodoListView.swift` is the
  worked example. A number only one view needs and the scale does not cover: a
  `private enum Layout` at the top of that view's file. A test's timeouts likewise
  (`LaunchTests.swift`'s `Timeout`)
- A number someone might tune (a delay, a threshold, a limit): one tuning type in Core
  (the `designing-core-logic` skill); a domain invariant is a parameter or a `static` on
  its type (`TodoItem.normalizedTitle(_:)`), not a tunable
- User-visible wording Core decides: a `static` on a caseless enum in Core
  (`TodoListStrings`), backed by the String Catalog; the logging subsystem: `AppLog`, once
- A type holding only `static` members is a caseless `enum` (SwiftLint's
  `convenience_type`). No global `let`, and no `Constants.swift` grab bag: a constant
  lives beside the one concern that uses it

## Error Handling

- Define typed errors per module (an `enum ... : Error, Equatable` with payload), thrown
  with context — `TodoRepositoryError` is the worked example; its payloads carry
  identifiers, never a title
- NEVER `try!` or force-unwrap (`!`) in production code; `guard let`/`throws` instead
- Never swallow errors silently; if catching, handle meaningfully or rethrow
- Never use errors for control flow
- Typed vs. plain `throws`, cancellation, payload privacy, and mapping a framework error
  in an adapter: the `designing-errors` skill

## Logging

- `os.Logger` is the only logging facility. NEVER `print`, `debugPrint`, or `NSLog`
  anywhere under `Packages/*/Sources/` or `App/`: an app launched from the Home Screen
  has nowhere to send stdout, so those lines are lost exactly when they matter. Enforced
  by `.swiftlint.yml`'s `no_print_in_sources`; test targets are exempt
- Every logger is declared in `AppLog` (`Sources/MyAppCore/AppLog.swift`), never built
  inline: `subsystem` is the app's bundle identifier, spelled once as a literal there
  (`Bundle.main.bundleIdentifier` answers for the test runner under `swift test` and for
  the preview agent in a preview), and one `category` names one concern. `just logs`
  streams that subsystem; `AppLogTests` fails if it drifts from `project.yml`
- Anything user-derived carries a privacy annotation — a to-do's title, anything typed,
  a file path — is `.private`. Only values that are safe in anyone's log, such as an
  identifier, a count, or an operation name, are `.public`. `os.Logger` defaults
  interpolated strings to `.private`, so say which one you mean rather than relying on
  the default
- Level by intent: `.debug` for the development stream `just logs` shows, `.info` for a
  milestone worth keeping, `.error`/`.fault` for something that went wrong. See
  `TodoListViewModel.load()` for the worked example
- A log message is an autoclosure: log a local constant, not a `self.` property
  (`docs/architecture.md` › Logging)

## Concurrency

- Swift 6 language mode is on: data-race safety errors are non-negotiable
- UI-facing state is `@MainActor` (`TodoListViewModel`); keep Core types `Sendable` where
  they cross actors
- Ports are `Sendable`. The repository and HTTP ports are `async`; `PreferencesStoring` is
  deliberately synchronous (`docs/architecture.md` › Preferences)
- Adapters and fakes are actors (`SwiftDataTodoRepository`, `InMemoryTodoRepository`), or
  `Sendable` structs holding only `Sendable` values (`URLSessionHTTPClient`,
  `UserDefaultsPreferences`) and final classes guarding their state with a `Mutex`
  (`InMemoryPreferences`) — never `@unchecked Sendable` (`docs/architecture.md` ›
  Concurrency)
- No `@unchecked Sendable` without a comment proving the invariant it papers over
