/// The port for small user preferences — a setting that must survive a relaunch, such as
/// ``PreferenceKeys/hideCompleted``. `UserDefaultsPreferences` in `MyAppPlatform` is the
/// adapter; `InMemoryPreferences` in `MyAppTestSupport` is the fake.
///
/// Synchronous and non-throwing, unlike the repositories' `async throws`: `UserDefaults`
/// is synchronous and thread-safe, and an `async` port would only add suspension points
/// — and the reentrancy they bring — to a `@MainActor` view model for nothing. Nothing to
/// report can go wrong either: a missing or unreadable value is the default.
///
/// Every implementation promises:
/// 1. An unset key answers its ``PreferenceKey/defaultValue``.
/// 2. A set value is read back equal.
/// 3. Keys with different names are independent.
/// 4. A stored value of the wrong type answers ``PreferenceKey/defaultValue``.
///
/// `PreferencesContract` in `MyAppTestSupport` checks the first three against the fake
/// and the adapter; the fourth needs a raw write the port does not offer, so each
/// implementation's own tests plant one.
public protocol PreferencesStoring: Sendable {
    /// The value stored under `key`, or its default when none is stored or the stored
    /// value is not a `Value`.
    func value<Value: PreferenceValue>(for key: PreferenceKey<Value>) -> Value

    /// Stores `value` under `key`, replacing whatever was there.
    func set<Value: PreferenceValue>(_ value: Value, for key: PreferenceKey<Value>)
}
