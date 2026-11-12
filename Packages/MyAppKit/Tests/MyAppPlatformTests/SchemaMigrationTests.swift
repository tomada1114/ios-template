import Foundation
import MyAppCore
@testable import MyAppPlatform
import SwiftData
import Testing

/// The two versions a migration stage joins, by the identity of their schema types.
private struct StageEndpoints: Equatable {
    var source: ObjectIdentifier
    var destination: ObjectIdentifier

    init(source: any VersionedSchema.Type, destination: any VersionedSchema.Type) {
        self.source = ObjectIdentifier(source)
        self.destination = ObjectIdentifier(destination)
    }

    /// `MigrationStage` is SDK-owned, so an unknown case answers `nil`, which fails the
    /// caller's comparison rather than passing it.
    init?(_ stage: MigrationStage) {
        switch stage {
        case let .lightweight(source, destination):
            self.init(source: source, destination: destination)

        case let .custom(source, destination, _, _):
            self.init(source: source, destination: destination)

        @unknown default:
            return nil
        }
    }
}

extension SwiftDataTodoRepositoryTests {
    /// The stored schema as contract (`AGENTS.md` › What is contract and what is private):
    /// every shipped version keeps the shape it shipped with, the migration plan reaches
    /// the version the app opens, and a store written by one version reopens through the
    /// production container.
    ///
    /// Nested in `SwiftDataTodoRepositoryTests` so its `.serialized` trait keeps these
    /// container opens out of every other suite's way, as `PersistenceStoreTests` is.
    @Suite("SchemaMigration", .serialized)
    struct SchemaMigrationTests {
        @Test
        func `every shipped schema version keeps the shape it shipped with`() {
            #expect(AppMigrationPlan.schemas.isEmpty == false)
            var planVersions: Set<String> = []
            for version in AppMigrationPlan.schemas {
                let actual = SchemaFingerprint(version)
                planVersions.insert(actual.version)
                guard let pinned = ShippedSchema.fingerprints[actual.version] else {
                    Issue.record("""
                    \(version) (\(actual.version)) has no pinned fingerprint. Write its row \
                    in ShippedSchema.fingerprints (ShippedSchema.swift) by hand, from \
                    \(version)'s @Model source — never from this test's output.
                    """)
                    continue
                }
                #expect(actual == pinned, """
                \(version) (\(actual.version)) no longer has the shape stores on users' \
                devices were written with. A shipped schema version is never edited: \
                restore it, and add a new VersionedSchema plus an AppMigrationPlan stage \
                instead (the persisting-data skill). Expected:
                \(pinned)
                Found:
                \(actual)
                """)
            }
            for orphan in Set(ShippedSchema.fingerprints.keys).subtracting(planVersions).sorted() {
                Issue.record("""
                Schema version \(orphan) is pinned in ShippedSchema.fingerprints but is no \
                longer in AppMigrationPlan.schemas. A shipped schema version is never \
                removed or renamed, nor its version identifier changed: stores on users' \
                devices were written with it. Restore it, and add a new VersionedSchema \
                plus an AppMigrationPlan stage instead (the persisting-data skill).
                """)
            }
        }

        @Test
        func `a type name drops the app's modules and the schema type, not Swift's or Foundation's`() {
            let names = TypeNames(AppSchemaV1.self)
            #expect(names.normalized(UUID.self) == "Foundation.UUID")
            #expect(names.normalized(String?.self) == "Swift.Optional<Swift.String>")
            #expect(names.normalized([AppSchemaV1.TodoRecord].self) == "Swift.Array<TodoRecord>")
            #expect(names.normalized(TodoItem?.self) == "Swift.Optional<TodoItem>")
            #expect(names
                .normalized([String: TodoItem].self) == "Swift.Dictionary<Swift.String, TodoItem>")
        }

        @Test
        func `the production container opens the migration plan's last schema`() throws {
            let last = try #require(AppMigrationPlan.schemas.last)
            let container = try PersistenceStore.makeContainer(storage: .inMemory)

            #expect(container.schema == Schema(versionedSchema: last))
            #expect(container.schema.version == last.versionIdentifier)
            let plan = try #require(container.migrationPlan)
            #expect(ObjectIdentifier(plan) == ObjectIdentifier(AppMigrationPlan.self))
        }

        @Test
        func `the migration plan lists versions in order, joined by one stage each`() {
            let schemas = AppMigrationPlan.schemas
            var versions: [Schema.Version] = []
            for schema in schemas {
                versions.append(schema.versionIdentifier)
            }
            let ascending = zip(versions, versions.dropFirst()).allSatisfy { $0 < $1 }
            #expect(
                ascending,
                "AppMigrationPlan.schemas must list versions oldest first: \(versions)",
            )

            // Stage i joins version i to version i + 1, by the identity of the schema types.
            let expected = zip(schemas, schemas.dropFirst()).map { source, destination in
                StageEndpoints(source: source, destination: destination)
            }
            let actual = AppMigrationPlan.stages.map(StageEndpoints.init)
            #expect(actual == expected)
        }

        @Test
        func `a store written with the current schema reopens through the production container`(
        ) async throws {
            let current = try #require(AppMigrationPlan.schemas.last)
            let directory = try StoreFiles.scratchDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appending(path: "current.store")

            try StoreFixture.writeCurrentStore(current, at: url)
            let written = try StoreFiles.modelVersion(of: url)

            let reopened = try StoreFiles.reopen(url)
            let items = try await SwiftDataTodoRepository(modelContainer: reopened).fetchAll()

            #expect(try items == StoreFixture.storedItems())
            #expect(written.identifiers == ["1.0.0"])
            #expect(try StoreFiles.modelVersion(of: url) == written)
        }
    }
}
