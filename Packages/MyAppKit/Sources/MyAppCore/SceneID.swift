import Foundation

/// One scene's identity, so ``AppModel`` tells two windows' lifecycles apart.
///
/// Opaque: `App/` makes one per scene, keeps it as long as the scene's view tree, and
/// passes it with every phase that scene reports. Nothing reads what is inside it.
public struct SceneID: Hashable, Sendable {
    private let id: UUID

    /// A new identity, distinct from every other one. No test needs to know its value, so
    /// unlike a ``TodoItem``'s identifier it takes no injected `makeID`.
    public init() {
        id = UUID()
    }
}
