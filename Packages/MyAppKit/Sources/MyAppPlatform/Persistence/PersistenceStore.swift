import Foundation
import MyAppCore
import SwiftData

/// The app's one SwiftData store: the only place a `ModelContainer` is opened.
///
/// Every SwiftData repository runs over the same container, built from the app-wide
/// ``AppSchemaV1`` and ``AppMigrationPlan``. A repository that opened its own container
/// would bring its own schema to the same default store file, and a container whose
/// schema disagrees with what the file holds risks failing to open or damaging the
/// store. So `App/` opens the container once, through
/// ``makeContainer(storage:)``, and hands it to each repository's
/// `init(modelContainer:)` — `SwiftDataTodoRepository` is the worked example.
public enum PersistenceStore {
    /// Where the store keeps its data.
    public enum Storage: Sendable {
        /// A store file at the given URL — a test that must close a store and open the
        /// same file again, as a migration test does.
        case file(URL)
        /// A store that lives and dies with the container — UI tests and previews.
        case inMemory
        /// SwiftData's default store file in the app's Application Support directory.
        case onDisk
    }

    /// Opens the container for the current schema, migrating an older store on the way.
    ///
    /// Throws whatever SwiftData threw — an unreadable file, or a migration that failed —
    /// after logging it, so the caller only decides what the app runs on instead
    /// (`App/` hands every port its unavailable null object, such as
    /// ``MyAppCore/UnavailableTodoRepository``).
    public static func makeContainer(storage: Storage) throws -> ModelContainer {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: configuration(for: storage, schema: schema),
            )
        } catch {
            // SwiftData's message can quote a file path or stored values: `.private`.
            AppLog.persistence.fault(
                "opening the store failed: \(String(describing: error), privacy: .private)",
            )
            throw error
        }
    }

    private static func configuration(for storage: Storage, schema: Schema) -> ModelConfiguration {
        switch storage {
        case let .file(url):
            ModelConfiguration(schema: schema, url: url)

        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        case .onDisk:
            // No name and no URL: SwiftData's default file, where every earlier build
            // kept the store. Changing either moves the user's data out of reach.
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
    }
}
