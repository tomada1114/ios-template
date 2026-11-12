/// One scene's lifecycle, as much of it as decides a reload: ``AppModel`` keeps one per
/// ``SceneID``.
struct SceneLifecycle {
    private var hasBeenActive = false
    private var wentToBackground = false

    /// Applies `phase`, and answers whether the scene has just come back to the foreground
    /// from the background.
    mutating func enter(_ phase: LifecyclePhase) -> Bool {
        switch phase {
        case .active:
            let returned = hasBeenActive && wentToBackground
            hasBeenActive = true
            wentToBackground = false
            return returned

        case .background:
            wentToBackground = true
            return false

        case .inactive:
            return false
        }
    }
}
