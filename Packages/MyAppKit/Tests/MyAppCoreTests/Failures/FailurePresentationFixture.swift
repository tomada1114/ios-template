import MyAppCore
import MyAppTestSupport

/// What the failure-presentation suites share: an app whose list has loaded `milk`, over
/// a repository every later call can fail, and the windows opened on it.
@MainActor
struct FailurePresentationFixture {
    let app: AppModel
    let repository: InMemoryTodoRepository
    let milk: TodoItem

    var list: TodoListViewModel {
        app.todoList
    }

    init() async throws {
        milk = try TodoListViewModelFixture.item("Milk", minute: 1)
        repository = InMemoryTodoRepository(items: [milk])
        app = AppModel(repository: repository, preferences: InMemoryPreferences())
        await app.todoList.load(from: nil)
    }

    /// A window that has reported `phases`, in order.
    func scene(_ phases: LifecyclePhase...) -> SceneLifecycleModel {
        let scene = app.makeSceneLifecycleModel()
        for phase in phases {
            scene.sceneDidEnter(phase)
        }
        return scene
    }

    /// A toggle of `milk` that fails, asked for by `scene` — or by no scene.
    func failAToggle(from scene: SceneLifecycleModel?) async {
        await repository.fail(.save, with: .storageFailure)
        await list.toggle(milk.id, from: scene?.id)
    }

    /// Which of `scenes` present the list's failure, by position.
    func presenters(among scenes: [SceneLifecycleModel]) -> [Int] {
        scenes.indices.filter { scenes[$0].presented(list.reportedFailure) != nil }
    }
}
