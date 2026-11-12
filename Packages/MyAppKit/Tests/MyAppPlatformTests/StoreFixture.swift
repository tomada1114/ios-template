import Foundation
import MyAppCore
@testable import MyAppPlatform
import SwiftData

/// Fixed values and store writers shared by the suites that write a store file and
/// reopen it (`PersistenceStoreTests`, `SchemaMigrationTests`): two records, "Open" and
/// "Done" a minute later, written with a given schema version.
enum StoreFixture {
    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    static let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
    static let minute: TimeInterval = 60
    static let firstCreatedAt = Date(timeIntervalSinceReferenceDate: minute)
    static let secondCreatedAt = firstCreatedAt.addingTimeInterval(minute)

    /// What every writer below stores, as Core's values, oldest first — the order every
    /// repository returns them in.
    static func storedItems() throws -> [TodoItem] {
        try [
            TodoItem(id: firstID, title: "Open", createdAt: firstCreatedAt),
            TodoItem(id: secondID, title: "Done", createdAt: secondCreatedAt, isDone: true),
        ]
    }

    /// Writes the two records with the frozen pre-rename schema.
    static func writePreRenameStore(at url: URL) throws {
        try StoreFiles
            .write(PreRenameSchemaV1.self, plan: PreRenameMigrationPlan.self, at: url) { context in
                context.insert(PreRenameSchemaV1.TodoRecord(
                    id: firstID,
                    title: "Open",
                    isDone: false,
                    createdAt: firstCreatedAt,
                ))
                context.insert(PreRenameSchemaV1.TodoRecord(
                    id: secondID,
                    title: "Done",
                    isDone: true,
                    createdAt: secondCreatedAt,
                ))
            }
    }

    /// Writes the two records with the current schema — `AppMigrationPlan`'s last
    /// version, whose record type `TodoRecord` names.
    static func writeCurrentStore(
        _ version: any VersionedSchema.Type,
        at url: URL,
    ) throws {
        let items = try storedItems()
        try StoreFiles.write(version, plan: AppMigrationPlan.self, at: url) { context in
            for item in items {
                context.insert(TodoRecord(item))
            }
        }
    }
}
