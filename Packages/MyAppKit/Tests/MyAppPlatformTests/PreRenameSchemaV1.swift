import Foundation
import SwiftData

/// The migration plan as it stood beside ``PreRenameSchemaV1``.
enum PreRenameMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PreRenameSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// A frozen copy of the stored schema as it stood before #69 renamed the Swift types of
/// the schema and the plan: the same entity, attributes, unique constraint, and version
/// identifier, under a name of its own. `PersistenceStoreTests` writes a store with it
/// and reopens the file through ``PersistenceStore``, the proof that the store never
/// records those Swift names, so renaming them moved nothing on disk.
///
/// Never edit this to follow `AppSchemaV1`: it stands for stores already written.
enum PreRenameSchemaV1: VersionedSchema {
    @Model
    final class TodoRecord {
        @Attribute(.unique)
        var id: UUID
        var title: String
        var isDone: Bool
        var createdAt: Date

        init(id: UUID, title: String, isDone: Bool, createdAt: Date) {
            self.id = id
            self.title = title
            self.isDone = isDone
            self.createdAt = createdAt
        }
    }

    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TodoRecord.self]
    }
}
