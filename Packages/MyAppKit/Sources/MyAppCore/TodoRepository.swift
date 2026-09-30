import Foundation

/// Everything a ``TodoRepository`` can report, in Core's vocabulary.
///
/// Payloads carry identifiers, never a title: an error can end up in a log line or a
/// crash report, and a title is the user's data.
public enum TodoRepositoryError: Error, Equatable, Sendable {
    /// A stored record with this identifier no longer satisfies ``TodoItem``'s invariants.
    case corruptedRecord(TodoItem.ID)
    /// No stored item has this identifier.
    case notFound(TodoItem.ID)
    /// The store could not be opened, read, or written. The underlying error stays in the
    /// adapter's log; Core only needs to know the operation did not happen.
    case storageFailure
}

/// A port: where to-do items are kept, asked in Core's own vocabulary.
///
/// This is the template's worked example of the repository pattern
/// (`docs/architecture.md` › Repositories). Core declares the protocol; `MyAppPlatform`
/// holds the SwiftData adapter (`SwiftDataTodoRepository`); `MyAppTestSupport` holds the
/// in-memory fake every Core test uses; and `App/` — the composition root — decides which
/// one the view model gets. Nothing below `App/` knows which store it is talking to.
///
/// The port is `Sendable` and speaks only value types, so an implementation can be an
/// actor with its own executor (SwiftData's `@ModelActor`) and a caller on the main
/// actor never touches a non-`Sendable` model object. Every method is `async` for the
/// same reason: crossing into the store's actor is a suspension point.
///
/// Every method throws ``TodoRepositoryError`` and nothing else. An implementation maps
/// its own failures (a SwiftData or file-system error) into it, so a caller handles a
/// closed set of cases and never learns which store failed.
///
/// `TodoRepositoryContract` in `MyAppTestSupport` checks the promises below against the
/// fake and against the SwiftData adapter, both under `just test`; a new promise is
/// stated here first, then added there.
public protocol TodoRepository: Sendable {
    /// Every stored item, in ``TodoItem/isOrderedBefore(_:_:)`` order.
    func fetchAll() async throws(TodoRepositoryError) -> [TodoItem]

    /// Stores `item`: inserts it when its identifier is new, otherwise replaces the stored
    /// item with that identifier. A later ``fetchAll()`` returns it exactly as passed.
    func save(_ item: TodoItem) async throws(TodoRepositoryError)

    /// Removes the item with `id`, or throws ``TodoRepositoryError/notFound(_:)`` when no
    /// item has it — a delete of something already gone is reported, not ignored, so a
    /// caller whose list is stale finds out.
    func delete(id: TodoItem.ID) async throws(TodoRepositoryError)
}
