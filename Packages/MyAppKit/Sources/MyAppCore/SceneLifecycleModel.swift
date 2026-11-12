import Observation

/// One scene's lifecycle: the phases that scene reports, when they call for a quiet
/// refresh of the shared list, and whether this scene is the one window that presents the
/// shared list's failure (``todoListFailure``) — which depends on the phase too.
///
/// Owned per scene, in `@State` on `App/`'s scene root, beside its ``NavigationModel``,
/// so its state lives exactly as long as the window: a window iOS discards and rebuilds
/// starts a new one. ``AppModel/makeSceneLifecycleModel()`` builds it over the shared
/// ``TodoListViewModel``. It is also the scene's identity (``id``): the per-scene model
/// every window already has.
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
    /// This scene's identity: what its views pass as an action's `from:`, so the action's
    /// failure presents in this window.
    public let id: SceneID

    /// Whether the scene has been active since this model was built.
    private var hasBeenActive = false
    /// Whether the scene went to the background since it was last active.
    private var wentToBackground = false
    private let list: TodoListViewModel
    private let openScenes: OpenScenes

    /// The shared list's failure if this is the one window that presents it, and `nil` in
    /// every other window: what this window's alert renders. The list is app-wide and
    /// every window renders it, so a failure presented wherever it is set would show in
    /// all of them at once, and one window's OK would pull the alert out from under the
    /// others (#133). A new shared model's failure gets the same pair of members here.
    public var todoListFailure: TodoListFailure? {
        presentsFailure(from: list.failureScene) ? list.failure : nil
    }

    /// Creates the model for a scene that has reported nothing yet, and so is not among
    /// `openScenes` yet: a spare model a re-render builds and discards never is.
    init(list: TodoListViewModel, openScenes: OpenScenes) {
        self.list = list
        self.openScenes = openScenes
        id = openScenes.makeSceneID()
    }

    /// Clears the shared list's failure if this window is presenting it: what this
    /// window's alert button calls. It acts only in its own window, as a sheet's dismissal
    /// names its sheet, so a tap that lands after another window's failure replaced this
    /// one dismisses nothing the person did not see.
    public func dismissTodoListFailure() {
        if presentsFailure(from: list.failureScene) {
            list.dismissFailure()
        }
    }

    /// Whether this scene is the one window that presents a failure the scene `origin`
    /// caused — `nil` when no scene did. Exactly one open window answers `true`, so one
    /// failure is one alert however many windows show the model that holds it:
    ///
    /// - `origin` itself, while it is in the foreground: the alert shows beside the row
    ///   whose change failed.
    /// - Otherwise — no scene caused it, or the one that did is in the background or
    ///   closed — the window that has been in the foreground longest, so the failure is
    ///   never left where nobody can see it, and of the windows that did not cause it,
    ///   one arriving later never takes it.
    /// - While no window is in the foreground, the same choice among all open windows, so
    ///   an alert that is up stays up while the app is away.
    ///
    /// A scene that has reported no phase is not a window, and presents nothing.
    private func presentsFailure(from origin: SceneID?) -> Bool {
        openScenes.presenter(ofFailureFrom: origin) == id
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
    ///
    /// The first phase a scene reports makes it an open window, and every phase but the
    /// background puts it in the foreground (``todoListFailure``).
    public func sceneDidEnter(_ phase: LifecyclePhase) {
        self.phase = phase
        switch phase {
        case .active:
            openScenes.record(self, isInForeground: true)
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
            openScenes.record(self, isInForeground: false)
            wentToBackground = true

        case .inactive:
            openScenes.record(self, isInForeground: true)
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
