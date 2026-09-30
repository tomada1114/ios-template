import Foundation
import MyAppCore

/// The `UserDefaults`-backed adapter for ``MyAppCore/PreferencesStoring``.
///
/// Translation only, in the manner of `URLSessionHTTPClient`: a key's name is the
/// `UserDefaults` key, and a value is stored as the property-list type it already is.
/// `PreferencesContract` checks it in `MyAppPlatformTests`, on a scratch suite, under
/// plain `just test`.
///
/// It stores only the suite's name and resolves the `UserDefaults` on each call, so it
/// is `Sendable` whether or not the SDK marks `UserDefaults` so — never store one here.
///
/// A value read back is cast with `as?`. `UserDefaults` hands numbers back as `NSNumber`,
/// which bridges between Swift's number types: an `Int` stored under a key read as a
/// `Double` answers that number, not the default. A `String` under a `Bool` key — or any
/// other value no bridge reaches — answers the default and is logged.
public struct UserDefaultsPreferences: PreferencesStoring {
    private let suiteName: String?

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// An adapter over the suite named `suiteName`, or over the app's standard defaults
    /// when it is `nil` — what the app runs on.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// An adapter over `suiteName` after removing everything stored there, so a UI test
    /// run or a unit test starts from every key's default. Never pass the standard
    /// defaults' domain.
    public static func scratch(suiteName: String) -> Self {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        return Self(suiteName: suiteName)
    }

    public func value<Value: PreferenceValue>(for key: PreferenceKey<Value>) -> Value {
        guard let stored = defaults.object(forKey: key.name) else {
            return key.defaultValue
        }
        guard let value = stored as? Value else {
            let storedType = String(describing: type(of: stored))
            let expectedType = String(describing: Value.self)
            AppLog.preferences.error(
                """
                \(key.name, privacy: .public) holds a \(storedType, privacy: .public), \
                not a \(expectedType, privacy: .public); answering its default
                """,
            )
            return key.defaultValue
        }
        return value
    }

    public func set<Value: PreferenceValue>(_ value: Value, for key: PreferenceKey<Value>) {
        defaults.set(value, forKey: key.name)
    }
}
