import Foundation
import MyAppCore
@testable import MyAppPlatform
import MyAppTestSupport
import SwiftData
import Testing

/// The adapter half of the `TodoRepository` contract suite, plus what only the adapter
/// can get wrong: rehydrating a stored record and keeping stores apart.
///
/// SwiftData runs on the host with an in-memory store, so these run under plain
/// `just test` and in CI — no simulator, no device, no permission grant.
@Suite("SwiftDataTodoRepository")
struct SwiftDataTodoRepositoryTests {
    @Test
    func `the SwiftData adapter keeps the contract`() async throws {
        try await TodoRepositoryContract.check(SwiftDataTodoRepository.make(storage: .inMemory))
    }

    @Test
    func `two in-memory stores share nothing`() async throws {
        let first = try SwiftDataTodoRepository.make(storage: .inMemory)
        let second = try SwiftDataTodoRepository.make(storage: .inMemory)
        try await first.save(TodoItem(id: UUID(), title: "Only here", createdAt: .now))
        #expect(try await second.fetchAll().isEmpty)
    }

    @Test
    func `a stored record that breaks the title invariant is reported as corrupted`() async throws {
        let container = try SwiftDataTodoRepository.makeContainer(storage: .inMemory)
        let item = try TodoItem(id: UUID(), title: "Fine", createdAt: .now)
        let context = ModelContext(container)
        let record = TodoRecord(item)
        record.title = "   "
        context.insert(record)
        try context.save()

        let repository = SwiftDataTodoRepository(modelContainer: container)
        await #expect(throws: TodoRepositoryError.corruptedRecord(item.id)) {
            try await repository.fetchAll()
        }
    }
}
