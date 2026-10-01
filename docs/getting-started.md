# Getting Started

## Prerequisites

- [Xcode][xcode], the version in `.xcode-version` (CI pins
  exactly that one), **with its iOS platform installed** — Xcode › Settings › Components.
  `xcode-select --install` alone is not enough: the app target needs the full IDE and
  an iOS Simulator runtime.
- [mise][mise] — installs the pinned CLI tools from `mise.toml`
- [Just][just] (optional — every recipe's
  underlying commands are plain shell; see [CONTRIBUTING.md](../CONTRIBUTING.md))

## Setup

```bash
git clone https://github.com/your-username/my-app.git
cd my-app
mise trust     # approve this repo's mise.toml (asked once per clone)
just install
just check
```

mise refuses to read config files it has not been told to trust, so a fresh clone
needs `mise trust` first. `just install` then runs `mise install` (SwiftLint,
SwiftFormat, XcodeGen, xcbeautify, actionlint, ShellCheck, typos — all pinned), points
`core.hooksPath` at `.githooks/` for the pre-commit gate, and generates
`MyApp.xcodeproj`. `just check` runs the full local gate once, so you start from green.

## Everyday Commands

```bash
just check     # the full local gate: verify-hooks → fmt → lint → test-scripts → check-harness → test → build
just test      # Swift Testing suites on the host Mac + 80% line / 75% function coverage floors on MyAppCore
just test-fast TodoItemTests   # only the matching tests, no coverage floor (while iterating)
just uitest    # the XCUITest launch test on an iOS Simulator
just test-ios  # every package test suite on an iOS Simulator (no coverage floor)
just smoke     # Release build + "does it actually launch" assertion
```

[CONTRIBUTING.md](../CONTRIBUTING.md) lists every recipe.

## Running on the Simulator

```bash
just run                                   # build (Debug), install, and launch on a simulator
SIMULATOR_DEVICE="iPhone 17 Pro" just run  # choose the device by name (or UDID)
just logs                                  # stream this app's log output; Ctrl-C to stop
just reset-permissions                     # forget this app's privacy grants on the booted simulator
```

`just run` boots the simulator, brings Simulator.app to the front, and replaces any
running copy of the app with the fresh build. `just logs` follows the subsystem the
app logs under (`AppLog`, which is the bundle identifier). After `just reset-permissions`
the next request for a permission prompts again, as on a fresh install.

## Running on your own iPhone

```bash
just run-device                      # build (Debug), install, and launch on a connected iPhone
IOS_DEVICE="<name or UDID>" just run-device   # when more than one device is connected
```

It needs a one-time `Config/Local.xcconfig` holding your development team, which is
gitignored and never committed. [Running on your own iPhone](running-on-device.md)
covers the setup, the bundle identifier, and a free Personal Team's limits.

## Removing the example code

The to-do list is an illustration for a new app to replace — example code in a skill
or a doc is likewise a sketch of the pattern, never something the app must keep. Work
through this list after `scripts/bootstrap.sh` (the paths below carry your app's name
once it has run).

**Core:**

- [ ] `Packages/MyAppKit/Sources/MyAppCore/TodoItem.swift` — the domain value
- [ ] `Packages/MyAppKit/Sources/MyAppCore/TodoRepository.swift` — the port and its
      error type, and its null object
      `Packages/MyAppKit/Sources/MyAppCore/UnavailableTodoRepository.swift`
- [ ] `Packages/MyAppKit/Sources/MyAppCore/TodoListViewModel.swift` — the view model
- [ ] `Packages/MyAppKit/Sources/MyAppCore/TodoListStrings.swift` and
      `Packages/MyAppKit/Sources/MyAppCore/TodoDetailStrings.swift` — the wording
- [ ] The `todoList.*` and `todoDetail.*` keys in
      `Packages/MyAppKit/Sources/MyAppCore/Resources/Localizable.xcstrings`, and the
      `TodoListStrings` and `TodoDetailStrings` cases in
      `Packages/MyAppKit/Tests/MyAppCoreTests/LocalizationTests.swift`
- [ ] `AppLog.todos`, the `todos` log category, in
      `Packages/MyAppKit/Sources/MyAppCore/AppLog.swift` — add a `Logger` for your own
      concern instead
- [ ] The Core tests: `Packages/MyAppKit/Tests/MyAppCoreTests/TodoItemTests.swift`,
      `Packages/MyAppKit/Tests/MyAppCoreTests/TodoListViewModelTests.swift`,
      `Packages/MyAppKit/Tests/MyAppCoreTests/TodoListViewModelEditingTests.swift`,
      `Packages/MyAppKit/Tests/MyAppCoreTests/TodoListViewModelHideCompletedTests.swift`,
      `Packages/MyAppKit/Tests/MyAppCoreTests/TodoListViewModelLookupTests.swift`,
      `Packages/MyAppKit/Tests/MyAppCoreTests/TodoListViewModelFixture.swift`, and
      `Packages/MyAppKit/Tests/MyAppCoreTests/TodoRepositoryContractTests.swift`

**Platform:**

- [ ] `Packages/MyAppKit/Sources/MyAppPlatform/Persistence/` — the adapter
      `Packages/MyAppKit/Sources/MyAppPlatform/Persistence/SwiftDataTodoRepository.swift`,
      the schema `Packages/MyAppKit/Sources/MyAppPlatform/Persistence/TodoSchemaV1.swift`,
      and the migration plan
      `Packages/MyAppKit/Sources/MyAppPlatform/Persistence/TodoMigrationPlan.swift`
