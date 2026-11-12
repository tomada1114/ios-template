import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// ``AppModel/sceneDidEnter(_:scene:)``: which phase sequences reload the shared list.
///
/// A window comes back to the foreground through `inactive` (background → inactive →
/// active), so only a scene that was active, then went to the background, then became
/// active again reloads; a scene's first active never does, because the list's `.task`
/// owns the first load.
@MainActor
@Suite("AppModel lifecycle")
struct AppModelLifecycleTests {
    typealias Fixture = TodoListViewModelFixture

    /// One scene's reported phases and how many fetches they cause, worked out by hand.
    struct PhaseCase: CustomTestStringConvertible, Sendable {
        let phases: [LifecyclePhase]
        let fetches: Int
        let label: String

        var testDescription: String {
            label
        }
    }

    nonisolated static let sequences: [PhaseCase] = [
        PhaseCase(phases: [.active], fetches: 0, label: "a first active"),
        PhaseCase(
            phases: [.active, .inactive, .active],
            fetches: 0,
            label: "inactive to active, such as dismissing Control Center",
        ),
        PhaseCase(
            phases: [.active, .background, .active],
            fetches: 1,
            label: "background to active",
        ),
        PhaseCase(
            phases: [.active, .inactive, .background, .inactive, .active],
            fetches: 1,
            label: "a full trip through the background",
        ),
        PhaseCase(
            phases: [.active, .inactive, .background, .inactive, .active, .inactive, .active],
            fetches: 1,
            label: "a trip through the background, then Control Center",
        ),
        PhaseCase(
            phases: [.active, .background, .active, .background, .active],
            fetches: 2,
            label: "two trips through the background",
        ),
        PhaseCase(
            phases: [.background, .inactive, .active],
            fetches: 0,
            label: "a scene whose first reports start in the background",
        ),
        PhaseCase(
            phases: [.active, .background, .background, .inactive],
            fetches: 0,
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

    @Test(arguments: sequences)
    func `a scene reloads the list only when it returns from the background`(
        sequence: PhaseCase,
    ) async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        await model.todoList.load()
        let scene = SceneID()
        for phase in sequence.phases {
            await model.sceneDidEnter(phase, scene: scene)
        }
        // The `.task` load above is the first fetch; the rest are the lifecycle's.
        #expect(await Self.fetchCount(repository) == 1 + sequence.fetches)
    }

    @Test
    func `the scene's first active does not double-load with the list's task`() async {
        let repository = InMemoryTodoRepository()
        let model = Self.appModel(over: repository)
        let scene = SceneID()
        await model.sceneDidEnter(.active, scene: scene)
        await model.todoList.load()
        await model.sceneDidEnter(.active, scene: scene)
        #expect(await Self.fetchCount(repository) == 1)
    }

    @Test
    func `a reload replaces what the list shows with what the store holds now`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let bread = try Fixture.item("Bread", minute: 2)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        let scene = SceneID()
        await model.sceneDidEnter(.active, scene: scene)
        await model.todoList.load()
        await model.sceneDidEnter(.background, scene: scene)
        // Written while the app was in the background, as a widget or a sync would.
        try await repository.save(bread)
        await model.sceneDidEnter(.active, scene: scene)
        #expect(model.todoList.items == [milk, bread])
        #expect(model.todoList.phase == .loaded)
    }

    @Test
    func `a reload that fails reports the load failure`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        let scene = SceneID()
        await model.sceneDidEnter(.active, scene: scene)
        await model.todoList.load()
        await model.sceneDidEnter(.background, scene: scene)
        await repository.fail(.fetchAll, with: .storageFailure)
        await model.sceneDidEnter(.active, scene: scene)
        #expect(model.todoList.phase == .failed)
        #expect(model.todoList.failure == .loadFailed)
        #expect(model.todoList.items == [milk])
    }

    /// Scenes are tracked apart: one window going to the background arms nothing in
    /// another window that only went inactive.
    @Test
    func `another scene's background does not make this scene reload`() async {
        let repository = InMemoryTodoRepository()
        let model = Self.appModel(over: repository)
        let first = SceneID()
        let second = SceneID()
        await model.sceneDidEnter(.active, scene: first)
        await model.sceneDidEnter(.active, scene: second)
        await model.todoList.load()
        await model.sceneDidEnter(.background, scene: first)
        await model.sceneDidEnter(.inactive, scene: second)
        await model.sceneDidEnter(.active, scene: second)
        #expect(await Self.fetchCount(repository) == 1)
    }

    /// Two windows coming back together each reload; the list's latest-wins guard applies
    /// only the newest fetch, and the list ends loaded with what the store holds.
    @Test
    func `two scenes returning from the background each reload`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Self.appModel(over: repository)
        let first = SceneID()
        let second = SceneID()
        for scene in [first, second] {
            await model.sceneDidEnter(.active, scene: scene)
        }
        await model.todoList.load()
        for scene in [first, second] {
            await model.sceneDidEnter(.background, scene: scene)
        }
        async let firstReturn: Void = model.sceneDidEnter(.active, scene: first)
        async let secondReturn: Void = model.sceneDidEnter(.active, scene: second)
        _ = await (firstReturn, secondReturn)
        #expect(await Self.fetchCount(repository) == 3)
        #expect(model.todoList.phase == .loaded)
        #expect(model.todoList.items == [milk])
    }

    @Test
    func `a scene identifier is distinct from every other one`() {
        let first = SceneID()
        let second = SceneID()
        #expect(first != second)
    }
}
