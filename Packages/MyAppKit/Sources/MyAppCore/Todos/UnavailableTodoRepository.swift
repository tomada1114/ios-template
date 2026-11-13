/// A ``TodoRepository`` that has no store: every call throws
/// ``TodoRepositoryError/storageFailure``.
///
/// The composition root's answer when the real store cannot be opened
/// (`App/MyAppApp.swift`). The alternatives are worse: crashing on launch loses the
/// user nothing but the app, and silently falling back to an in-memory store would
/// accept edits that vanish on the next launch. With this, the list shows its load
/// failure and a retry, and nothing pretends to have been saved.
///
/// Its methods are synchronous: a synchronous throwing method satisfies the port's
/// `async` requirement, and there is nothing here to wait for.
public struct UnavailableTodoRepository: TodoRepository {
    public init() {
        // Stateless: there is nothing to hold.
    }

    public func fetchAll() throws(TodoRepositoryError) -> [TodoItem] {
        throw .storageFailure
    }

    public func save(_: TodoItem) throws(TodoRepositoryError) {
        throw .storageFailure
    }

    public func delete(id _: TodoItem.ID) throws(TodoRepositoryError) {
        throw .storageFailure
    }
}
