import Foundation
import Observation

/// Observable presentation state for one to-do item's detail screen.
///
/// The worked example of a pushed screen with a view model of its own: the screen
/// ``AppRoute/todoDetail(_:)`` pushes is handed one by
/// ``AppModel/makeTodoDetailViewModel(id:)``, never the list's view model. It holds the
/// shared ``TodoListViewModel`` and the item's identifier, not a copy of the item, so it
/// shows the item as it is now — a toggle on the row, or a delete in another window,
/// shows here too — and decides what the screen shows while the list is still loading.
@MainActor
@Observable
public final class TodoDetailViewModel {
    /// What the detail screen shows.
    public enum Content: Equatable, Sendable {
        /// The item, as the list holds it now.
        case item(TodoItem)
        /// The items are not known yet, so the identifier may still arrive.
        case loading
        /// The list loaded, or failed to, and holds no item with this identifier — a
        /// deleted item, or a stale link.
        case notFound
    }

    private let list: TodoListViewModel
    private let id: TodoItem.ID

    /// What the screen shows now: the item when the list holds it — hidden by Hide
    /// Completed or not — progress while the list is still awaiting its items, and not
    /// found otherwise.
    public var content: Content {
        if let item = list.item(withID: id) {
            .item(item)
        } else if list.isAwaitingItems {
            .loading
        } else {
            .notFound
        }
    }

    /// Created only by ``AppModel/makeTodoDetailViewModel(id:)``, which decides what the
    /// model shares.
    init(list: TodoListViewModel, id: TodoItem.ID) {
        self.list = list
        self.id = id
    }

    /// Asks the shared list for its first load, if nothing has asked yet: a deep link can
    /// push this screen before the list under it ever appeared. A list that loaded, failed,
    /// or is loading is left alone.
    public func load() async {
        if list.phase == .idle {
            await list.load()
        }
    }

    /// Flips the item's done state — the list's own ``TodoListViewModel/toggle(_:)``, so a
    /// failure is reported where the list reports it.
    public func toggle() async {
        await list.toggle(id)
    }

    /// What VoiceOver reads for the done toggle of `item`, which is otherwise a glyph.
    public func toggleLabel(for item: TodoItem) -> LocalizedStringResource {
        list.toggleLabel(for: item)
    }
}
