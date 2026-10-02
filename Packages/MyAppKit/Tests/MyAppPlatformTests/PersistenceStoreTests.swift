import CoreData
import Foundation
import MyAppCore
@testable import MyAppPlatform
import SwiftData
import Testing

/// Fixed values and the pre-rename store writer for
/// ``SwiftDataTodoRepositoryTests/PersistenceStoreTests``.
private enum Fixture {
    /// What the store file says about the model that wrote it: the per-entity version
    /// hashes Core Data compares to decide on a migration, and the schema's version
    /// identifiers.
    struct ModelVersion: Equatable {
        var hashes: [String: Data]
        var identifiers: [String]

        var entities: [String] {
            hashes.keys.sorted()
        }
    }

    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    static let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
    static let minute: TimeInterval = 60
    static let firstCreatedAt = Date(timeIntervalSinceReferenceDate: minute)
    static let secondCreatedAt = firstCreatedAt.addingTimeInterval(minute)

    static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MyAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes two records through a container built from the frozen pre-rename schema,
    /// then lets that container go, so the reopen is a second open of the file.
    static func writePreRenameStore(at url: URL) throws {
        let schema = Schema(versionedSchema: PreRenameSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PreRenameMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(container)
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
        try context.save()
    }

    static func modelVersion(of url: URL) throws -> ModelVersion {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: url,
        )
        return ModelVersion(
            hashes: metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:],
            identifiers: metadata[NSStoreModelVersionIdentifiersKey] as? [String] ?? [],
        )
    }
}

extension SwiftDataTodoRepositoryTests {
    /// The app's one container: shared by every repository, and able to reopen a store
    /// file an earlier build wrote.
    ///
    /// Nested in `SwiftDataTodoRepositoryTests` so its `.serialized` trait covers these
    /// too — they open containers, and concurrent container creation is what that trait
    /// keeps out.
    @Suite("PersistenceStore")
    struct PersistenceStoreTests {
        @Test
        func `two repositories over one container see each other's writes`() async throws {
            let container = try PersistenceStore.makeContainer(storage: .inMemory)
            let writer = SwiftDataTodoRepository(modelContainer: container)
            let reader = SwiftDataTodoRepository(modelContainer: container)
            let item = try TodoItem(
                id: Fixture.firstID,
                title: "Shared",
                createdAt: Fixture.firstCreatedAt,
            )

            try await writer.save(item)
            #expect(try await reader.fetchAll() == [item])

            try await reader.delete(id: item.id)
            #expect(try await writer.fetchAll().isEmpty)
        }

        @Test
        func `a store written with the pre-rename schema reopens without data loss`() async throws {
            let directory = try Fixture.scratchDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appending(path: "pre-rename.store")

            try Fixture.writePreRenameStore(at: url)
            let written = try Fixture.modelVersion(of: url)

            let reopened = try PersistenceStore.makeContainer(storage: .file(url))
            let items = try await SwiftDataTodoRepository(modelContainer: reopened).fetchAll()

            // Oldest first, as every repository returns them: "Open", then "Done" a
            // minute later.
            #expect(try items == [
                TodoItem(id: Fixture.firstID, title: "Open", createdAt: Fixture.firstCreatedAt),
                TodoItem(
                    id: Fixture.secondID,
                    title: "Done",
                    createdAt: Fixture.secondCreatedAt,
                    isDone: true,
                ),
            ])
            // Unchanged hashes mean SwiftData found the file already at the current
            // model and migrated nothing: the rename did not touch the stored shape.
            #expect(try Fixture.modelVersion(of: url) == written)
            #expect(written.identifiers == ["1.0.0"])
            #expect(written.entities == ["TodoRecord"])
        }

        @Test
        func `a file that is not a store fails to open`() throws {
            let directory = try Fixture.scratchDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appending(path: "not-a.store")
            try Data("not a SQLite database".utf8).write(to: url)

            #expect(throws: (any Error).self) {
                try PersistenceStore.makeContainer(storage: .file(url))
            }
        }
    }
}
