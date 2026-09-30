# What can be tested where

Each part of an integration is proven by exactly one kind of check, chosen by what is
under test, not by what is convenient. `.claude/rules/testing.md` › Where a Test Goes
states the four kinds; this is the same split applied to a system API.

| What is under test | The test | Where | Runs in |
|---|---|---|---|
| A decision — when to ask, what a denied state shows, what a delivered notification changes | Swift Testing against the port's fake | `Tests/MyAppCoreTests` | `just test`, CI `test` — inside the coverage floor |
| The port's promises | the contract function, against the fake | `Tests/MyAppCoreTests` | `just test`, CI `test` |
| Translation over a framework that runs on the host (SwiftData, Foundation) | the contract function and adapter-only cases, against the real adapter | `Tests/MyAppPlatformTests` | `just test`, CI `test` |
| Translation through an iOS-only API, or one that needs an app process | the same, inside `#if os(iOS)` | `Tests/MyAppPlatformTests` | `just test-ios`, CI `Package Tests (iOS Simulator)` — compiled away under `swift test` |
| The wiring in `App/` — the adapter handed over, a delegate or task handler registered | the launch test, when that wiring is what could break | `LaunchUITests/` | `just uitest`, CI `app` |
| A real prompt, a delivered push, the camera, a background launch | none — a person on the Simulator or a device | the pull request | nowhere; the evidence is a screenshot or a log excerpt (`running-the-app`) |

## Reading the table

- **The top row is the default.** If an adapter seems to need a test for a decision,
  the decision is in the wrong module: move it into Core. Adapters stay
  translation-only precisely so the rows below it never hold the only test of a rule.
- **`just test-ios` is not part of `just check`.** Only CI's
  `Package Tests (iOS Simulator)` job and a local `just test-ios` run it, and the
  coverage floor never measures it. Run it yourself before the pull request when you
  touched code behind `#if os(iOS)`.
- **"Runs on the host" is checked, not assumed.** A framework can compile for macOS and
  still refuse a test process: `UNUserNotificationCenter.current()` raises
  `bundleProxyForCurrentProcess is nil` without an app bundle (checked 2026-09-30).
  When a host test crashes like that, the test moves behind `#if os(iOS)`; it is never
  disabled (`AGENTS.md` › "Security and human approval").
- **The Simulator answers more than it seems.** `xcrun simctl privacy` grants or revokes
  the services its help lists, `xcrun simctl push` delivers a notification payload, and
  `xcrun simctl openurl` opens a link — so a permission's denied path and a
  notification's handling are observable without a device
  ([references/permissions.md](permissions.md) has the per-Xcode list).
- **Only a device shows** real APNs delivery, the camera, and a background task launch:
  Apple's debugger route to launch a `BGTaskScheduler` task works only on a device
  ([Starting and terminating tasks during development](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development),
  checked 2026-09-30). No gate runs one; a person does, and says so in the pull request.

## The fake for a permission

A permission port's fake is an actor in `Tests/MyAppTestSupport` that starts in the
state a test hands it and records what it was asked, like `InMemoryTodoRepository`:

```swift
package actor FakeNotificationScheduler: NotificationScheduling {
    package private(set) var permission: NotificationPermission
    package private(set) var requests: [ReminderRequest] = []
    private let answer: NotificationPermission

    package init(permission: NotificationPermission = .notDetermined, answers answer: NotificationPermission = .authorized) {
        self.permission = permission
        self.answer = answer
    }

    package func currentPermission() -> NotificationPermission { permission }

    package func requestPermission() -> NotificationPermission {
        if permission == .notDetermined { permission = answer }
        return permission
    }

    package func schedule(_ request: ReminderRequest) { requests.append(request) }
}
```

The names are illustrative — the template ships no notification port. What carries
over: the fake answers "not determined → the prompt's answer" once and then keeps its
state, as the system does after the first prompt
([Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications),
checked 2026-09-30), and that promise is a clause in the port's `///` and its contract
function, so the fake and the adapter are held to it together.
