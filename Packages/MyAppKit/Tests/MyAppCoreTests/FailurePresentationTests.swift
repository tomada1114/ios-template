import MyAppCore
import MyAppTestSupport
import Testing

/// Which window presents the shared list's failure: the list is app-wide and every window
/// renders it, so Core picks exactly one of them (`designing-ui`'s
/// `references/navigation.md` › A failure presents in one window).
///
/// Among the windows in the foreground — or among all open windows while none is — the
/// one whose action caused the failure presents it, and otherwise the one that came to
/// the foreground first.
@MainActor
@Suite("Failure presentation")
struct FailurePresentationTests {
    typealias Fixture = TodoListViewModelFixture

    /// An app whose list has loaded `milk`, over a repository every later call can fail.
    @MainActor
    struct Loaded {
        let app: AppModel
        let repository: InMemoryTodoRepository
        let milk: TodoItem

        var list: TodoListViewModel {
            app.todoList
        }

        init() async throws {
            milk = try Fixture.item("Milk", minute: 1)
            repository = InMemoryTodoRepository(items: [milk])
            app = AppModel(repository: repository, preferences: InMemoryPreferences())
            await app.todoList.load()
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
            scenes.indices.filter { scenes[$0].todoListFailure != nil }
        }
    }

    // MARK: - The scene that caused it

    @Test
    func `a failure from one window presents there and not in the other open window`() async throws {
        let loaded = try await Loaded()
        let first = loaded.scene(.active)
        let second = loaded.scene(.active)
        await loaded.failAToggle(from: second)
        #expect(loaded.list.failureScene == second.id)
        #expect(second.todoListFailure == .saveFailed)
        #expect(first.todoListFailure == nil)
    }

    @Test
    func `every action that can fail names the window that asked for it`() async throws {
        let loaded = try await Loaded()
        let scene = loaded.scene(.active)
        let list = loaded.list

        await loaded.repository.fail(.save, with: .storageFailure)
        list.draftTitle = "Bread"
        await list.addDraft(from: scene.id)
        #expect(list.failure == .saveFailed)
        #expect(list.failureScene == scene.id)
        list.dismissFailure()

        await loaded.repository.fail(.delete, with: .storageFailure)
        await list.delete(atOffsets: [0], from: scene.id)
        #expect(list.failure == .deleteFailed)
        #expect(list.failureScene == scene.id)
        list.dismissFailure()

        await list.delete([loaded.milk.id], from: scene.id)
        #expect(list.failure == .deleteFailed)
        #expect(list.failureScene == scene.id)
        list.dismissFailure()

        await loaded.repository.fail(.fetchAll, with: .storageFailure)
        await list.load(from: scene.id)
        #expect(list.failure == .loadFailed)
        #expect(list.failureScene == scene.id)
    }

    @Test
    func `a detail screen's toggle fails as its own window's`() async throws {
        let loaded = try await Loaded()
        let first = loaded.scene(.active)
        let second = loaded.scene(.active)
        let detail = loaded.app.makeTodoDetailViewModel(id: loaded.milk.id, scene: second.id)
        await loaded.repository.fail(.save, with: .storageFailure)
        await detail.toggle()
        #expect(loaded.list.failure == .saveFailed)
        #expect(loaded.presenters(among: [first, second]) == [1])
    }

    /// A deep link can push the detail screen before the list ever loaded, so its load is
    /// the list's first, and fails as its window's.
    @Test
    func `a detail screen's first load fails as its own window's`() async {
        let repository = InMemoryTodoRepository()
        let app = AppModel(repository: repository, preferences: InMemoryPreferences())
        let first = app.makeSceneLifecycleModel()
        let second = app.makeSceneLifecycleModel()
        first.sceneDidEnter(.active)
        second.sceneDidEnter(.active)
        await repository.fail(.fetchAll, with: .storageFailure)
        await app.makeTodoDetailViewModel(id: Fixture.fixedID, scene: second.id).load()
        #expect(second.todoListFailure == .loadFailed)
        #expect(first.todoListFailure == nil)
    }

    /// One failure is held at a time, as in one window: the newer one replaces the older,
    /// and is presented where it was caused.
    @Test
    func `a second failure from another window replaces the first and presents there`(
    ) async throws {
        let loaded = try await Loaded()
        let first = loaded.scene(.active)
        let second = loaded.scene(.active)
        await loaded.failAToggle(from: first)
        await loaded.repository.fail(.delete, with: .storageFailure)
        await loaded.list.delete([loaded.milk.id], from: second.id)
        #expect(first.todoListFailure == nil)
        #expect(second.todoListFailure == .deleteFailed)
    }

    // MARK: - No scene caused it

