import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// ``TodoListViewModel/item(withID:)``: how the detail screen, and a deep link to it, find
/// an item.
@MainActor
@Suite("TodoListViewModel — looking up an item")
struct TodoListViewModelLookupTests {
    typealias Fixture = TodoListViewModelFixture

    @Test
    func `finds a loaded item by its identifier`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let bread = try Fixture.item("Bread", minute: 2)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [milk, bread]))
        await model.load()
        #expect(model.item(withID: bread.id) == bread)
    }

    /// A link to a done item must still open it while Hide Completed is on.
    @Test
    func `finds an item that hideCompleted hides`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [done]))
        await model.load()
        model.setHideCompleted(true)
        #expect(model.visibleItems.isEmpty)
        #expect(model.item(withID: done.id) == done)
    }

    @Test
    func `answers nil for an identifier it does not hold`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [milk]))
        await model.load()
        #expect(model.item(withID: Fixture.fixedID) == nil)
    }

    @Test
    func `answers nil before anything is loaded`() throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [milk]))
        #expect(model.item(withID: milk.id) == nil)
    }

    // MARK: - Before the items are known

    /// Before the first load, a missing item is not yet "not found": the detail screen
    /// shows progress instead, so a deep link that arrives first never flashes not-found.
    @Test
    func `is awaiting items before anything is loaded`() {
        let model = Fixture.model(over: InMemoryTodoRepository())
        #expect(model.phase == .idle)
        #expect(model.isAwaitingItems)
    }

    @Test
    func `is no longer awaiting items once a load has succeeded`() async {
        let model = Fixture.model(over: InMemoryTodoRepository())
        await model.load()
        #expect(!model.isAwaitingItems)
    }

    @Test
    func `is no longer awaiting items once a load has failed`() async {
        let repository = InMemoryTodoRepository()
        await repository.fail(.fetchAll, with: .storageFailure)
        let model = Fixture.model(over: repository)
        await model.load()
        #expect(model.phase == .failed)
        #expect(!model.isAwaitingItems)
    }

    @Test
    func `reflects a toggle`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [milk]))
        await model.load()
        await model.toggle(milk.id)
        #expect(model.item(withID: milk.id)?.isDone == true)
    }
}
