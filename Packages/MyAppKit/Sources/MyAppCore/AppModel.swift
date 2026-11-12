import Foundation
import Observation

/// The app's model: the view models every scene shares, and one factory per route whose
/// screen needs a view model of its own.
///
/// `App/` builds it once, from the adapters it chose, and hands it the **ports** through
/// this initializer; the root view reads the shared models from it and asks it for a
/// pushed screen's model. That keeps the wiring — which model is built over which port,
/// and what a route's screen shares with the list — in Core, where `AppModelTests` and
/// the coverage floor see it, rather than in `App/` or in a destination `switch` in
/// `MyAppUI`, which may not import the adapters (the `designing-core-logic` skill's
/// `references/view-models.md`).
///
/// Not a service locator: there is no registry, no lookup by type, and no global. Every
/// dependency is a named stored property set from this initializer, and a route's model
/// is built by a named `make…ViewModel(…)` method.
///
/// It is app-level, never per scene: what it holds is what every window shows. Which
/// screens a window has pushed is that window's own ``NavigationModel``. The one thing it
/// keeps per scene is where each scene stands in its lifecycle
/// (``sceneDidEnter(_:scene:)``), keyed by the ``SceneID`` that scene passes.
@MainActor
@Observable
public final class AppModel {
    /// The to-do list every scene shows, built once over the ports, so two windows show
    /// the same items and a pushed detail screen shows what the list shows.
    public let todoList: TodoListViewModel

    /// Per scene, whether it has been active once, and whether it went to the background
    /// since it was last active. A closed scene's entry stays, armed or not, and is never
    /// read again: a closed scene reports nothing more.
    private var scenes: [SceneID: SceneLifecycle] = [:]

    /// Builds the shared view models over `repository` and `preferences`. Nothing is read
    /// until a view model's own `load()`: construction stays free of side effects.
    ///
    /// `now` and `makeID` reach every view model that stamps a new value, so a test pins
    /// both here once. `preferences` has no default, for the reason
    /// ``TodoListViewModel/init(repository:preferences:now:makeID:)`` gives.
    public init(
        repository: any TodoRepository,
        preferences: any PreferencesStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        todoList = TodoListViewModel(
            repository: repository,
            preferences: preferences,
            now: now,
            makeID: makeID,
        )
    }

    /// Records that `scene` entered `phase`, and reloads the shared list when that scene
    /// comes back to the foreground after being in the background.
    ///
    /// Each scene is tracked on its own: the scene that returns reloads, whatever the
    /// others are doing, and two windows returning together each reload — two overlapping
    /// ``TodoListViewModel/load()`` calls, of which the list applies only the newest.
    /// A return passes through `inactive` (background → inactive → active), so a scene
    /// stays armed until its next active. A plain inactive → active change — Control
    /// Center, a system alert — is not a return and reloads nothing. A scene's first active
    /// never reloads, whatever it reported before it: the list's `.task` owns the first
    /// load, and a launch would otherwise load twice.
    ///
    /// The phase is recorded before anything suspends, so phases forwarded in order are
    /// applied in order.
    public func sceneDidEnter(_ phase: LifecyclePhase, scene: SceneID) async {
        var lifecycle = scenes[scene] ?? SceneLifecycle()
        let returned = lifecycle.enter(phase)
        scenes[scene] = lifecycle
        guard returned else {
            return
        }
        AppLog.todos.debug("lifecycle: a scene returned from the background; reloading")
        await todoList.load()
    }

    /// The view model of the screen ``AppRoute/todoDetail(_:)`` pushes for `id`.
    ///
    /// A new model on every call — the pushed screen owns the one it is given — over the
    /// shared ``todoList``, so the detail screen shows the item as the list holds it now,
    /// and a toggle there is the list's toggle.
    public func makeTodoDetailViewModel(id: TodoItem.ID) -> TodoDetailViewModel {
        TodoDetailViewModel(list: todoList, id: id)
    }
}
