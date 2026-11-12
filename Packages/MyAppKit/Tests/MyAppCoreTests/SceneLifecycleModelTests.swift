import MyAppCore
import MyAppTestSupport
import Testing

/// ``SceneLifecycleModel``: which phase sequences refresh the shared list.
///
/// A window comes back to the foreground through `inactive` (background → inactive →
/// active). A scene asks for a refresh at its first active and at every active after a
/// trip through the background, never at a plain inactive → active change; the list then
/// fetches only when it has already loaded and no fetch is in flight.
@MainActor
@Suite("SceneLifecycleModel")
struct SceneLifecycleModelTests {
    typealias Fixture = TodoListViewModelFixture

    /// One scene's reported phases, over a list that has already loaded, and how many
    /// fetches they add to that first load — worked out by hand.
    struct PhaseCase: CustomTestStringConvertible, Sendable {
        let phases: [LifecyclePhase]
        let fetches: Int
        let label: String

        var testDescription: String {
            label
        }
    }

    nonisolated static let sequences: [PhaseCase] = [
        PhaseCase(phases: [.active], fetches: 1, label: "a first active over a loaded list"),
        PhaseCase(
            phases: [.active, .inactive, .active],
            fetches: 1,
            label: "inactive to active, such as dismissing Control Center",
        ),
        PhaseCase(
            phases: [.active, .background, .active],
            fetches: 2,
            label: "background to active",
        ),
        PhaseCase(
            phases: [.active, .inactive, .background, .inactive, .active],
            fetches: 2,
            label: "a full trip through the background",
        ),
        PhaseCase(
            phases: [.active, .inactive, .background, .inactive, .active, .inactive, .active],
            fetches: 2,
            label: "a trip through the background, then Control Center",
        ),
        PhaseCase(
            phases: [.active, .background, .active, .background, .active],
            fetches: 3,
            label: "two trips through the background",
        ),
        PhaseCase(
            phases: [.background, .inactive, .active],
            fetches: 1,
            label: "a prewarmed scene whose first reports start in the background",
        ),
        PhaseCase(
            phases: [.active, .background, .background, .inactive],
            fetches: 1,
            label: "a scene that has not come back yet",
        ),
    ]

    private static func appModel(over repository: some TodoRepository) -> AppModel {
        let pinnedNow = Fixture.now
        let pinnedID = Fixture.fixedID
        return AppModel(
            repository: repository,
            preferences: InMemoryPreferences(),
            now: { pinnedNow },
            makeID: { pinnedID },
        )
    }

    private static func fetchCount(_ repository: InMemoryTodoRepository) async -> Int {
        await repository.calls.count { $0 == .fetchAll }
    }

    /// What `SceneRoot` does with each phase: record it, then run what it asked for.
    private static func report(_ phases: [LifecyclePhase], to scene: SceneLifecycleModel) async {
        for phase in phases {
            scene.sceneDidEnter(phase)
            await scene.refreshIfNeeded()
        }
    }

    // MARK: - One scene

