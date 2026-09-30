import Foundation
import MyAppCore
import SwiftData

/// The SwiftData-backed adapter for ``MyAppCore/TodoRepository``.
///
/// The template's worked example of an adapter, and the shape every other one copies: it
/// imports the framework Core may not, translates between Core's value type and the
/// stored `@Model` record, maps every framework error into Core's error enum, and makes
/// no domain decision of its own. That is why `MyAppPlatform` sits outside the coverage
/// floor (`scripts/coverage.sh` measures `MyAppCore` only): what is checked here is the
/// translation, by `TodoRepositoryContract` in `MyAppPlatformTests` against an in-memory
/// store — under plain `just test`, in CI.
///
/// `@ModelActor` gives the adapter its own serial executor and a `ModelContext` bound to
/// it, so no `@Model` object ever leaves this actor and the main actor never waits on a
/// disk write it did not ask for.
@ModelActor
public actor SwiftDataTodoRepository: TodoRepository {
    /// Logs the framework error — the only place its detail survives — and answers
    /// Core's error. SwiftData's messages can quote stored values, so the detail is
    /// `.private`; the operation name is not user data.
    private static func storageFailure(
        _ error: any Error,
        during operation: StaticString,
    ) -> TodoRepositoryError {
        AppLog.persistence.error(
            "\(operation, privacy: .public) failed: \(String(describing: error), privacy: .private)",
        )
        return .storageFailure
    }

    public func fetchAll() throws(TodoRepositoryError) -> [TodoItem] {
        let records: [TodoRecord]
        do {
            records = try modelContext.fetch(FetchDescriptor<TodoRecord>())
        } catch {
            throw Self.storageFailure(error, during: "fetchAll")
        }
        var items: [TodoItem] = []
        items.reserveCapacity(records.count)
        for record in records {
            try items.append(record.item())
        }
        // Sorted here, by Core's rule, rather than by a SortDescriptor: the order is the
        // port's promise and must not depend on what a store's query can express.
        return items.sorted(by: TodoItem.isOrderedBefore)
    }

    public func save(_ item: TodoItem) throws(TodoRepositoryError) {
        do {
            if let existing = try record(id: item.id) {
                existing.update(from: item)
            } else {
                modelContext.insert(TodoRecord(item))
            }
            try modelContext.save()
        } catch {
            // A failed save leaves the change pending in the context; drop it, or the
            // next successful save would write it after all.
            modelContext.rollback()
            throw Self.storageFailure(error, during: "save")
        }
    }

    public func delete(id: TodoItem.ID) throws(TodoRepositoryError) {
        let found: TodoRecord?
        do {
            found = try record(id: id)
        } catch {
            throw Self.storageFailure(error, during: "delete")
        }
        guard let found else {
            throw .notFound(id)
        }
        modelContext.delete(found)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw Self.storageFailure(error, during: "delete")
        }
    }

    private func record(id: UUID) throws -> TodoRecord? {
        var descriptor = FetchDescriptor<TodoRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

extension SwiftDataTodoRepository {
    /// Where the store keeps its data.
    public enum Storage: Sendable {
        /// A store that lives and dies with the container — UI tests and previews.
        case inMemory
        /// SwiftData's default store file in the app's Application Support directory.
        case onDisk
    }

    /// Opens a store and returns an adapter over it, or
    /// ``MyAppCore/TodoRepositoryError/storageFailure`` when the container cannot be
    /// created (an unreadable file, or a migration that failed).
    public static func make(storage: Storage) throws(TodoRepositoryError) -> Self {
        do {
            return try Self(modelContainer: makeContainer(storage: storage))
        } catch {
            AppLog.persistence.fault(
                "opening the store failed: \(String(describing: error), privacy: .private)",
            )
            throw .storageFailure
        }
    }

    /// The container for the current schema, migrating an older store on the way.
    static func makeContainer(storage: Storage) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TodoSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: storage == .inMemory,
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TodoMigrationPlan.self,
            configurations: configuration,
        )
    }
}
