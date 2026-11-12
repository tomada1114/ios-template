import Foundation
import Observation

/// Observable presentation state for the to-do list, over a ``TodoRepository`` port and a
/// ``PreferencesStoring`` port.
///
/// The template's worked example of a view model (`.claude/rules/core.md` › View models):
/// it holds the ports, not adapters, so `MyAppCoreTests` drives it with the in-memory
/// fake and `App/` hands it the SwiftData adapter. Every decision a reader can observe —
/// when Add is enabled, what an empty list says, what a failed save does to the row — is
/// made here, where the coverage floor sees it; `TodoListView` only renders it.
///
/// Action-shaped: the view calls one method per user intent (``addDraft()``,
/// ``toggle(_:)``, ``delete(atOffsets:)``, ``setHideCompleted(_:)``) and never mutates
/// ``items`` itself.
/// Time and identity are injected so a test can pin both.
@MainActor
@Observable
public final class TodoListViewModel {
    /// Where loading stands. An edit never moves it; only ``load()`` does.
    public enum Phase: Equatable, Sendable {
        /// The last ``load()`` failed; ``items`` is whatever was shown before it.
        case failed
        /// No load has finished: nothing has asked the repository yet, or the only load
        /// was cancelled — so the screen's next appearance asks again.
        case idle
        /// ``items`` reflects the repository.
        case loaded
        /// ``load()`` is waiting on the repository.
        case loading
    }

    /// A write the repository acknowledged while the newest ``load()`` was in flight. That
    /// load's fetch may have read the store before the write landed, so the write is
    /// replayed over its result rather than lost until the next load.
    private enum FetchOutcome {
        case cancelled
        case failed(TodoRepositoryError)
        /// The fetch with every write since it started replayed over it, and its count.
        case loaded([TodoItem], fetchedCount: Int)
        /// A newer fetch started while this one was in flight; it owns the state.
        case superseded
    }

    private enum AcknowledgedWrite {
        case deleted(TodoItem.ID)
        case saved(TodoItem)
    }

    /// Every item the repository holds, in ``TodoItem/isOrderedBefore(_:_:)`` order —
    /// hidden ones included. The list renders ``visibleItems``.
    public private(set) var items: [TodoItem] = []
    /// Where loading stands.
    public private(set) var phase: Phase = .idle
    /// The text in the new-item field. The view binds to it; only ``addDraft()`` clears it.
    public var draftTitle = ""
    /// Whether a save started by ``addDraft()`` is still in flight.
    public private(set) var isAdding = false
    /// The failure to present, or `nil`. Cleared by ``dismissFailure()``.
    public private(set) var failure: TodoListFailure?
    /// Whether done items are hidden: ``PreferenceKeys/hideCompleted``, read by
    /// ``load()`` and written by ``setHideCompleted(_:)``. Off until the first load.
    public private(set) var hideCompleted = false

    /// How many loads have started. A load that returns after a newer one started is
    /// superseded, and drops its result: the newest load is the only one that applies.
    private var loadGeneration = 0
    /// What ``phase`` was before the in-flight loads set `.loading` — what a cancelled
    /// load puts back.
    private var phaseBeforeLoading = Phase.idle
    /// The generation of the ``refresh()`` in flight, or `nil`. It is in flight only while
    /// it equals ``loadGeneration``: a newer load supersedes it.
    private var refreshGeneration: Int?
    /// Whether a load is in flight, so an acknowledged write is recorded for it.
    private var isRecordingWrites = false
    /// Writes acknowledged since the newest load started, in order. An edit outside a load
    /// records nothing.
    private var writesDuringLoad: [AcknowledgedWrite] = []

    private let repository: any TodoRepository
    private let preferences: any PreferencesStoring
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    /// Whether Add would do anything: the draft has a usable title and no add is in
    /// flight, so a double tap cannot store the same item twice.
    public var canAdd: Bool {
        !isAdding && TodoItem.normalizedTitle(draftTitle) != nil
    }

    /// The items the list shows: ``items`` without the done ones while ``hideCompleted``
    /// is on. `List.onDelete` offsets index this array (``delete(atOffsets:)``).
    public var visibleItems: [TodoItem] {
        hideCompleted ? items.filter { !$0.isDone } : items
    }

    /// Whether the list loaded, has items, and hides every one of them because each is
    /// done — the state that says so instead of looking empty.
    public var showsAllDoneState: Bool {
        phase == .loaded && !items.isEmpty && visibleItems.isEmpty
    }

    /// Whether the list loaded and is genuinely empty — not merely not loaded yet.
    public var showsEmptyState: Bool {
        phase == .loaded && items.isEmpty
    }

    /// Whether the list has nothing to show because loading failed — the case that
    /// offers a retry instead of an empty state.
    public var showsLoadFailure: Bool {
        phase == .failed && items.isEmpty
    }

