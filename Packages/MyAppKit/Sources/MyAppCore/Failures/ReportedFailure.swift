/// A failure of a model every scene shares, with the scene whose action caused it: what
/// such a model holds while a failure waits to be dismissed.
///
/// One value rather than a failure and a scene side by side, so the two cannot disagree.
/// A window renders it only through its own ``SceneLifecycleModel/presented(_:)``, which
/// answers in exactly one window, and dismisses it by handing the same value back, so a
/// tap cannot dismiss a failure that replaced the one it was shown for (#133).
public struct ReportedFailure<Failure: PresentableFailure & Equatable>: Equatable, Sendable {
    /// What failed, as the alert words it.
    public let failure: Failure
    /// The scene whose action caused it, or `nil` when no scene did.
    public let scene: SceneID?
    /// Which report this is, and so which window presents it (``OpenScenes``).
    let claim: OpenScenes.Claim
}
