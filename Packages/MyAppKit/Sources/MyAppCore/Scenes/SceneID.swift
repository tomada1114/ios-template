/// Which scene — which window — something belongs to: the name a view passes with an
/// action (`toggle(_:from:)`), so a failure of that action presents in the window that
/// asked for it rather than in every window showing the shared list (#133).
///
/// Opaque, and only ever compared: two values are equal when they came from the same
/// scene model (``SceneLifecycleModel/id``). It is the identity of an object made for
/// the purpose, never an injected `UUID` or a counter, so making one reads nothing,
/// changes nothing, and a test that pins the app's identifier source still gets a
/// different identity per scene.
public struct SceneID: Hashable, Sendable {
    /// What is compared. A class only for its identity, kept alive by every copy of the
    /// value, so no later scene can be mistaken for this one.
    private final class Token: Sendable {}

    private let token = Token()

    /// A new identity, equal only to its own copies.
    init() {
        // Nothing to set up: the token is the identity.
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token === rhs.token
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(token))
    }
}
