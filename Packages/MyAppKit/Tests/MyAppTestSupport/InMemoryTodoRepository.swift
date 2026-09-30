import MyAppCore

/// The one fake of ``MyAppCore/TodoRepository``, shared by every test target.
///
/// A fake, not a mock: a real conforming implementation that keeps items in a
/// dictionary, whose failures and calls are data the test sets and reads — no
/// expectations are declared up front. `TodoRepositoryContract` holds it to the same
/// promises as the SwiftData adapter, so a view model test written against it is a test
/// against the port, not against a convenient invention.
///
/// An actor, like the adapter, so it is `Sendable` without a lock and a view model under
/// test crosses the same suspension points it will cross in the app.
package actor InMemoryTodoRepository: TodoRepository {
    /// A port method, as recorded in ``calls`` and targeted by ``fail(_:with:)``.
    package enum Operation: Equatable, Sendable {
        case delete
        case fetchAll
        case save
    }

    /// Every call made so far, in order — including the ones that failed.
    package private(set) var calls: [Operation] = []

    private var stored: [TodoItem.ID: TodoItem]
    private var failures: [Operation: TodoRepositoryError] = [:]
    private var beforeSave: (@Sendable (TodoItem) async -> Void)?

    /// What the fake holds right now, in display order — read without recording a call.
    package var snapshot: [TodoItem] {
        stored.values.sorted(by: TodoItem.isOrderedBefore)
    }

    /// Starts empty.
    package init() {
        self.init(items: [])
    }

    /// Starts holding `items`.
    package init(items: [TodoItem]) {
        stored = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    /// Makes every later call to `operation` throw `error`, until ``succeed(_:)``.
    package func fail(_ operation: Operation, with error: TodoRepositoryError) {
        failures[operation] = error
    }

    /// Undoes ``fail(_:with:)`` for `operation`.
    package func succeed(_ operation: Operation) {
        failures[operation] = nil
    }

    /// Runs `hook` inside every later ``save(_:)``, before the item is stored — the seam
    /// a test uses to act while a save is in flight.
    package func onSave(_ hook: @escaping @Sendable (TodoItem) async -> Void) {
        beforeSave = hook
    }

    package func fetchAll() throws(TodoRepositoryError) -> [TodoItem] {
        try record(.fetchAll)
        return snapshot
    }

    package func save(_ item: TodoItem) async throws(TodoRepositoryError) {
        try record(.save)
        await beforeSave?(item)
        stored[item.id] = item
    }

    package func delete(id: TodoItem.ID) throws(TodoRepositoryError) {
        try record(.delete)
        guard stored.removeValue(forKey: id) != nil else {
            throw .notFound(id)
        }
    }

    private func record(_ operation: Operation) throws(TodoRepositoryError) {
        calls.append(operation)
        if let error = failures[operation] {
            throw error
        }
    }
}
