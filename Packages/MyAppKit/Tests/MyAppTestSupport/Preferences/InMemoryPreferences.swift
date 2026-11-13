import MyAppCore
import Synchronization

/// The one fake of ``MyAppCore/PreferencesStoring``, shared by every test target.
///
/// A fake, not a mock: a real conforming implementation that keeps values in a
/// dictionary, which a test reads back through ``snapshot``. `PreferencesContract` holds
/// it to the same promises as `UserDefaultsPreferences`, so a view model tested against
/// it is tested against the port.
///
/// A final class rather than an actor, because the port is synchronous: its only stored
/// property is a `Mutex`, so the compiler checks it `Sendable` without an escape hatch.
package final class InMemoryPreferences: PreferencesStoring {
    private let storage = Mutex<[String: any Sendable]>([:])

    /// What the fake holds right now, by key name.
    package var snapshot: [String: any Sendable] {
        storage.withLock { $0 }
    }

    /// Starts empty: every key answers its default.
    package init() {
        // The empty dictionary is the whole initial state.
    }

    /// Stores `value` under `name` whatever its type — the fake's way to plant a value of
    /// the wrong type, as an older build or a hand edit could leave behind.
    package func storeRaw(_ value: any Sendable, forName name: String) {
        storage.withLock { $0[name] = value }
    }

    package func value<Value: PreferenceValue>(for key: PreferenceKey<Value>) -> Value {
        storage.withLock { $0[key.name] } as? Value ?? key.defaultValue
    }

    package func set<Value: PreferenceValue>(_ value: Value, for key: PreferenceKey<Value>) {
        storage.withLock { $0[key.name] = value }
    }
}
