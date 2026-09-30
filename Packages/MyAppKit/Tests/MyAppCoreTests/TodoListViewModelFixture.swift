import Foundation
import MyAppCore
import MyAppTestSupport

/// Shared values and builders for the `TodoListViewModel` suites.
@MainActor
enum TodoListViewModelFixture {
    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3_600
    static let start = Date(timeIntervalSinceReferenceDate: 0)
    /// What the injected clock answers: an hour after ``start``.
    static let now = start.addingTimeInterval(hour)
    /// What the injected identifier source answers.
    static let fixedID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A") ?? UUID()

    /// An open item created `minute` minutes after ``start``.
    static func item(_ title: String, minute minutes: Double) throws -> TodoItem {
        try TodoItem(
            id: UUID(),
            title: title,
            createdAt: start.addingTimeInterval(minutes * minute),
        )
    }

    /// A checked-off item created `minute` minutes after ``start``.
    static func doneItem(_ title: String, minute minutes: Double) throws -> TodoItem {
        try TodoItem(
            id: UUID(),
            title: title,
            createdAt: start.addingTimeInterval(minutes * minute),
            isDone: true,
        )
    }

    /// A view model over `repository` and a fresh, empty preferences fake, whose clock
    /// and identifier source are pinned.
    ///
    /// An overload rather than a default argument, which `discouraged_default_parameter`
    /// rejects on an internal function.
    static func model(over repository: some TodoRepository) -> TodoListViewModel {
        model(over: repository, preferences: InMemoryPreferences())
    }

    /// A view model over `repository` and `preferences` whose clock and identifier source
    /// are pinned.
    static func model(
        over repository: some TodoRepository,
        preferences: some PreferencesStoring,
    ) -> TodoListViewModel {
        let pinnedNow = now
        let pinnedID = fixedID
        return TodoListViewModel(
            repository: repository,
            preferences: preferences,
            now: { pinnedNow },
            makeID: { pinnedID },
        )
    }
}
