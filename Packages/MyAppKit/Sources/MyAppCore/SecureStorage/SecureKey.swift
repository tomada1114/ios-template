/// The name a secret is stored under in a ``SecureStoring``.
///
/// A type of its own rather than a bare `String`, so a secret is only ever read or
/// written through a constant declared in ``SecureKeys``, where a test pins its name —
/// never through a string literal at a call site.
public struct SecureKey: Hashable, Sendable {
    /// The name the secret is stored under. Contract once a build has shipped: a renamed
    /// key reads as absent on every device that stored the old one, and the old secret
    /// stays behind.
    public let name: String

    /// Creates a key stored under `name`.
    public init(name: String) {
        self.name = name
    }
}
