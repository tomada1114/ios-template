import MyAppCore
import MyAppTestSupport
import Testing

/// Keeps items in the order they were first saved — breaks the ordering promise.
private actor InsertionOrderRepository: TodoRepository {
    private var items: [TodoItem] = []

    func fetchAll() -> [TodoItem] {
        items
    }

    func save(_ item: TodoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func delete(id: TodoItem.ID) throws(TodoRepositoryError) {
        guard items.contains(where: { $0.id == id }) else {
            throw .notFound(id)
        }
        items.removeAll { $0.id == id }
    }
}

/// Treats a delete of a missing identifier as success — breaks the `notFound` promise.
private actor LenientDeleteRepository: TodoRepository {
    private let inner = InMemoryTodoRepository()

    func fetchAll() async throws(TodoRepositoryError) -> [TodoItem] {
        try await inner.fetchAll()
    }

    func save(_ item: TodoItem) async throws(TodoRepositoryError) {
        try await inner.save(item)
    }

    func delete(id: TodoItem.ID) async {
        try? await inner.delete(id: id)
    }
}

/// The fake half of the `TodoRepository` contract suite: the same
/// ``TodoRepositoryContract`` that `MyAppPlatformTests` runs against the SwiftData adapter
/// runs here against ``InMemoryTodoRepository``, so the fake cannot drift from the port's
/// promises.
@Suite("TodoRepository contract, against the fake")
struct TodoRepositoryContractTests {
    @Test
    func `the fake keeps the contract`() async {
        await TodoRepositoryContract.check(InMemoryTodoRepository())
    }

    // The contract's own oracle: an implementation that breaks a promise must be
    // reported, or `check(_:)` would pass anything, the real adapter included.

    @Test
    func `a store that returns insertion order is reported`() async {
        let violations = await TodoRepositoryContract.violations(of: InsertionOrderRepository())
        #expect(violations.contains { $0.contains("isOrderedBefore order") })
    }

    @Test
    func `a store that ignores a missing delete is reported`() async {
        let violations = await TodoRepositoryContract.violations(of: LenientDeleteRepository())
        #expect(violations == ["delete of a missing identifier did not throw"])
    }

    @Test
    func `a store that cannot be reached is reported`() async {
        let violations = await TodoRepositoryContract.violations(of: UnavailableTodoRepository())
        #expect(violations.count == 1)
        #expect(violations.first?.contains("storageFailure") == true)
    }
}
