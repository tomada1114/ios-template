import SwiftData

/// The record type the adapter uses: always the newest schema version's.
typealias TodoRecord = AppSchemaV1.TodoRecord

/// How an older store reaches the current schema — the whole app's, every entity in it.
/// Empty until a second version exists; then each version is listed in order and each
/// step between two gets a stage.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
