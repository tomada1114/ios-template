import Foundation
import MyAppCore
@testable import MyAppPlatform
import SwiftData
import Testing

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
                id: StoreFixture.firstID,
                title: "Shared",
                createdAt: StoreFixture.firstCreatedAt,
            )

            try await writer.save(item)
            #expect(try await reader.fetchAll() == [item])

            try await reader.delete(id: item.id)
            #expect(try await writer.fetchAll().isEmpty)
        }

        @Test
        func `a store written with the pre-rename schema reopens without data loss`() async throws {
            let directory = try StoreFiles.scratchDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appending(path: "pre-rename.store")

            try StoreFixture.writePreRenameStore(at: url)
            let written = try StoreFiles.modelVersion(of: url)

            let reopened = try StoreFiles.reopen(url)
            let items = try await SwiftDataTodoRepository(modelContainer: reopened).fetchAll()

            // Oldest first, as every repository returns them: "Open", then "Done" a
            // minute later.
            #expect(try items == StoreFixture.storedItems())
            // Unchanged hashes mean SwiftData found the file already at the current
            // model and migrated nothing: the rename did not touch the stored shape.
            #expect(try StoreFiles.modelVersion(of: url) == written)
            #expect(written.identifiers == ["1.0.0"])
            #expect(written.entities == ["TodoRecord"])
        }

        @Test
        func `a file that is not a store fails to open`() throws {
            let directory = try StoreFiles.scratchDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appending(path: "not-a.store")
            try Data("not a SQLite database".utf8).write(to: url)

            #expect(throws: (any Error).self) {
                try PersistenceStore.makeContainer(storage: .file(url))
            }
        }
    }
}
