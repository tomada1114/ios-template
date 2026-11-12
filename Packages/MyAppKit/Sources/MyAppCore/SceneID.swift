/// Which scene — which window — something belongs to: the name a view passes with an
/// action (`toggle(_:from:)`), so a failure of that action presents in the window that
/// asked for it rather than in every window showing the shared list (#133).
///
/// Opaque, and only ever compared. ``SceneLifecycleModel/id`` is the one source of one:
/// a number ``AppModel`` issues once per scene model, never an injected `UUID`, so a test
/// that pins the app's identifier source still gets a different identity per scene.
public struct SceneID: Hashable, Sendable {
    private let number: Int

    init(number: Int) {
        self.number = number
    }
}
