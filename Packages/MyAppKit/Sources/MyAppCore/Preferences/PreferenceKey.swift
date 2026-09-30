/// A stored preference: the name it is kept under, and what it answers until it is set.
///
/// The value type travels with the key, so a read and a write of one key can never
/// disagree about its type. Declare every key the app stores in ``PreferenceKeys``, where
/// a test pins its name.
public struct PreferenceKey<Value: PreferenceValue>: Sendable {
    /// The name the value is stored under. Contract once a build has shipped: a renamed
    /// key reads as unset on every device that stored the old one.
    public let name: String
    /// What ``PreferencesStoring/value(for:)`` answers while nothing valid is stored.
    public let defaultValue: Value

    /// Creates a key stored under `name` that answers `defaultValue` until it is set.
    public init(name: String, defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}
