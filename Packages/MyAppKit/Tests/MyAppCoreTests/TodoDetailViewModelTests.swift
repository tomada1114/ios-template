import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// ``TodoDetailViewModel``: what the detail screen shows for its item — the item,
/// progress, or not found — and its two actions.
@MainActor
@Suite("TodoDetailViewModel")
struct TodoDetailViewModelTests {
    typealias Fixture = TodoListViewModelFixture

    /// The app model over `repository` and empty preferences, and the detail model it
    /// builds for `id`.
    private static func detail(
        of id: TodoItem.ID,
        over repository: InMemoryTodoRepository,
    ) -> (app: AppModel, detail: TodoDetailViewModel) {
        let app = AppModel(repository: repository, preferences: InMemoryPreferences())
        return (app, app.makeTodoDetailViewModel(id: id))
    }

    // MARK: - What it shows

    /// A deep link can push the screen before the list under it ever loaded: that is
    /// progress, never a flash of "not found".
    @Test
    func `shows progress before the list has loaded`() throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let (_, detail) = Self.detail(of: milk.id, over: InMemoryTodoRepository(items: [milk]))
        #expect(detail.content == .loading)
    }

    @Test
    func `shows the item once the list has loaded`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let (_, detail) = Self.detail(of: milk.id, over: InMemoryTodoRepository(items: [milk]))
        await detail.load()
        #expect(detail.content == .item(milk))
    }

    @Test
    func `shows not found for an identifier the loaded list does not hold`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let (_, detail) = Self.detail(
            of: Fixture.fixedID,
            over: InMemoryTodoRepository(items: [milk]),
        )
        await detail.load()
        #expect(detail.content == .notFound)
    }

    @Test
    func `shows not found once loading has failed`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        await repository.fail(.fetchAll, with: .storageFailure)
        let (_, detail) = Self.detail(of: milk.id, over: repository)
        await detail.load()
        #expect(detail.content == .notFound)
    }

    /// The item is looked up when the screen renders, so a delete from the list (or
    /// another window) turns an open detail screen into not found.
    @Test
    func `shows not found once the item is deleted from the list`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let (app, detail) = Self.detail(of: milk.id, over: InMemoryTodoRepository(items: [milk]))
        await detail.load()
        await app.todoList.delete([milk.id])
        #expect(detail.content == .notFound)
    }

    /// Hide Completed hides rows, not the item: its detail screen still opens.
    @Test
    func `shows an item that hideCompleted hides`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let (app, detail) = Self.detail(of: done.id, over: InMemoryTodoRepository(items: [done]))
        await detail.load()
        app.todoList.setHideCompleted(true)
        #expect(detail.content == .item(done))
    }

    // MARK: - Loading

    @Test
    func `load asks the repository once when the list has not loaded`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let (_, detail) = Self.detail(of: milk.id, over: repository)
        await detail.load()
        #expect(await repository.calls == [.fetchAll])
    }

    /// Returning to a pushed screen, or pushing it over a list that already loaded, keeps
    /// what is shown: pull-to-refresh on the list is the explicit way to reload.
    @Test
    func `load does not ask again once the list has loaded`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let (app, detail) = Self.detail(of: milk.id, over: repository)
        await app.todoList.load()
        await detail.load()
        await detail.load()
        #expect(await repository.calls == [.fetchAll])
    }

    @Test
    func `load does not ask again after a failed load`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        await repository.fail(.fetchAll, with: .storageFailure)
        let (app, detail) = Self.detail(of: milk.id, over: repository)
        await app.todoList.load()
        await detail.load()
        #expect(await repository.calls == [.fetchAll])
    }

    // MARK: - Toggling

    @Test
    func `toggle checks the item off, and a second toggle reopens it`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let (_, detail) = Self.detail(of: milk.id, over: repository)
        await detail.load()
        await detail.toggle()
        var done = milk
        done.isDone = true
        #expect(detail.content == .item(done))
        #expect(await repository.snapshot == [done])
        await detail.toggle()
        #expect(detail.content == .item(milk))
    }

    @Test
    func `a failed toggle keeps the item and reports the failure on the list`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let (app, detail) = Self.detail(of: milk.id, over: repository)
        await detail.load()
        await repository.fail(.save, with: .storageFailure)
        await detail.toggle()
        #expect(detail.content == .item(milk))
        #expect(app.todoList.failure == .saveFailed)
    }

    @Test
    func `toggle does nothing for an item the list does not hold`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let (_, detail) = Self.detail(of: Fixture.fixedID, over: repository)
        await detail.load()
        await detail.toggle()
        #expect(await repository.calls == [.fetchAll])
    }

    // MARK: - Wording

    @Test
    func `the toggle's label says what tapping it will do`() throws {
        let open = try Fixture.item("Open", minute: 1)
        let done = try Fixture.doneItem("Done", minute: 2)
        let (_, detail) = Self.detail(of: open.id, over: InMemoryTodoRepository())
        #expect(detail.toggleLabel(for: open).english == "Mark as Done")
        #expect(detail.toggleLabel(for: done).english == "Mark as Not Done")
    }
}
