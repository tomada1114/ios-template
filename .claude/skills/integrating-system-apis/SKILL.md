---
name: integrating-system-apis
description: >
  Covers reaching an iOS system API from this app through a Core port under Swift 6
  strict concurrency - where the port, the MyAppPlatform adapter, the fake, the contract,
  and the App/ wiring go; a permission status as a Core enum; Info.plist usage
  descriptions (INFOPLIST_KEY_NSCameraUsageDescription and friends), UIBackgroundModes,
  BGTaskSchedulerPermittedIdentifiers and PrivacyInfo.xcprivacy in project.yml;
  UserNotifications authorization and scheduling, PhotosPicker and loadTransferable,
  BGTaskScheduler background tasks, simctl privacy grant, revoke and reset; #if os(iOS)
  in MyAppPlatform and what just test, just test-ios, and a human on a device each
  prove. Use when adding a notification, photo, camera, location, background-task, or
  other framework integration, when a permission prompt or a denied permission is
  involved, when the app crashes at a missing usage-description string, when a
  framework type will not cross an actor boundary, or when tempted by @unchecked
  Sendable or nonisolated(unsafe).
---

# Integrating System APIs

**Owns:** reaching an iOS framework from this app — the port and adapter shape, a
permission as Core state, where a usage description and an `Info.plist` key live, and
what can be tested where. **Does not own:** which capabilities and entitlements the app
takes (`starting-an-app`, and an ADR — `recording-architecture-decisions`); the
red-green loop for the Core decision the port serves (`tdd`); the Core error enum an
adapter maps into (`designing-errors`); running the app and the evidence a pull request
carries (`running-the-app`); a picker or other control that lives in a view
(`building-swiftui-screens`).

## The shape, before any OS code

Every integration is the same pieces, and the template ships one of each to copy —
`docs/architecture.md` › Repositories is the full description:

| Piece | Where | Worked example |
|---|---|---|
| Port: a `Sendable` protocol, Core value types in and out, and the decision it serves | `Sources/MyAppCore/` | `TodoRepository.swift`, and `TodoListViewModel` deciding what to show |
| Adapter: the framework import, translation only | `Sources/MyAppPlatform/` | `Persistence/SwiftDataTodoRepository.swift` |
| Fake: a real implementation answering from test data | `Tests/MyAppTestSupport/` | `InMemoryTodoRepository.swift` |
| Contract: the port's promises, run against the fake and the adapter | `Tests/MyAppTestSupport/` | `TodoRepositoryContract.swift` |
| Wiring: which adapter each port gets | `App/` | `MyAppApp.makeRepository()` |

Write the port first. Its signature is where you decide what the framework type
collapses into, and an adapter written before its port almost always leaks one:
`UNNotificationSettings`, `PHAsset`, `BGTask`, and `CLLocation` are framework types a
Core test cannot build, and their frameworks are banned from `MyAppCore` by
`.swiftlint.yml`'s `no_ui_import_in_core` and `ArchitectureBoundaryTests`.

## Permission as Core state

A permission is a Core enum the port returns, never the framework's status type:

```swift
public enum NotificationPermission: Equatable, Sendable {
    case notDetermined, denied, authorized, provisional
}
```

- Start from `notDetermined`, `denied`, `authorized`, and add `restricted`, `limited`,
  or `provisional` only when the framework has that case — `PHAuthorizationStatus` has
  `limited`, `UNAuthorizationStatus` has `provisional` (and `ephemeral`, for App Clips),
  `CLAuthorizationStatus` has `restricted`.
- The adapter maps the framework's status one to one; the `@unknown default` the
  compiler requires is logged and never answers `authorized`. It decides nothing.
- The view model decides: whether to ask now, what an empty state says while denied,
  whether to offer the Settings link. That is Core behavior with a Core test against
  the fake, where the coverage floor sees it.
- When to ask is a product decision, and Apple's guidance is to ask in context, not at
  first launch
  ([Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications),
  checked 2026-09-30).

## Three rules that never bend

1. **Only values cross the port.** Translate the framework object into the port's value
   type inside the adapter, then return the value. A framework class handed to a
   `@MainActor` view model is a compile error under Swift 6
   (`sending '…' risks causing data races`), and a bug even where it compiles.
2. **The usage description and the `Info.plist` key exist before the first call.** A
   missing usage string does not fail the build or a test; the system terminates the app
   at the first request
   ([Requesting authorization to capture and save media](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media),
   checked 2026-09-30). **REQUIRED:** [references/permissions.md](references/permissions.md).
3. **Launch-time registration lives in `App/`, and happens before launch finishes.** A
   notification delegate assigned after launch can miss notifications
   ([`UNUserNotificationCenterDelegate`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)),
   and every `BGTaskSchedulerPermittedIdentifiers` identifier needs its handler
   registered before launch completes
   ([`register(forTaskWithIdentifier:using:launchHandler:)`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)),
   both checked 2026-09-30). The composition root does the registering; the work it
   triggers is a Core action.

## Worked mechanisms

Where each common integration's code lives. The behavior is Apple's — follow the link
rather than a paraphrase (all checked 2026-09-30).

