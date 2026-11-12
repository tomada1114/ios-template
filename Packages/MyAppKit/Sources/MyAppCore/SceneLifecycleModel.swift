import Foundation
import Observation

/// One scene's lifecycle: the phases that scene reports, and when they call for a quiet
/// refresh of the shared list.
///
/// Owned per scene, in `@State` on `App/`'s scene root, beside its ``NavigationModel``,
/// so its state lives exactly as long as the window: a window iOS discards and rebuilds
/// starts a new one. ``AppModel/makeSceneLifecycleModel()`` builds it over the shared
/// ``TodoListViewModel``.
///
/// Two steps, so phases are applied in the order the scene reports them however tasks
/// are scheduled: ``sceneDidEnter(_:)`` records a phase synchronously, and
/// ``refreshIfNeeded()``, which the scene root calls from a `Task` after it, runs the
/// refresh a recorded phase asked for.
@MainActor
@Observable
public final class SceneLifecycleModel {
    /// The phase the scene reported last, or `nil` before its first report.
    public private(set) var phase: LifecyclePhase?
    /// Whether a refresh was asked for and has not run yet.
    public private(set) var isRefreshPending = false

    /// Whether the scene has been active since this model was built.
    private var hasBeenActive = false
    /// Whether the scene went to the background since it was last active.
    private var wentToBackground = false
    private let list: TodoListViewModel

    /// Creates the model for a scene that has reported nothing yet.
    init(list: TodoListViewModel) {
        self.list = list
    }

    /// Records that the scene entered `phase`. Synchronous, and suspends nowhere.
    ///
    /// A refresh is asked for when the scene becomes active for the first time, or again
    /// after going to the background — a return passes through `inactive`
    /// (background → inactive → active), so the scene stays armed until its next active. A
    /// plain inactive → active change — Control Center, a system alert — asks for nothing:
    /// the scene never left the screen. Whether the asked-for refresh fetches is the
    /// list's (``TodoListViewModel/refresh()``): at launch the list is still idle or
    /// loading, so a scene's first active fetches nothing and a launch loads once.
    public func sceneDidEnter(_ phase: LifecyclePhase) {
        self.phase = phase
        switch phase {
        case .active:
            // A local, not `self.hasBeenActive`: the log message is an autoclosure, and
            // SwiftFormat's redundantSelf rule would strip the `self` it needs.
            let isFirstActive = !hasBeenActive
            if isFirstActive || wentToBackground {
                isRefreshPending = true
                AppLog.lifecycle.debug(
                    "active: refresh requested (first active: \(isFirstActive, privacy: .public))",
                )
            }
            hasBeenActive = true
            wentToBackground = false

        case .background:
            wentToBackground = true

        case .inactive:
            break
        }
    }

    /// Runs the refresh a recorded phase asked for, once, and nothing otherwise.
    public func refreshIfNeeded() async {
        guard isRefreshPending else {
            return
        }
        isRefreshPending = false
        await list.refresh()
    }
}