    @Test(arguments: sequences)
    func `a scene refreshes at its first active and when it returns from the background`(
        sequence: PhaseCase,
    ) async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        await model.todoList.load(from: nil)
        await Self.report(sequence.phases, to: model.makeSceneLifecycleModel())
        // The load above is the first fetch; the rest are the lifecycle's.
        #expect(await Self.fetchCount(repository) == 1 + sequence.fetches)
    }

    /// A window iOS discarded and rebuilt gets a new model, and so a first active: the
    /// list it shows is refreshed even though its old model's trip through the background
    /// went with it.
    @Test
    func `a recreated scene's first active reloads when the list is loaded`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let bread = try Fixture.item("Bread", minute: 2)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        await Self.report([.active], to: model.makeSceneLifecycleModel())
        await model.todoList.load(from: nil)
        await Self.report([.inactive, .background], to: model.makeSceneLifecycleModel())
        try await repository.save(bread)
        await Self.report([.active], to: model.makeSceneLifecycleModel())
        #expect(model.todoList.items == [milk, bread])
        #expect(await Self.fetchCount(repository) == 2)
    }

    @Test
    func `a first active before the list's task loads fetches nothing`() async {
        let repository = InMemoryTodoRepository()
        let model = Self.appModel(over: repository)
        await Self.report([.active], to: model.makeSceneLifecycleModel())
        await model.todoList.load(from: nil)
        #expect(await Self.fetchCount(repository) == 1)
    }

    @Test
    func `a first active while the list's task is loading fetches nothing`() async {
        let repository = InMemoryTodoRepository()
        let model = Self.appModel(over: repository)
        let scene = model.makeSceneLifecycleModel()
        await repository.onFetch { _ in
            guard await repository.calls.count == 1 else {
                return
            }
            await Self.report([.active], to: scene)
        }
        await model.todoList.load(from: nil)
        #expect(await Self.fetchCount(repository) == 1)
        #expect(model.todoList.phase == .loaded)
    }

    @Test
    func `phases recorded before the refresh runs apply in order`() async {
        let repository = InMemoryTodoRepository()
        let model = Self.appModel(over: repository)
        await model.todoList.load(from: nil)
        let scene = model.makeSceneLifecycleModel()
        await Self.report([.active], to: scene)
        // Recorded with no chance for the refresh tasks to run in between.
        scene.sceneDidEnter(.background)
        scene.sceneDidEnter(.inactive)
        scene.sceneDidEnter(.active)
        scene.sceneDidEnter(.inactive)
        #expect(scene.phase == .inactive)
        #expect(scene.isRefreshPending)
        await scene.refreshIfNeeded()
        await scene.refreshIfNeeded()
        #expect(!scene.isRefreshPending)
        #expect(await Self.fetchCount(repository) == 3)
    }

    @Test
    func `a scene reports nothing before its first phase`() {
        let model = Self.appModel(over: InMemoryTodoRepository())
        let scene = model.makeSceneLifecycleModel()
        #expect(scene.phase == nil)
        #expect(!scene.isRefreshPending)
    }

    // MARK: - What a refresh does to the list

    @Test
    func `a refresh replaces what the list shows with what the store holds now`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let bread = try Fixture.item("Bread", minute: 2)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        let scene = model.makeSceneLifecycleModel()
        await Self.report([.active], to: scene)
        await model.todoList.load(from: nil)
        await Self.report([.background], to: scene)
        // Written while the app was in the background, as a widget or a sync would.
        try await repository.save(bread)
        await Self.report([.active], to: scene)
        #expect(model.todoList.items == [milk, bread])
        #expect(model.todoList.phase == .loaded)
    }

    @Test
    func `a refresh that fails keeps the items and presents nothing`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        let scene = model.makeSceneLifecycleModel()
        await Self.report([.active], to: scene)
        await model.todoList.load(from: nil)
        await Self.report([.background], to: scene)
        await repository.fail(.fetchAll, with: .storageFailure)
        await Self.report([.active], to: scene)
        #expect(await Self.fetchCount(repository) == 2)
        #expect(model.todoList.items == [milk])
        #expect(model.todoList.phase == .loaded)
        #expect(model.todoList.failure == nil)
    }

    // MARK: - Several scenes

    /// Scenes are tracked apart: one window going to the background arms nothing in
    /// another window that only went inactive.
    @Test
    func `another scene's background does not make this scene refresh`() async {
        let repository = InMemoryTodoRepository()
        let model = Self.appModel(over: repository)
        let first = model.makeSceneLifecycleModel()
        let second = model.makeSceneLifecycleModel()
        await Self.report([.active], to: first)
        await Self.report([.active], to: second)
        await model.todoList.load(from: nil)
        await Self.report([.background], to: first)
        await Self.report([.inactive, .active], to: second)
        #expect(await Self.fetchCount(repository) == 1)
    }

    /// Two windows coming back together fetch once: the second asks while the first's
    /// refresh is in flight, and the list skips a refresh while one is running.
    @Test
    func `two scenes returning from the background together fetch once`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        let first = model.makeSceneLifecycleModel()
        let second = model.makeSceneLifecycleModel()
        await Self.report([.active], to: first)
        await Self.report([.active], to: second)
        await model.todoList.load(from: nil)
        await Self.report([.background], to: first)
        await Self.report([.background], to: second)
        await repository.onFetch { _ in
            guard await repository.calls.count == 2 else {
                return
            }
            await Self.report([.inactive, .active], to: second)
        }
        await Self.report([.inactive, .active], to: first)
        #expect(await Self.fetchCount(repository) == 2)
        #expect(!second.isRefreshPending)
        #expect(model.todoList.phase == .loaded)
        #expect(model.todoList.items == [milk])
    }
}
