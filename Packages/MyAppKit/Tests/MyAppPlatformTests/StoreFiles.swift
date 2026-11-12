import CoreData
import Foundation
@testable import MyAppPlatform
import SwiftData

/// On-disk SwiftData stores for the tests that must close a store and open the same file
/// again: a store written with one schema version, reopened through the production
/// container the way a new build opens the store an earlier build left on a device.
///
/// The migration harness: the test for a new schema version writes a store with the
/// version before it here and reopens it with ``reopen(_:)``, which runs
/// ``PersistenceStore/makeContainer(storage:)`` and so `AppMigrationPlan`.
enum StoreFiles {
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

    /// A fresh directory of the test's own (`.claude/rules/testing.md` › Hygiene); the
    /// caller removes it in a `defer`.
    static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MyAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes a store at `url` with `version`'s schema, under `plan` — a plan whose last
    /// schema is `version`, as the build that shipped `version` had — inserting what
    /// `populate` inserts, then lets the container go, so the next open is a second open
    /// of the file.
    static func write(
        _ version: any VersionedSchema.Type,
        plan: any SchemaMigrationPlan.Type,
        at url: URL,
        populate: (ModelContext) throws -> Void,
    ) throws {
        let schema = Schema(versionedSchema: version)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: plan,
            configurations: ModelConfiguration(schema: schema, url: url),
        )
        let context = ModelContext(container)
        try populate(context)
        try context.save()
    }

    /// Opens the file at `url` the way the app opens its store: through the production
    /// container, migrating it to the current schema on the way.
    static func reopen(_ url: URL) throws -> ModelContainer {
        try PersistenceStore.makeContainer(storage: .file(url))
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
