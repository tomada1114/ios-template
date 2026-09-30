import SwiftData

/// The record type the adapter uses: always the newest schema version's.
typealias TodoRecord = TodoSchemaV1.TodoRecord

/// How an older store reaches the current schema. Empty until a second version exists;
/// then each version is listed in order and each step between two gets a stage.
enum TodoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TodoSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
