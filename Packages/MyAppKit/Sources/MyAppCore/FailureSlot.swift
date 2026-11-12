/// The one failure a shared model holds at a time, and its place among the open windows:
/// reporting a failure claims a presenting window for it, and dismissing or replacing it
/// gives the claim up. A new shared model keeps one of these, built over the
/// ``OpenScenes`` ``AppModel`` hands it, and its failure then goes through the same
/// ``SceneLifecycleModel/presented(_:)`` as every other.
@MainActor
struct FailureSlot<Failure: PresentableFailure & Equatable> {
    /// The failure waiting to be dismissed, or `nil`.
    private(set) var reported: ReportedFailure<Failure>?
    private let openScenes: OpenScenes

    init(openScenes: OpenScenes) {
        self.openScenes = openScenes
    }

    /// Holds `failure`, caused by `scene`, in place of whatever was held: one failure at
    /// a time, as in one window. Its presenting window is chosen afresh.
    mutating func report(_ failure: Failure, from scene: SceneID?) {
        dismiss()
        reported = ReportedFailure(
            failure: failure,
            scene: scene,
            claim: openScenes.claim(forFailureFrom: scene),
        )
    }

    /// Clears the failure, whichever window presents it.
    mutating func dismiss() {
        if let reported {
            openScenes.release(reported.claim)
        }
        reported = nil
    }

    /// Clears the failure if it is still `shown`, the one an alert was presenting when
    /// its button was tapped, and otherwise does nothing.
    mutating func dismiss(_ shown: ReportedFailure<Failure>?) {
        if shown != nil, shown == reported {
            dismiss()
        }
    }
}