| You need | Where the code goes | Port? |
|---|---|---|
| Notification authorization and scheduling — [`UNUserNotificationCenter`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) | adapter in `MyAppPlatform` (the async `requestAuthorization(options:)`, `notificationSettings()`, `add(_:)`); delegate wiring in `App/` | yes |
| The user picks a photo — [`PhotosPicker`](https://developer.apple.com/documentation/photosui/photospicker) | a SwiftUI control in `MyAppUI`; it hands Core `Data` from [`loadTransferable(type:)`](https://developer.apple.com/documentation/photosui/photospickeritem/loadtransferable(type:)) through a view-model action | no — the picker runs out of process and needs no photo-library permission ([PhotoKit privacy](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)) |
| Reading the photo library itself — [`PHPhotoLibrary`](https://developer.apple.com/documentation/photos/phphotolibrary/authorizationstatus(for:)) | adapter in `MyAppPlatform` | yes, with a permission |
| Work while suspended — [`BGTaskScheduler`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler) | registration in `App/` (in SwiftUI, the [`backgroundTask(_:action:)`](https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:)) scene modifier); submitting a request behind a port; the task's work a Core action | yes, for scheduling |

A notification is observed on the Simulator with `xcrun simctl push`; a background task
cannot be launched there at all — Apple's debugger route works only on a device
([Starting and terminating tasks during development](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development),
checked 2026-09-30). Adding a background mode or any capability is an ADR and a signing
change (`AGENTS.md` › "Security and human approval").

## Two platforms at compile time

`MyAppPlatform` also builds for macOS, because `swift test` runs the package on the host
(`docs/architecture.md` › Why the package also builds for macOS). An iOS-only framework
call — `BGTaskScheduler`, a UIKit type, `UIApplication.openSettingsURLString` — sits
inside `#if os(iOS)`, and so does its test; `just test-ios` runs that test on the iOS
Simulator, and CI's `Package Tests (iOS Simulator)` job runs it on every pull request.
Keep the `#if` around the smallest translation that needs it, never around a decision:
a Core decision is tested on the host, where the coverage floor sees it.

A framework that compiles on macOS may still refuse to run in a test process.
`UNUserNotificationCenter.current()` raises `bundleProxyForCurrentProcess is nil` in a
process with no app bundle (checked 2026-09-30 with a Swift script on the host), so a
notification adapter's test also belongs behind `#if os(iOS)`. Unverified: whether the
`just test-ios` runner gives it the bundle it needs — if not, the adapter's evidence is
the running app's, in the pull request.

**REQUIRED:** [references/testing-where.md](references/testing-where.md) for which test
proves what.

## A framework Core never imports

`.swiftlint.yml`'s `no_ui_import_in_core` and `ArchitectureBoundaryTests.forbiddenModules`
already ban UserNotifications, CoreLocation, Photos, PhotosUI, StoreKit, and WidgetKit
from `MyAppCore`. An app that adopts a framework neither list names yet — BackgroundTasks,
AVFoundation, HealthKit — adds it to both in the same pull request as the adapter;
`scripts/checks/core-ban-lists-agree.sh` (`just check-harness`) fails while they differ.

## Never reach for `@unchecked Sendable` or `nonisolated(unsafe)`

They turn the build green and leave the race, with the reason it was safe written
nowhere; using either to silence a diagnostic needs a human's sign-off (`AGENTS.md` ›
"Security and human approval"). The actual fix, in this order:

| The compiler says | The fix |
|---|---|
| `sending '…' risks causing data races` | Map to a Core value type inside the adapter; return the value. |
| a completion handler fires on an arbitrary queue | Call the framework's `async` variant (`notificationSettings()`, `requestAuthorization(options:)`), or wrap the handler once in `withCheckedThrowingContinuation`. |
| a framework delegate method is not isolated to your actor | Declare it `nonisolated`, extract the values it needs, then hop with `Task { @MainActor in … }` carrying only those values. |
| a framework type must be `Sendable` to be shared | It must not be shared. Keep it inside the adapter's actor and expose values. |
| a framework is not yet annotated for concurrency | `@preconcurrency import` it in the adapter only, and say why in one line. |

## Before you call it done

- [ ] The port takes and returns Core value types only; `MyAppCore` imports no framework
      (`just lint` runs `no_ui_import_in_core`, `just test` runs
      `ArchitectureBoundaryTests`).
- [ ] The permission is a Core enum, the adapter maps it one to one, and every decision
      about it has a Core test against the fake.
- [ ] The fake and one contract function live in `Tests/MyAppTestSupport`, run against
      the fake in `MyAppCoreTests` and against the adapter where it can run.
- [ ] Every usage description and `Info.plist` key is in `project.yml`, and the ADR for
      the permission or capability is written as Proposed.
- [ ] iOS-only code and its test sit behind `#if os(iOS)`; `just test-ios` passes.
- [ ] The pull request carries what no test can: the real prompt, the delivered
      notification, or the device run (`running-the-app`).
- [ ] No new `@unchecked Sendable`, `nonisolated(unsafe)`, or `try!`.
