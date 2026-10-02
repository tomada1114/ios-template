#if DEBUG
    /// A ``TodoRepository`` over another one that fails every save replacing an item
    /// already stored — a toggle — with ``TodoRepositoryError/storageFailure``, and passes
    /// everything else through: reads, deletes, and saves of a new item.
    ///
    /// Debug-only fault injection, so a failed save can be seen in the running app: the
    /// composition root wraps the real store in it under the `-failUpdates` launch argument
    /// (`App/MyAppApp.swift`), and `LaunchUITests` launches with it to prove a failure
    /// presents over whichever screen is on top. Adds still succeed, so there is an item to
    /// open and toggle. A Release build compiles neither this type nor the argument.
    public struct UpdateFailingTodoRepository: TodoRepository {
        private let base: any TodoRepository

        /// Creates the repository over `base`, which answers every call this one lets
        /// through.
        public init(wrapping base: any TodoRepository) {
            self.base = base
        }

        public func fetchAll() async throws(TodoRepositoryError) -> [TodoItem] {
            try await base.fetchAll()
        }

        /// Stores `item` when no stored item has its identifier; otherwise throws
        /// ``TodoRepositoryError/storageFailure`` and stores nothing.
        public func save(_ item: TodoItem) async throws(TodoRepositoryError) {
            let stored = try await base.fetchAll()
            if stored.contains(where: { $0.id == item.id }) {
                throw .storageFailure
            }
            try await base.save(item)
        }

        public func delete(id: TodoItem.ID) async throws(TodoRepositoryError) {
            try await base.delete(id: id)
        }
    }
#endif