    @Test
    func `a failure no window caused presents in the one that came to the foreground first`(
    ) async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: nil)
        #expect(loaded.list.failure == .saveFailed)
        #expect(loaded.list.failureScene == nil)
        #expect(loaded.presenters(among: scenes) == [0])
    }

    /// The window presenting a failure it did not cause hands it on when it leaves the
    /// foreground, and does not take it back from under the person when it returns.
    @Test
    func `a failure no window caused moves on only when its window leaves the foreground`(
    ) async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: nil)
        scenes[0].sceneDidEnter(.inactive)
        #expect(loaded.presenters(among: scenes) == [0])
        scenes[0].sceneDidEnter(.background)
        #expect(loaded.presenters(among: scenes) == [1])
        scenes[0].sceneDidEnter(.inactive)
        scenes[0].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [1])
    }

    // MARK: - The scene that caused it is not on screen

    /// A failure is never left where nobody can see it: while its window is in the
    /// background another window in the foreground presents it. It is the origin's
    /// again once the origin is back, beside the row whose change failed.
    @Test
    func `a failure whose window left the foreground presents in another until it returns`(
    ) async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        scenes[1].sceneDidEnter(.inactive)
        #expect(loaded.presenters(among: scenes) == [1])
        scenes[1].sceneDidEnter(.background)
        #expect(loaded.presenters(among: scenes) == [0])
        scenes[1].sceneDidEnter(.inactive)
        #expect(loaded.presenters(among: scenes) == [1])
    }

    @Test
    func `a failure that arrives after its window went to the background presents in another`(
    ) async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active, .inactive, .background)]
        await loaded.failAToggle(from: scenes[1])
        #expect(loaded.presenters(among: scenes) == [0])
    }

    /// A closed window's model is gone, whether or not it reported the background first.
    @Test
    func `a failure whose window closed presents in a window that is still open`() async throws {
        let loaded = try await Loaded()
        var closing: SceneLifecycleModel? = loaded.scene(.active)
        let open = loaded.scene(.active)
        await loaded.failAToggle(from: closing)
        #expect(open.todoListFailure == nil)
        closing = nil
        #expect(closing == nil)
        #expect(open.todoListFailure == .saveFailed)
    }

    // MARK: - No window in the foreground

    /// The app in the background has no foreground window: the failure stays with the
    /// window that caused it, so its alert is still up when the app comes back.
    @Test
    func `while every window is in the background the window that caused a failure keeps it`(
    ) async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        scenes[0].sceneDidEnter(.background)
        scenes[1].sceneDidEnter(.background)
        #expect(loaded.presenters(among: scenes) == [1])
        scenes[0].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [0])
        scenes[1].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [1])
    }

    @Test
    func `while every window is in the background a failure no window caused still has one presenter`(
    ) async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active, .background), loaded.scene(.background)]
        await loaded.failAToggle(from: nil)
        #expect(loaded.presenters(among: scenes) == [0])
    }

    /// `SceneRoot` builds a spare model on every re-render, which reports nothing: it is
    /// not a window, and must never be the one a failure is handed to.
    @Test
    func `a scene that has reported no phase presents nothing`() async throws {
        let loaded = try await Loaded()
        let spare = loaded.scene()
        let window = loaded.scene(.active)
        await loaded.failAToggle(from: nil)
        #expect(loaded.presenters(among: [spare, window]) == [1])
        await loaded.failAToggle(from: spare)
        #expect(loaded.presenters(among: [spare, window]) == [1])
    }

    @Test
    func `each scene has an identity of its own`() async throws {
        let loaded = try await Loaded()
        let ids = [loaded.scene().id, loaded.scene().id, loaded.scene(.active).id]
        #expect(Set(ids).count == 3)
    }

    // MARK: - Dismissal

    @Test
    func `the presenting window's dismissal clears the failure for every window`() async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[0])
        scenes[0].dismissTodoListFailure()
        #expect(loaded.list.failure == nil)
        #expect(loaded.list.failureScene == nil)
        #expect(loaded.presenters(among: scenes).isEmpty)
    }

    /// A window whose alert was replaced by another window's failure may still deliver its
    /// button's tap: it names the window, so it cannot dismiss a failure shown elsewhere.
    @Test
    func `a dismissal from a window that is not presenting the failure changes nothing`(
    ) async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        scenes[0].dismissTodoListFailure()
        #expect(loaded.list.failure == .saveFailed)
        #expect(loaded.list.failureScene == scenes[1].id)
        #expect(loaded.presenters(among: scenes) == [1])
    }

    @Test
    func `a failure after a dismissed one is presented where it was caused`() async throws {
        let loaded = try await Loaded()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        loaded.list.dismissFailure()
        #expect(loaded.list.failureScene == nil)
        await loaded.failAToggle(from: scenes[0])
        #expect(loaded.presenters(among: scenes) == [0])
    }
}
