import MyAppCore
import Testing

/// The promises ``MyAppCore/PreferencesStoring`` makes, checked against any
/// implementation.
///
/// A fake stands in for the adapter only while both keep the port's promises, so they are
/// written once, here, over the protocol. `MyAppCoreTests` runs ``check(_:)`` against
/// ``InMemoryPreferences``; `MyAppPlatformTests` runs it against `UserDefaultsPreferences`
/// on a scratch suite. Both run under `just test` and in CI.
///
/// The port's fourth promise — a stored value of the wrong type answers the default — is
/// not checked here: the port has no way to write a raw value, so each implementation's
/// own tests plant one (`InMemoryPreferences.storeRaw`, `UserDefaults` directly).
///
/// The keys are the contract's own, never ``MyAppCore/PreferenceKeys``, so a contract run
/// never touches a real setting.
package enum PreferencesContract {
    /// Contract-local keys. Their defaults are values the contract never sets, so a read
    /// that answers the default is told apart from one that answers a stored value.
    enum Keys {
        static let bool = PreferenceKey<Bool>(name: "contract.bool", defaultValue: false)
        static let int = PreferenceKey<Int>(name: "contract.int", defaultValue: 0)
        static let string = PreferenceKey<String>(name: "contract.string", defaultValue: "")
        static let other = PreferenceKey<Int>(name: "contract.other", defaultValue: -1)
    }

    /// Fixed values the contract stores.
    enum Fixture {
        static let storedInt = 42
        static let otherInt = 7
        static let storedString = "stored"
    }

    /// A description of every broken promise, empty when `preferences` keeps them all.
    /// `preferences` must start empty.
    ///
    /// Separate from ``check(_:)`` so a test can hand it an implementation that breaks a
    /// promise and see the contract notice — the proof it is not vacuous.
    package static func violations(of preferences: some PreferencesStoring) -> [String] {
        unsetKeysAnswerTheirDefault(preferences)
            + setValuesReadBackEqual(preferences)
            + keysAreIndependent(preferences)
    }

    /// Records an issue for every promise `preferences` breaks. `preferences` must start
    /// empty.
    package static func check(_ preferences: some PreferencesStoring) {
        let broken = violations(of: preferences)
        #expect(
            broken.isEmpty,
            "\(type(of: preferences)) breaks the PreferencesStoring contract: \(broken)",
        )
    }

    // MARK: - Clauses

    /// Promise 1: an unset key answers its `defaultValue`.
    private static func unsetKeysAnswerTheirDefault(
        _ preferences: some PreferencesStoring,
    ) -> [String] {
        var broken: [String] = []
        if preferences.value(for: Keys.bool) != Keys.bool.defaultValue {
            broken.append("an unset Bool key did not answer its default")
        }
        if preferences.value(for: Keys.int) != Keys.int.defaultValue {
            broken.append("an unset Int key did not answer its default")
        }
        if preferences.value(for: Keys.string) != Keys.string.defaultValue {
            broken.append("an unset String key did not answer its default")
        }
        return broken
    }

    /// Promise 2: a set value is read back equal — including a second set that replaces
    /// the first.
    private static func setValuesReadBackEqual(
        _ preferences: some PreferencesStoring,
    ) -> [String] {
        var broken: [String] = []
        preferences.set(true, for: Keys.bool)
        if preferences.value(for: Keys.bool) != true {
            broken.append("a Bool set to true did not read back true")
        }
        preferences.set(false, for: Keys.bool)
        if preferences.value(for: Keys.bool) != false {
            broken.append("a Bool set back to false did not read back false")
        }
        preferences.set(Fixture.storedInt, for: Keys.int)
        let int = preferences.value(for: Keys.int)
        if int != Fixture.storedInt {
            broken.append("an Int set to \(Fixture.storedInt) read back \(int)")
        }
        preferences.set(Fixture.storedString, for: Keys.string)
        let string = preferences.value(for: Keys.string)
        if string != Fixture.storedString {
            broken.append("a String set to \(Fixture.storedString) read back \(string)")
        }
        return broken
    }

    /// Promise 3: keys with different names are independent. Runs after promise 2, so
    /// `contract.int` already holds a value that `contract.other` must not see.
    private static func keysAreIndependent(_ preferences: some PreferencesStoring) -> [String] {
        var broken: [String] = []
        let untouched = preferences.value(for: Keys.other)
        if untouched != Keys.other.defaultValue {
            broken.append("setting contract.int changed contract.other to \(untouched)")
        }
        preferences.set(Fixture.otherInt, for: Keys.other)
        let int = preferences.value(for: Keys.int)
        if int != Fixture.storedInt {
            broken.append("setting contract.other changed contract.int to \(int)")
        }
        return broken
    }
}