    /// Whether the items are not known yet — nothing has loaded, or a load is running — so
    /// an identifier ``item(withID:)`` does not find may still arrive. The detail screen
    /// shows progress rather than "not found" while this holds, which covers a deep link
    /// that pushes it before the list under it ever loaded.
    public var isAwaitingItems: Bool {
        phase == .idle || phase == .loading
    }

    /// Whether the first load is still running with nothing on screen yet.
    public var showsProgress: Bool {
        phase == .loading && items.isEmpty
    }

    /// Creates the view model over `repository` and `preferences`. Nothing is read until
    /// ``load()``: touching storage in an initializer would make construction a side
    /// effect.
    ///
    /// `preferences` has no default: a composition root that forgot to wire it would
    /// otherwise compile and silently stop remembering the user's settings.
    public init(
        repository: any TodoRepository,
        preferences: any PreferencesStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() },
    ) {
        self.repository = repository
        self.preferences = preferences
        self.now = now
        self.makeID = makeID
    }

    /// Reads ``hideCompleted`` from the preferences, then replaces ``items`` with what the
    /// repository holds. The preference is read first, so it is current even when the
    /// repository fails.
    ///
    /// Safe to call while another load is in flight — `.task`, pull-to-refresh, Retry, and
    /// the detail screen can all ask at once, and a lifecycle ``refresh()`` can be running
    /// (`designing-core-logic`'s `view-models.md`):
    /// - The newest load wins. An older one that returns later drops its result, success
    ///   or failure, so a slow, stale fetch never overwrites a newer one.
    /// - An add, toggle, or delete the repository acknowledged while the load was in
    ///   flight is replayed over the loaded items, so it does not vanish from the screen.
    /// - A cancelled load is a no-op: no failure, ``items`` untouched, and ``phase`` back
    ///   to what it was before the load. Cancellation is read from `Task.isCancelled`
    ///   after the fetch, not from the port, because ``TodoRepositoryError`` has no
    ///   cancellation case — a store that sees its caller cancel reports a failure, which
    ///   the cancelled caller no longer wants (`.claude/rules/core.md` › Cancellation).
    public func load() async {
        hideCompleted = preferences.value(for: PreferenceKeys.hideCompleted)
        if phase != .loading {
            phaseBeforeLoading = phase
        }
        phase = .loading
        switch await fetch(for: beginFetch()) {
        case .superseded:
            // The newer load owns `items`, `phase`, and the write log.
            return

        case .cancelled:
            phase = phaseBeforeLoading

        case let .loaded(loaded, fetchedCount):
            items = loaded
            phase = .loaded
            AppLog.todos.debug("load: \(fetchedCount, privacy: .public) items")

        case let .failed(error):
            phase = .failed
            report(.loadFailed, error)
        }
    }

    /// Reloads what the list already shows, quietly: the refresh a scene's return to the
    /// foreground asks for (``SceneLifecycleModel``), which the user did not request.
    ///
    /// - It does nothing while ``phase`` is `.idle` or `.loading` — the screen's `.task`
    ///   is about to load or is loading — or while another refresh is in flight, so
    ///   several windows returning at once fetch once.
    /// - It never sets `.loading`, so no progress shows over the items already there.
    /// - A failure keeps ``items`` and ``phase``, presents no ``failure``, and is logged.
    /// - It shares ``load()``'s fetch: the newest of the two wins, and writes acknowledged
    ///   while it was in flight are replayed over its result.
    public func refresh() async {
        guard phase == .loaded || phase == .failed, refreshGeneration != loadGeneration else {
            AppLog.todos.debug("refresh: skipped, nothing loaded yet or a fetch is in flight")
            return
        }
        hideCompleted = preferences.value(for: PreferenceKeys.hideCompleted)
        let generation = beginFetch()
        refreshGeneration = generation
        let outcome = await fetch(for: generation)
        if refreshGeneration == generation {
            refreshGeneration = nil
        }
        switch outcome {
        case .cancelled, .superseded:
            return

        case let .loaded(loaded, fetchedCount):
            items = loaded
            phase = .loaded
            AppLog.todos.debug("refresh: \(fetchedCount, privacy: .public) items")

        case let .failed(error):
            AppLog.todos.error("refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stores the draft as a new item, then clears the draft.
    ///
    /// The row appears only once the save succeeded, so the list never shows an item the
    /// store does not have. The draft is cleared only if it still holds what was
    /// submitted: whatever the user typed while the save was in flight is theirs.
    public func addDraft() async {
        guard canAdd else {
            return
        }
        let submitted = draftTitle
        let item: TodoItem
        do {
            item = try TodoItem(id: makeID(), title: submitted, createdAt: now())
        } catch {
            // Unreachable while `canAdd` holds: both use `TodoItem.normalizedTitle`.
            return
        }
        isAdding = true
        defer { isAdding = false }
        do {
            try await repository.save(item)
        } catch {
            report(.saveFailed, error)
            return
        }
        recordWrite(.saved(item))
        items.append(item)
        items.sort(by: TodoItem.isOrderedBefore)
        if draftTitle == submitted {
            draftTitle = ""
        }
        AppLog.todos
            .debug("add: \(item.id, privacy: .public) title=\(item.title, privacy: .private)")
    }

    /// Flips the item's done state, keeping the row unchanged if the save fails.
    public func toggle(_ id: TodoItem.ID) async {
        guard var updated = items.first(where: { $0.id == id }) else {
            return
        }
        updated.isDone.toggle()
        do {
            try await repository.save(updated)
        } catch {
            report(.saveFailed, error)
            return
        }
        recordWrite(.saved(updated))
        // Found again by identifier: the list may have changed while the save was in flight.
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = updated
        }
    }

    /// Deletes the items at `offsets` in ``visibleItems`` — the rows the list shows, and
    /// the shape `List.onDelete` hands over. Resolving them against ``items`` would delete
    /// a hidden row whenever ``hideCompleted`` is on. Offsets are resolved to identifiers
    /// before anything suspends.
    public func delete(atOffsets offsets: IndexSet) async {
        let shown = visibleItems
        let ids = offsets.filter(shown.indices.contains).map { shown[$0].id }
        await delete(ids)
    }

    /// Deletes each item in turn, stopping at the first failure so the rows still shown
    /// are exactly the ones the store still has.
    public func delete(_ ids: [TodoItem.ID]) async {
        for id in ids {
            do {
                try await repository.delete(id: id)
            } catch .notFound {
                // Already gone: what the user asked for is true, so the row goes too.
            } catch {
                report(.deleteFailed, error)
                return
            }
            recordWrite(.deleted(id))
            items.removeAll { $0.id == id }
        }
    }

    /// Shows or hides done items, and remembers the choice for the next launch.
    public func setHideCompleted(_ hide: Bool) {
        hideCompleted = hide
        preferences.set(hide, for: PreferenceKeys.hideCompleted)
    }

    /// The item with `id`, looked up in ``items`` rather than ``visibleItems``: the
    /// detail screen, and a deep link to it, open an item that Hide Completed hides.
    /// `nil` when no loaded item has that identifier — deleted, or not loaded yet.
    public func item(withID id: TodoItem.ID) -> TodoItem? {
        items.first { $0.id == id }
    }

    /// Clears ``failure`` once the view has shown it.
    public func dismissFailure() {
        failure = nil
    }

    /// What VoiceOver reads for the done toggle of `item`, which is otherwise a glyph.
    public func toggleLabel(for item: TodoItem) -> LocalizedStringResource {
        item.isDone ? TodoListStrings.markNotDone : TodoListStrings.markDone
    }

    /// `loaded` with `writes` applied in order: a save replaces the item with its
    /// identifier or adds it, a delete removes it. Replaying a write the fetch already saw
    /// changes nothing, so it is safe whether the fetch read the store before or after it.
    private func replaying(
        _ writes: [AcknowledgedWrite],
        over loaded: [TodoItem],
    ) -> [TodoItem] {
        var result = loaded
        for write in writes {
            switch write {
            case let .deleted(id):
                result.removeAll { $0.id == id }

            case let .saved(item):
                if let index = result.firstIndex(where: { $0.id == item.id }) {
                    result[index] = item
                } else {
                    result.append(item)
                }
            }
        }
        return result.sorted(by: TodoItem.isOrderedBefore)
    }

    /// Starts a fetch, before anything suspends: a new generation and an empty write log.
    private func beginFetch() -> Int {
        loadGeneration += 1
        writesDuringLoad = []
        isRecordingWrites = true
        return loadGeneration
    }

    /// The fetch ``load()`` and ``refresh()`` share, and the latest-wins guard over it: a
    /// fetch that returns after a newer one began is `.superseded`, and drops its result.
    /// Cancellation is read from `Task.isCancelled` after the fetch, not from the port,
    /// because ``TodoRepositoryError`` has no cancellation case.
    private func fetch(for generation: Int) async -> FetchOutcome {
        let outcome: Result<[TodoItem], TodoRepositoryError>
        do {
            outcome = try await .success(repository.fetchAll())
        } catch {
            outcome = .failure(error)
        }
        guard generation == loadGeneration else {
            return .superseded
        }
        let writes = writesDuringLoad
        writesDuringLoad = []
        isRecordingWrites = false
        guard !Task.isCancelled else {
            return .cancelled
        }
        switch outcome {
        case let .success(loaded):
            return .loaded(replaying(writes, over: loaded), fetchedCount: loaded.count)

        case let .failure(error):
            return .failed(error)
        }
    }

    private func recordWrite(_ write: AcknowledgedWrite) {
        if isRecordingWrites {
            writesDuringLoad.append(write)
        }
    }

    private func report(_ failure: TodoListFailure, _ error: TodoRepositoryError) {
        self.failure = failure
        AppLog.todos.error(
            "\(String(describing: failure), privacy: .public): \(String(describing: error), privacy: .public)",
        )
    }
}
