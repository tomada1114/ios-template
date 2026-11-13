#if DEBUG
    /// A ``TodoRepository`` over another one that fails every save replacing an item
    /// already stored — a toggle — with ``TodoRepositoryError/storageFailure``, and passes
    /// everything else through: reads, deletes, and saves of a new item.
    ///
    /// Debug-only fault injection, so a failed save can be seen in the running app: the
    /// composition root wraps the real store in it under the `-failUpdates` launch argument
    /// (`App/MyAppApp.swift`), and `LaunchUITests` launches with it to prove a failure
    /// presents over whichever screen is on top. Adds still succeed, so there is an item to
    /// open and toggle. Under `-holdFailedUpdates` too, each failure is held at a
    /// ``FailedUpdateGate`` until the test releases it, so a test can open a sheet while
    /// the failing save is still in flight and see where its failure presents. A Release
    /// build compiles neither this type nor the arguments.
    public struct UpdateFailingTodoRepository: TodoRepository {
        private let base: any TodoRepository
        private let gate: FailedUpdateGate?

        /// Creates the repository over `base`.
        ///
        /// - Parameters:
        ///   - base: The repository every call this one lets through goes to.
        ///   - gate: Where a failing save waits for a release before it throws; `nil`
        ///     throws at once.
        public init(
            wrapping base: any TodoRepository,
            holdingFailuresAt gate: FailedUpdateGate? = nil,
        ) {
            self.base = base
            self.gate = gate
        }

        public func fetchAll() async throws(TodoRepositoryError) -> [TodoItem] {
            try await base.fetchAll()
        }

        /// Stores `item` when no stored item has its identifier; otherwise waits for the
        /// gate to release it, then throws ``TodoRepositoryError/storageFailure`` and
        /// stores nothing — at once, too, when the calling task is cancelled.
        public func save(_ item: TodoItem) async throws(TodoRepositoryError) {
            let stored = try await base.fetchAll()
            if stored.contains(where: { $0.id == item.id }) {
                // `throws(TodoRepositoryError)` has no way to throw `CancellationError`,
                // and the port has no `.cancelled` case (`core.md` › Cancellation: the
                // awaiting action reads `Task.isCancelled`), so a cancelled hold ends
                // early and the save fails as it would have.
                await gate?.hold()
                throw .storageFailure
            }
            try await base.save(item)
        }

        public func delete(id: TodoItem.ID) async throws(TodoRepositoryError) {
            try await base.delete(id: id)
        }
    }
#endif
