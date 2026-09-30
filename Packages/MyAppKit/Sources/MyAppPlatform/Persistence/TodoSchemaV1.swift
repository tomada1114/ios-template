import Foundation
import MyAppCore
import SwiftData

/// The first version of the stored schema.
///
/// Versioned from day one because the stored shape is contract (`docs/architecture.md`
/// › What is contract): an installed app's store outlives every build, so a change to a
/// `@Model` class that the shipped schema does not describe is a migration, not an
/// edit. The next change adds `TodoSchemaV2` beside this one and a stage to
/// ``TodoMigrationPlan``; this enum is then never edited again.
enum TodoSchemaV1: VersionedSchema {
    /// SwiftData's stored shape of a ``MyAppCore/TodoItem``. Internal to this module: no
    /// `@Model` object ever crosses the port, which speaks only Core's value types.
    ///
    /// `@Attribute(.unique)` makes a save with a known identifier an update rather than
    /// a duplicate row. CloudKit sync does not allow unique constraints, so an app that
    /// turns sync on replaces it with a fetch-before-insert in a new schema version.
    @Model
    final class TodoRecord {
        @Attribute(.unique)
        var id: UUID
        var title: String
        var isDone: Bool
        var createdAt: Date

        init(_ item: TodoItem) {
            id = item.id
            title = item.title
            isDone = item.isDone
            createdAt = item.createdAt
        }

        /// Copies what may change about an item. Identity and creation time never do.
        func update(from item: TodoItem) {
            title = item.title
            isDone = item.isDone
        }

        /// Core's value for this record, or ``MyAppCore/TodoRepositoryError/corruptedRecord(_:)``
        /// when the stored title no longer satisfies ``MyAppCore/TodoItem``'s invariant.
        func item() throws(TodoRepositoryError) -> TodoItem {
            do {
                return try TodoItem(id: id, title: title, createdAt: createdAt, isDone: isDone)
            } catch {
                throw .corruptedRecord(id)
            }
        }
    }

    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TodoRecord.self]
    }
}
