#if DEBUG
    /// A ``TodoRepository`` over another one that fails every save replacing an item
    /// already stored — a toggle — with ``TodoRepositoryError/storageFailure``, and passes
    /// everything else through: reads, deletes, and saves of a new item.
    ///
    /// Debug-only fault injection, so a failed save can be seen in the running app: the
    /// composition root wraps the real store in it under the `-failUpdates` launch argument
    /// (`App/MyAppApp.swift`), and `LaunchUITests` launches with it to prove a failure
    /// presents over whichever screen is on top. Adds still succeed, so there is an item to
    /// open and toggle. Under `-delayFailedUpdates` too, each failure arrives only after a
    /// delay, so a test can open a sheet while the failing save is still in flight and see
    /// where its failure presents. A Release build compiles neither this type nor the
    /// arguments.
    public struct UpdateFailingTodoRepository: TodoRepository {
        private let base: any TodoRepository
        private let failureDelay: Duration
        private let clock: any Clock<Duration>

        /// Creates the repository over `base`.
        ///
        /// - Parameters:
        ///   - base: The repository every call this one lets through goes to.
        ///   - failureDelay: How long a failing save waits before it throws; zero throws
        ///     at once.
        ///   - clock: What that wait sleeps on. Injected so a test advances it by hand.
        public init(
            wrapping base: any TodoRepository,
            failureDelay: Duration = .zero,
            clock: any Clock<Duration> = ContinuousClock(),
        ) {
            self.base = base
            self.failureDelay = failureDelay
            self.clock = clock
        }

        public func fetchAll() async throws(TodoRepositoryError) -> [TodoItem] {
            try await base.fetchAll()
        }

        /// Stores `item` when no stored item has its identifier; otherwise waits
        /// `failureDelay`, then throws ``TodoRepositoryError/storageFailure`` and stores
        /// nothing — at once, too, when the calling task is cancelled during the wait.
        public func save(_ item: TodoItem) async throws(TodoRepositoryError) {
            let stored = try await base.fetchAll()
            if stored.contains(where: { $0.id == item.id }) {
                if failureDelay > .zero {
                    // A cancelled wait fails the save just the same: there is nothing
                    // else for it to report.
                    try? await clock.sleep(for: failureDelay)
                }
                throw .storageFailure
            }
            try await base.save(item)
        }

        public func delete(id: TodoItem.ID) async throws(TodoRepositoryError) {
            try await base.delete(id: id)
        }
    }
#endif
