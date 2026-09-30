#if DEBUG
    import MyAppCore
    import Synchronization

    /// Preview-only preferences, so a `#Preview` can start with a setting already on and
    /// never writes to the real `UserDefaults`.
    ///
    /// `MyAppTestSupport`'s fake is test code no shipped module may import, and the
    /// `UserDefaults` adapter lives in `MyAppPlatform`, which `MyAppUI` must not see —
    /// hence this small copy, compiled into Debug builds only. A final class whose only
    /// stored property is a `Mutex`, so it is checked `Sendable`.
    final class PreviewPreferences: PreferencesStoring {
        private let storage: Mutex<[String: any Sendable]>

        /// Starts empty: every key answers its default.
        init() {
            storage = Mutex([:])
        }

        /// Starts with Hide Completed set to `hideCompleted`.
        init(hideCompleted: Bool) {
            storage = Mutex([PreferenceKeys.hideCompleted.name: hideCompleted])
        }

        func value<Value: PreferenceValue>(for key: PreferenceKey<Value>) -> Value {
            storage.withLock { $0[key.name] } as? Value ?? key.defaultValue
        }

        func set<Value: PreferenceValue>(_ value: Value, for key: PreferenceKey<Value>) {
            storage.withLock { $0[key.name] = value }
        }
    }
#endif
