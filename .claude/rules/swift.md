---
paths:
  - "Packages/**/*.swift"
  - "App/**/*.swift"
---

Module-specific rules: `core.md` (MyAppCore), `ui.md` (MyAppUI, `App/`, LaunchUITests),
`platform.md` (MyAppPlatform and its tests), `testing.md` (every test target).

## Design

- One logical concern per file. `just lint` enforces SwiftFormat and SwiftLint's length
  and parameter limits under `strict: true` (`just fix` applies what is auto-fixable);
  group related parameters in a struct long before `function_parameter_count` fires
- Value types first: reach for `struct`/`enum`; use `class` only for identity or reference semantics
- `///` doc comments on all public API; document *why*, not what the signature already says
- A `switch` over an enum `MyAppCore` declares lists every case and has no `default:`
  (group cases with `case .a, .b:` instead), so adding a case is a compile error at each
  switch that must decide about it rather than a silent fall into `default`. An enum the
  SDK owns is the exception (`platform.md` › Mapping framework errors). No SwiftLint
  rule enforces this; review does

## Two platforms at compile time

- `Package.swift` lists `.macOS(.v27)` beside `.iOS(.v27)` so `swift test` runs the
  package on the host. `MyAppUI` and `MyAppPlatform` therefore also compile for macOS,
  not only for the iOS Simulator
- An iOS-only API (`.navigationBarTitleDisplayMode`, `UIApplication`, a `UIKit` type)
  goes inside `#if os(iOS)`
- `just test` (which builds the package for macOS) catches a missing guard; `just build`
  compiles only for iOS and will not. Code behind `#if os(iOS)`, and behavior that
  differs on the iOS runtime, is tested only by `just test-ios`
- The why: `AGENTS.md` › Architecture

## Access Control

- Narrowest first: `private`, then internal (the default, unwritten), then `package`,
  then `public`
- `package` is for a declaration another target *in* `Packages/MyAppKit` needs — a
  sibling module or a test target — that is not app API. It replaces `@testable import`
  in a Core test (`core.md` › Test first). `App/` is an Xcode target outside the package
  and cannot see it: whatever `App/` calls is `public`
- `package` does not loosen the module boundaries: `MyAppUI` and `MyAppPlatform` still
  never import each other, and a view still does not mutate Core state directly

## Constants

- A type holding only `static` members is a caseless `enum` (SwiftLint's
  `convenience_type`). No global `let`, and no `Constants.swift` grab bag: a constant
  lives beside the one concern that uses it
- Where each kind lives: a view's spacing, radius, or hit target in `DesignTokens`
  (`ui.md`); a number someone might tune in Core's one `Tuning` type (`core.md`);
  user-visible wording as a `static` on a caseless enum in Core (`TodoListStrings`); the
  logging subsystem in `AppLog`, once; a test's timeouts in a caseless enum in the test
  file (`LaunchTests.swift`'s `Timeout`)

## Error Handling

- No `try!` or force-unwrap (`!`) in production code; `guard let`/`throws` instead
- Never swallow an error: handle it meaningfully or rethrow it
- Never use errors for control flow
- Designing an error type, typed vs. plain `throws`, and cancellation: `core.md` ›
  Errors. Mapping a framework error in an adapter: `platform.md`

## Logging

- Shipped code logs only through `os.Logger` (`no_print_in_sources` rejects `print`,
  `debugPrint`, and `NSLog`; test targets are exempt)
- Every logger is declared in `AppLog` (`Sources/MyAppCore/AppLog.swift`), never built
  inline: `subsystem` is the app's bundle identifier, spelled once as a literal there
  (`Bundle.main.bundleIdentifier` answers for the test runner under `swift test` and for
  the preview agent in a preview), and one `category` names one concern. `just logs`
  streams that subsystem; `AppLogTests` fails if it drifts from `project.yml`
- Every interpolation carries an explicit privacy annotation. Anything user-derived — a
  to-do's title, anything typed, a file path — is `.private`; only values safe in
  anyone's log, such as an identifier, a count, an error code, or an operation name, are
  `.public`. `os.Logger` defaults dynamic strings to `.private`; never mark one `.public`
  to make a log easier to read
- Level by intent: `.debug` for the development stream `just logs` shows, `.info` for a
  milestone worth keeping, `.error`/`.fault` for something that went wrong. See
  `TodoListViewModel.load()` for the worked example
- A log message is an autoclosure that needs an explicit `self`, which SwiftFormat's
  `redundantSelf` rule strips: log a local constant, not a `self.` property
  (`TodoListViewModel.load()`)

## Concurrency

- Swift 6 language mode is on: data-race safety errors are non-negotiable
- UI-facing state is `@MainActor` (`TodoListViewModel`); keep Core types `Sendable` where
  they cross actors
- Ports are `Sendable`. The repository, HTTP, and secure-storage ports are `async`;
  `PreferencesStoring` is deliberately synchronous (the `persisting-data` skill's
  `references/preferences.md`)
- Adapters and fakes are actors (`SwiftDataTodoRepository`, `InMemoryTodoRepository`,
  `KeychainSecureStore`, `InMemorySecureStore`),
  `Sendable` structs holding only `Sendable` values (`URLSessionHTTPClient`,
  `UserDefaultsPreferences`), or final classes guarding their state with a `Mutex`
  (`InMemoryPreferences`)
- A closure a test injects (`now`, `makeID`, the fake's `onSave` and `onFetch`) is
  `@Sendable`; it captures values, not a `@MainActor` static
- `@unchecked Sendable` and `nonisolated(unsafe)` are not used to silence a diagnostic:
  doing so needs a human's sign-off (`AGENTS.md` › Security and human approval), and a
  comment explaining the invariant does not replace it. The usual fixes are in the
  `integrating-system-apis` skill
