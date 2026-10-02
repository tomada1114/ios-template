import Foundation
import Observation

/// A failure the list reports, from whichever screen caused it — the detail screen's
/// toggle is the list's. Which store failed, and why, stays in the log.
public enum TodoListFailure: Equatable, PresentableFailure {
    /// A delete could not be completed.
    case deleteFailed
    /// ``TodoListViewModel/load()`` could not read the repository.
    case loadFailed
    /// An add or a toggle could not be saved.
    case saveFailed

    /// Every case shares one headline; ``message`` says what did not happen.
    public var title: LocalizedStringResource {
        TodoListStrings.failureTitle
    }

    /// The sentence the alert shows for this failure.
    public var message: LocalizedStringResource {
        switch self {
        case .deleteFailed:
            LocalizedStringResource(
                "todoList.failure.delete",
                defaultValue: "The item could not be deleted.",
                bundle: .module,
                comment: "Alert message when deleting a to-do item failed.",
            )

        case .loadFailed:
            LocalizedStringResource(
                "todoList.failure.load",
                defaultValue: "Your items could not be loaded.",
                bundle: .module,
                comment: "Alert message when the saved to-do items could not be read.",
            )

        case .saveFailed:
            LocalizedStringResource(
                "todoList.failure.save",
                defaultValue: "Your change could not be saved.",
                bundle: .module,
                comment: "Alert message when adding or checking off a to-do item could not be saved.",
            )
        }
    }
}

/// Observable presentation state for the to-do list, over a ``TodoRepository`` port and a
/// ``PreferencesStoring`` port.
///
/// The template's worked example of a view model (`docs/architecture.md` › View models):
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
    /// Where the first load stands. A later action never moves it back to `loading`.
    public enum Phase: Equatable, Sendable {
        /// The last ``load()`` failed; ``items`` is whatever was shown before it.
        case failed
        /// Nothing has asked the repository yet.
        case idle
        /// ``items`` reflects the repository.
        case loaded
        /// ``load()`` is waiting on the repository.
        case loading
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
    public func load() async {
        hideCompleted = preferences.value(for: PreferenceKeys.hideCompleted)
        phase = .loading
        do {
            let loaded = try await repository.fetchAll()
            items = loaded
            phase = .loaded
            // A local, not `self.items`: the message is an autoclosure that needs an
            // explicit `self`, which SwiftFormat's redundantSelf rule would strip.
            AppLog.todos.debug("load: \(loaded.count, privacy: .public) items")
        } catch {
            phase = .failed
            report(.loadFailed, error)
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

    private func report(_ failure: TodoListFailure, _ error: TodoRepositoryError) {
        self.failure = failure
        AppLog.todos.error(
            "\(String(describing: failure), privacy: .public): \(String(describing: error), privacy: .public)",
        )
    }
}
