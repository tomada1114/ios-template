import Foundation
import MyAppCore
import Testing

/// The promises ``MyAppCore/TodoRepository`` makes, checked against any implementation.
///
/// A fake stands in for the adapter only while both keep the port's promises, so they are
/// written once, here, over the protocol rather than over either implementation.
/// `MyAppCoreTests` runs ``check(_:)`` against ``InMemoryTodoRepository``;
/// `MyAppPlatformTests` runs it against `SwiftDataTodoRepository` with an in-memory store.
/// Both run under `just test` and in CI. Every clause is one the port's `///` states; a
/// new clause is stated there first.
package enum TodoRepositoryContract {
    /// Fixed values, so a failure message names the same items on every run.
    enum Fixture {
        static let hour: TimeInterval = 3_600
        static let early = Date(timeIntervalSinceReferenceDate: 0)
        static let late = early.addingTimeInterval(hour)
        static let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        static let highID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
        static let lateID = UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID()
        static let missingID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF") ?? UUID()
    }

    /// A description of every broken promise, empty when `repository` keeps them all.
    /// `repository` must start empty.
    ///
    /// Separate from ``check(_:)`` so a test can hand it an implementation that breaks a
    /// promise and see the contract notice — the proof it is not vacuous.
    package static func violations(of repository: some TodoRepository) async -> [String] {
        var broken: [String] = []
        do {
            try await checkClauses(of: repository, into: &broken)
        } catch {
            broken.append("an operation the contract expects to succeed threw \(error)")
        }
        return broken
    }

    /// Records an issue for every promise `repository` breaks. `repository` must start empty.
    package static func check(_ repository: some TodoRepository) async {
        let broken = await violations(of: repository)
        #expect(
            broken.isEmpty,
            "\(type(of: repository)) breaks the TodoRepository contract: \(broken)",
        )
    }

    private static func checkClauses(
        of repository: some TodoRepository,
        into broken: inout [String],
    ) async throws {
        let late = try TodoItem(id: Fixture.lateID, title: "Late", createdAt: Fixture.late)
        let highTie = try TodoItem(id: Fixture.highID, title: "High", createdAt: Fixture.early)
        let lowTie = try TodoItem(id: Fixture.lowID, title: "Low", createdAt: Fixture.early)

        if try await !repository.fetchAll().isEmpty {
            broken.append("fetchAll on an empty repository returned items")
        }

        // Inserted newest-first, so a store that returns insertion order fails the order clause.
        for item in [late, highTie, lowTie] {
            try await repository.save(item)
        }
        let ordered = try await repository.fetchAll()
        if ordered != [lowTie, highTie, late] {
            broken
                .append("fetchAll did not return saved items in isOrderedBefore order: \(ordered)")
        }

        var toggled = highTie
        toggled.isDone = true
        try await repository.save(toggled)
        let afterUpdate = try await repository.fetchAll()
        if afterUpdate != [lowTie, toggled, late] {
            broken
                .append(
                    "save with a known identifier did not replace exactly that item: \(afterUpdate)",
                )
        }

        try await repository.delete(id: lowTie.id)
        let afterDelete = try await repository.fetchAll()
        if afterDelete != [toggled, late] {
            broken.append("delete did not remove exactly that item: \(afterDelete)")
        }

        do {
            try await repository.delete(id: Fixture.missingID)
            broken.append("delete of a missing identifier did not throw")
        } catch {
            if error != .notFound(Fixture.missingID) {
                broken.append("delete of a missing identifier threw \(error), not notFound")
            }
        }
    }
}
