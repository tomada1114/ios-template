import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// ``AppModel``: the shared view models it builds over the ports `App/` hands it, and the
/// view model it builds for a pushed route.
@MainActor
@Suite("AppModel")
struct AppModelTests {
    typealias Fixture = TodoListViewModelFixture

    /// An app model over `repository` and `preferences` whose clock and identifier source
    /// are pinned to the fixture's.
    private static func appModel(
        over repository: some TodoRepository,
        preferences: some PreferencesStoring,
    ) -> AppModel {
        let pinnedNow = Fixture.now
        let pinnedID = Fixture.fixedID
        return AppModel(
            repository: repository,
            preferences: preferences,
            now: { pinnedNow },
            makeID: { pinnedID },
        )
    }

    // MARK: - The shared list

    @Test
    func `building the app model reads nothing from either port`() async {
        let repository = InMemoryTodoRepository()
        let preferences = InMemoryPreferences()
        let model = Self.appModel(over: repository, preferences: preferences)
        #expect(model.todoList.phase == .idle)
        #expect(await repository.calls.isEmpty)
    }

    @Test
    func `the list loads from the repository and the preferences it was handed`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let preferences = InMemoryPreferences()
        preferences.set(true, for: PreferenceKeys.hideCompleted)
        let model = Self.appModel(
            over: InMemoryTodoRepository(items: [milk]),
            preferences: preferences,
        )
        await model.todoList.load()
        #expect(model.todoList.items == [milk])
        #expect(model.todoList.hideCompleted)
    }

    @Test
    func `the list stamps a new item with the injected clock and identifier`() async throws {
        let repository = InMemoryTodoRepository()
        let model = Self.appModel(over: repository, preferences: InMemoryPreferences())
        model.todoList.draftTitle = "Milk"
        await model.todoList.addDraft()
        let expected = try TodoItem(id: Fixture.fixedID, title: "Milk", createdAt: Fixture.now)
        #expect(model.todoList.items == [expected])
        #expect(await repository.snapshot == [expected])
    }

    // MARK: - A route's view model

    @Test
    func `a detail model shows the item the list loaded`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let bread = try Fixture.item("Bread", minute: 2)
        let model = Self.appModel(
            over: InMemoryTodoRepository(items: [milk, bread]),
            preferences: InMemoryPreferences(),
        )
        await model.todoList.load()
        #expect(model.makeTodoDetailViewModel(id: bread.id).content == .item(bread))
    }

    @Test
    func `a detail model loads the shared list, not a copy of its own`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let model = Self.appModel(
            over: InMemoryTodoRepository(items: [milk]),
            preferences: InMemoryPreferences(),
        )
        let detail = model.makeTodoDetailViewModel(id: milk.id)
        await detail.load()
        #expect(model.todoList.phase == .loaded)
        #expect(model.todoList.items == [milk])
    }

    @Test
    func `a toggle on a detail model is the list's toggle`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let model = Self.appModel(
            over: InMemoryTodoRepository(items: [milk]),
            preferences: InMemoryPreferences(),
        )
        await model.todoList.load()
        await model.makeTodoDetailViewModel(id: milk.id).toggle()
        #expect(model.todoList.item(withID: milk.id)?.isDone == true)
    }

    /// Two windows can push the same item: each gets a model of its own, and both show
    /// the one state the list holds.
    @Test
    func `each call builds a new detail model over the same state`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let model = Self.appModel(
            over: InMemoryTodoRepository(items: [milk]),
            preferences: InMemoryPreferences(),
        )
        await model.todoList.load()
        let first = model.makeTodoDetailViewModel(id: milk.id)
        let second = model.makeTodoDetailViewModel(id: milk.id)
        #expect(first !== second)
        await first.toggle()
        var done = milk
        done.isDone = true
        #expect(second.content == .item(done))
    }
}
