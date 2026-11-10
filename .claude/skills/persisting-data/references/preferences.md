# Preferences

`PreferencesStoring` is the seam for small user settings — the ones that must survive a
relaunch but are not the user's data. The port and its keys are in
`MyAppCore/Preferences`, the `UserDefaultsPreferences` adapter in
`MyAppPlatform/Preferences`, and `InMemoryPreferences` plus `PreferencesContract` in
`Tests/MyAppTestSupport`. The worked example is Hide Completed on the to-do list.

```swift
public protocol PreferencesStoring: Sendable {
    func value<Value: PreferenceValue>(for key: PreferenceKey<Value>) -> Value
    func set<Value: PreferenceValue>(_ value: Value, for key: PreferenceKey<Value>)
}
```

- **Synchronous, unlike every other port.** `UserDefaults` is synchronous and
  thread-safe, so an `async` port would only add suspension points — and the reentrancy
  they bring — to a `@MainActor` view model. Nothing can fail that a caller could act
  on, so it does not throw either: an unset key, or a stored value of the wrong type,
  answers the key's default, and the adapter logs the wrong type under
  `AppLog.preferences`. The adapter stores only its suite's name, so it is a `Sendable`
  struct; the fake is a final class over a `Mutex`.
- **A key carries its type and default.** `PreferenceKey<Value>` pairs a name with a
  default, and `PreferenceValue` admits only `Bool`, `Int`, `Double`, and `String` —
  types `UserDefaults` stores natively. A richer setting is stored as one of these and
  converted in Core.
- **Key names are contract.** Every key is a constant in `PreferenceKeys`, and
  `PreferenceKeysTests` pins each name and default. A renamed key reads as unset, so a
  rename silently resets every user's setting: it is a migration in Core — read the old
  key, write the new one, with a test that starts from the old value — not an edit to
  that test (`AGENTS.md`'s "What is contract and what is private").
- **Read on load, not in `init`.** `TodoListViewModel` reads `hideCompleted` at the
  start of `load()`, so constructing a view model still touches no storage.
- **UI tests start clean.** `UserDefaultsPreferences.scratch(suiteName:)` removes a
  suite's domain before handing back an adapter over it. Under `-uiTesting`, `App/` uses
  a scratch suite named after `AppLog.subsystem`, because `just uitest` reuses the
  simulator and one run's setting would otherwise leak into the next. Unit tests of the
  adapter each use a scratch suite named with a fresh UUID.
- **`UserDefaults` is a required-reason API.** What an App Store upload then needs in
  `PrivacyInfo.xcprivacy` is `integrating-system-apis`' `references/permissions.md`
  › "The privacy manifest".
