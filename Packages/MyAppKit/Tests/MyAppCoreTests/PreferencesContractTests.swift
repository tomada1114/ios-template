import MyAppCore
import MyAppTestSupport
import Synchronization
import Testing

/// Answers every key its default and drops every write — breaks "a set value is read back
/// equal".
private struct WriteIgnoringPreferences: PreferencesStoring {
    func value<Value: PreferenceValue>(for key: PreferenceKey<Value>) -> Value {
        key.defaultValue
    }

    func set<Value: PreferenceValue>(_: Value, for _: PreferenceKey<Value>) {
        // Deliberately dropped.
    }
}

/// Stores every key in one slot, whatever its name — breaks "keys with different names
/// are independent".
private final class SingleSlotPreferences: PreferencesStoring {
    private let slot = Mutex<(any Sendable)?>(nil)

    func value<Value: PreferenceValue>(for key: PreferenceKey<Value>) -> Value {
        slot.withLock { $0 } as? Value ?? key.defaultValue
    }

    func set<Value: PreferenceValue>(_ value: Value, for _: PreferenceKey<Value>) {
        slot.withLock { $0 = value }
    }
}

/// The fake half of the `PreferencesStoring` contract suite: the same
/// ``PreferencesContract`` that `MyAppPlatformTests` runs against `UserDefaultsPreferences`
/// runs here against ``InMemoryPreferences``, so the fake cannot drift from the port.
@Suite("PreferencesContract, against the fake")
struct PreferencesContractTests {
    @Test
    func `the fake keeps the contract`() {
        PreferencesContract.check(InMemoryPreferences())
    }

    // The contract's own oracle: an implementation that breaks a promise must be
    // reported, or `check(_:)` would pass anything, the real adapter included.

    @Test
    func `a store that ignores set is reported`() {
        let violations = PreferencesContract.violations(of: WriteIgnoringPreferences())
        #expect(violations.contains("a Bool set to true did not read back true"))
        #expect(violations.contains { $0.hasPrefix("an Int set to 42") })
    }

    @Test
    func `a store that keeps every key under one name is reported`() {
        let violations = PreferencesContract.violations(of: SingleSlotPreferences())
        #expect(violations == ["setting contract.other changed contract.int to 7"])
    }

    // The port's fourth promise, which the contract cannot plant a value for.

    @Test
    func `a wrong-typed value answers the default`() {
        let preferences = InMemoryPreferences()
        let key = PreferenceKey<Bool>(name: "test.wrongType", defaultValue: true)
        preferences.storeRaw("not a Bool", forName: key.name)
        #expect(preferences.value(for: key) == true)
    }

    @Test
    func `the snapshot shows what was set, by key name`() {
        let preferences = InMemoryPreferences()
        preferences.set(true, for: PreferenceKeys.hideCompleted)
        #expect(preferences.snapshot["todoList.hideCompleted"] as? Bool == true)
        #expect(preferences.snapshot.count == 1)
    }
}
