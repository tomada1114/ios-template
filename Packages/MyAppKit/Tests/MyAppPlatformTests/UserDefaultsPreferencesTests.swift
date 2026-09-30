import Foundation
import MyAppCore
import MyAppPlatform
import MyAppTestSupport
import Testing

/// The adapter half of the `PreferencesStoring` contract suite, plus what only the
/// adapter can get wrong: a value of the wrong type already in `UserDefaults`, two
/// adapters over one suite, and a scratch suite starting clean.
///
/// `UserDefaults` runs on the host, so these run under plain `just test` and in CI. Each
/// test works in its own suite, named with a fresh UUID and removed when the test ends,
/// so parallel tests share nothing and no run leaves a domain behind.
@Suite("UserDefaultsPreferences")
struct UserDefaultsPreferencesTests {
    /// A suite name no other test uses.
    static func uniqueSuiteName() -> String {
        "test.\(UUID().uuidString)"
    }

    /// Removes `suiteName`'s domain, as a test's `defer` does when it ends.
    static func removeDomain(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test
    func `the UserDefaults adapter keeps the contract`() {
        let suiteName = Self.uniqueSuiteName()
        defer { Self.removeDomain(suiteName) }
        PreferencesContract.check(UserDefaultsPreferences.scratch(suiteName: suiteName))
    }

    /// `"yes"` is what `UserDefaults.bool(forKey:)` would read as `true`: an adapter that
    /// used it instead of a typed cast would answer `true` here, not the default.
    @Test
    func `a wrong-typed stored value answers the default`() throws {
        let suiteName = Self.uniqueSuiteName()
        defer { Self.removeDomain(suiteName) }
        let preferences = UserDefaultsPreferences.scratch(suiteName: suiteName)
        let key = PreferenceKey<Bool>(name: "test.flag", defaultValue: false)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set("yes", forKey: key.name)
        #expect(preferences.value(for: key) == false)
    }

    @Test
    func `two adapters on one suite see the same value`() {
        let suiteName = Self.uniqueSuiteName()
        defer { Self.removeDomain(suiteName) }
        let writer = UserDefaultsPreferences.scratch(suiteName: suiteName)
        let reader = UserDefaultsPreferences(suiteName: suiteName)
        let key = PreferenceKey<String>(name: "test.shared", defaultValue: "")
        writer.set("shared", for: key)
        #expect(reader.value(for: key) == "shared")
    }

    @Test
    func `scratch starts empty`() {
        let suiteName = Self.uniqueSuiteName()
        defer { Self.removeDomain(suiteName) }
        let key = PreferenceKey<Bool>(name: "test.leftover", defaultValue: false)
        UserDefaultsPreferences(suiteName: suiteName).set(true, for: key)
        let scratch = UserDefaultsPreferences.scratch(suiteName: suiteName)
        #expect(scratch.value(for: key) == false)
    }
}
