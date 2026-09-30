import Foundation

/// Why a ``TodoItem`` could not be made.
public enum TodoItemError: Error, Equatable, Sendable {
    /// The title was empty once whitespace and newlines were trimmed.
    case emptyTitle
}

/// A to-do item — the template's worked example of a domain value.
///
/// A value type Core owns, never the persistence type an adapter stores it as
/// (`TodoRecord` in `MyAppPlatform`): that is what lets a view model, its tests, and
/// the fake repository all work without SwiftData. The invariant — a title is never
/// blank — is enforced here, once, so every layer above can rely on it.
public struct TodoItem: Identifiable, Hashable, Sendable {
    /// Identity across edits: a toggled item is the same item.
    public let id: UUID
    /// The trimmed, non-empty title (see ``normalizedTitle(_:)``).
    public let title: String
    /// Whether the item has been checked off.
    public var isDone: Bool
    /// When the item was created; with ``id`` it decides ``isOrderedBefore(_:_:)``.
    public let createdAt: Date

    /// Creates an item whose title passes ``normalizedTitle(_:)``.
    ///
    /// The same initializer serves user input and an adapter rehydrating a stored
    /// record, so a record that no longer satisfies the invariant is caught on the way
    /// in rather than rendered as a blank row.
    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        isDone: Bool = false,
    ) throws(TodoItemError) {
        guard let normalized = Self.normalizedTitle(title) else {
            throw .emptyTitle
        }
        self.id = id
        self.title = normalized
        self.isDone = isDone
        self.createdAt = createdAt
    }

    /// `raw` with surrounding whitespace and newlines removed, or `nil` when nothing is
    /// left — the one definition of "a usable title" the draft field and the
    /// initializer share.
    public static func normalizedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The list's display order: oldest first, ties broken by identifier so two items
    /// created in the same instant still sort the same way on every read.
    ///
    /// Every ``TodoRepository`` returns items in this order
    /// (`TodoRepositoryContract` checks it), so the order is defined here rather than
    /// separately by each store's query.
    public static func isOrderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
