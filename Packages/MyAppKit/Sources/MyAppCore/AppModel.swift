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
/// screens a window has pushed is that window's own ``NavigationModel``, and where it
/// stands in its lifecycle is its own ``SceneLifecycleModel``, which it builds here —
/// each over the one list of open windows it keeps, from which a scene learns whether it
/// is the window that presents a failure.
@MainActor
@Observable
public final class AppModel {
    /// The to-do list every scene shows, built once over the ports, so two windows show
    /// the same items and a pushed detail screen shows what the list shows.
    public let todoList: TodoListViewModel

    /// The open windows, shared by every scene model and every shared view model built
    /// here: what makes one failure present in one window
    /// (``SceneLifecycleModel/presented(_:)``).
    private let openScenes: OpenScenes

    /// Builds the shared view models over `repository` and `preferences`. Nothing is read
    /// until a view model's own `load()`: construction stays free of side effects.
    ///
    /// `now` and `makeID` reach every view model that stamps a new value, so a test pins
    /// both here once. `preferences` has no default: a composition root that forgot to
    /// wire it would otherwise compile and silently stop remembering the user's settings.
    public init(
        repository: any TodoRepository,
        preferences: any PreferencesStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        let scenes = OpenScenes()
        openScenes = scenes
        todoList = TodoListViewModel(
            repository: repository,
            preferences: preferences,
            now: now,
            makeID: makeID,
            openScenes: scenes,
        )
    }

    /// A new lifecycle model for one scene, over the shared ``todoList``: the scene root
    /// keeps it in `@State`, so it lives exactly as long as the scene. It becomes an open
    /// window only once it reports a phase.
    public func makeSceneLifecycleModel() -> SceneLifecycleModel {
        SceneLifecycleModel(list: todoList, openScenes: openScenes)
    }

    /// A new navigation model for the scene `lifecycle` belongs to: the scene root keeps
    /// it in `@State` beside `lifecycle`.
    ///
    /// Built here because it waits on that window's failure alerts: a link that arrives
    /// while the window presents one moves nothing until the alert is answered
    /// (``NavigationModel/open(_:)``). Every shared model whose failure `RootView`
    /// presents is asked here, so a new one adds its line.
    public func makeNavigationModel(for lifecycle: SceneLifecycleModel) -> NavigationModel {
        NavigationModel { [todoList] in
            lifecycle.presented(todoList.reportedFailure) != nil
        }
    }

    /// The view model of the screen ``AppRoute/todoDetail(_:)`` pushes for `id`, in the
    /// window `scene` names.
    ///
    /// A new model on every call — the pushed screen owns the one it is given — over the
    /// shared ``todoList``, so the detail screen shows the item as the list holds it now,
    /// and a toggle there is the list's toggle. `scene` has no default: a pushed screen
    /// always has a window, and its failure presents there. `nil` is for a caller with
    /// none.
    public func makeTodoDetailViewModel(id: TodoItem.ID, scene: SceneID?) -> TodoDetailViewModel {
        TodoDetailViewModel(list: todoList, id: id, scene: scene)
    }
}