- [ ] Its test: `Packages/MyAppKit/Tests/MyAppPlatformTests/SwiftDataTodoRepositoryTests.swift`

**Test support:**

- [ ] The fake `Packages/MyAppKit/Tests/MyAppTestSupport/InMemoryTodoRepository.swift`
      and the contract `Packages/MyAppKit/Tests/MyAppTestSupport/TodoRepositoryContract.swift`

**UI:**

- [ ] `Packages/MyAppKit/Sources/MyAppUI/TodoListView.swift`,
      `Packages/MyAppKit/Sources/MyAppUI/TodoDetailView.swift`, and
      `Packages/MyAppKit/Sources/MyAppUI/TodoDoneToggle.swift`
- [ ] The previews' repository: `Packages/MyAppKit/Sources/MyAppUI/PreviewTodoRepository.swift`

**App:**

- [ ] `makeRepository()`, the `todoList` view model, and the `TodoListView` root in
      `App/MyAppApp.swift` — wire your own port's adapter and first screen there

**UI tests:**

- [ ] `LaunchUITests/LaunchTests.swift` — every test adds, opens, deletes, or hides a
      to-do; point them at what your first screen shows

**Routing:**

- [ ] `AppRoute.todoDetail` in `Packages/MyAppKit/Sources/MyAppCore/Navigation/AppRoute.swift`,
      the `todo` host `Packages/MyAppKit/Sources/MyAppCore/Navigation/DeepLink.swift`
      parses, and the cases that use them in
      `Packages/MyAppKit/Tests/MyAppCoreTests/DeepLinkTests.swift` and
      `Packages/MyAppKit/Tests/MyAppCoreTests/NavigationModelTests.swift`

**Preferences:**

- [ ] `PreferenceKeys.hideCompleted` in
      `Packages/MyAppKit/Sources/MyAppCore/Preferences/PreferenceKeys.swift`, and its
      line in `Packages/MyAppKit/Tests/MyAppCoreTests/PreferenceKeysTests.swift`

**Keep, as the pattern your own code copies:**

- The port/fake/contract shape: a `Sendable` protocol in Core, its adapter in
  `MyAppPlatform`, one fake and one contract function in `MyAppTestSupport` — the
  `TodoRepository` files above are the worked example until your first port exists
- `HTTPClient` — `Packages/MyAppKit/Sources/MyAppCore/Networking/HTTPClient.swift`
  and `Packages/MyAppKit/Sources/MyAppPlatform/Networking/URLSessionHTTPClient.swift`
- `PreferencesStoring` — `Packages/MyAppKit/Sources/MyAppCore/Preferences/PreferencesStoring.swift`
  and `Packages/MyAppKit/Sources/MyAppPlatform/Preferences/UserDefaultsPreferences.swift`
- `NavigationModel` — `Packages/MyAppKit/Sources/MyAppCore/Navigation/NavigationModel.swift`
- `DesignTokens` — `Packages/MyAppKit/Sources/MyAppUI/DesignSystem/DesignTokens.swift`
- `AppLog` — `Packages/MyAppKit/Sources/MyAppCore/AppLog.swift`

**An order that keeps `just check` green at each step:**

1. Add your own Core model, view model, and their tests beside the example, so the
   coverage floor always has something to measure.
2. Wire your first screen into `App/MyAppApp.swift` in place of `TodoListView` and
   `makeRepository()`, and point `LaunchUITests/LaunchTests.swift` at it (`just uitest`).
3. Delete the UI files and the previews' repository.
4. Replace `AppRoute.todoDetail` and the `todo` deep link with a route of your own,
   updating `DeepLinkTests` and `NavigationModelTests` in the same step.
5. Delete `PreferenceKeys.hideCompleted` with its `PreferenceKeysTests` line — a stored
   key's removal is a migration for any app already installed, so do it before you ship.
6. Delete `TodoListViewModel`, the two strings files, their catalog keys, and their
   `LocalizationTests` cases together.
7. Delete the Platform persistence files and their test, then the fake and the
   contract, then `TodoRepository`, `UnavailableTodoRepository`, `TodoItem`, the Core
   tests, and `AppLog.todos`.

`rg -i 'todo'` then lists anything left — including the mentions in `AGENTS.md`,
`docs/architecture.md`, `.claude/rules/`, and the skills that cite the to-do list as
the worked example (skills are edited under `.agents/skills/`, then `just agents-sync`).

## Open in Xcode

```bash
just generate
open MyApp.xcodeproj
```

Remember: `MyApp.xcodeproj` is generated from `project.yml` and gitignored. Change
targets and settings in `project.yml`, then `just generate`.

## App Icon

The template ships `App/Assets.xcassets/AppIcon.appiconset` with empty 1024×1024 slots
(default, dark, and tinted) — the app builds and runs without icon artwork. Add yours either as an image in that asset
catalog (Xcode › the App target's Assets), or as an Icon Composer `.icon` file, which
gives the iOS 26 layered, Liquid Glass icon. Which one, and what it looks like, is an
app decision: record it in the app's design lock, as the `designing-ui` skill
([SKILL.md](../.agents/skills/designing-ui/SKILL.md)) says.

[xcode]: https://developer.apple.com/xcode/
[mise]: https://mise.jdx.dev/
[just]: https://just.systems/man/en/installation.html
