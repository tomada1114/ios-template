import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// Hide Completed: the preference the view model reads on load and writes on change, and
/// what hiding does to the rows shown, the all-done state, and deleting by offset.
@MainActor
@Suite("TodoListViewModel — hide completed")
struct TodoListViewModelHideCompletedTests {
    typealias Fixture = TodoListViewModelFixture

    // MARK: - Reading and writing the preference

    @Test
    func `hideCompleted is read by load, not by the initializer`() async {
        let preferences = InMemoryPreferences()
        preferences.set(true, for: PreferenceKeys.hideCompleted)
        let model = Fixture.model(over: InMemoryTodoRepository(), preferences: preferences)
        #expect(!model.hideCompleted)
        await model.load()
        #expect(model.hideCompleted)
    }

    @Test
    func `hideCompleted is read even when the items cannot be`() async {
        let repository = InMemoryTodoRepository()
        await repository.fail(.fetchAll, with: .storageFailure)
        let preferences = InMemoryPreferences()
        preferences.set(true, for: PreferenceKeys.hideCompleted)
        let model = Fixture.model(over: repository, preferences: preferences)
        await model.load()
        #expect(model.phase == .failed)
        #expect(model.hideCompleted)
    }

    @Test
    func `an unset preference loads as off`() async {
        let model = Fixture.model(over: InMemoryTodoRepository())
        await model.load()
        #expect(!model.hideCompleted)
    }

    @Test(arguments: [true, false])
    func `setHideCompleted sets the property and writes the preference`(hide: Bool) {
        let preferences = InMemoryPreferences()
        preferences.set(!hide, for: PreferenceKeys.hideCompleted)
        let model = Fixture.model(over: InMemoryTodoRepository(), preferences: preferences)
        model.setHideCompleted(hide)
        #expect(model.hideCompleted == hide)
        #expect(preferences.snapshot["todoList.hideCompleted"] as? Bool == hide)
    }

    @Test
    func `a value set before load survives the load`() async {
        let preferences = InMemoryPreferences()
        let model = Fixture.model(over: InMemoryTodoRepository(), preferences: preferences)
        model.setHideCompleted(true)
        await model.load()
        #expect(model.hideCompleted)
    }

    // MARK: - What is shown

    @Test
    func `visibleItems drops done items only while hiding`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let open = try Fixture.item("Open", minute: 2)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [done, open]))
        await model.load()
        #expect(model.visibleItems == [done, open])
        model.setHideCompleted(true)
        #expect(model.visibleItems == [open])
        #expect(model.items == [done, open])
        model.setHideCompleted(false)
        #expect(model.visibleItems == [done, open])
    }

    @Test
    func `checking off an item hides it while hiding`() async throws {
        let open = try Fixture.item("Open", minute: 1)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [open]))
        await model.load()
        model.setHideCompleted(true)
        await model.toggle(open.id)
        #expect(model.visibleItems.isEmpty)
        #expect(model.showsAllDoneState)
    }

    @Test
    func `the all-done state shows when every item is done and hidden`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [done]))
        #expect(!model.showsAllDoneState)
        await model.load()
        #expect(!model.showsAllDoneState)
        model.setHideCompleted(true)
        #expect(model.showsAllDoneState)
        #expect(!model.showsEmptyState)
    }

    @Test
    func `the all-done state does not show while an item is still open`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let open = try Fixture.item("Open", minute: 2)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [done, open]))
        await model.load()
        model.setHideCompleted(true)
        #expect(!model.showsAllDoneState)
    }

    @Test
    func `an empty list shows the empty state, not the all-done state`() async {
        let model = Fixture.model(over: InMemoryTodoRepository())
        await model.load()
        model.setHideCompleted(true)
        #expect(model.showsEmptyState)
        #expect(!model.showsAllDoneState)
    }

    @Test
    func `a failed load never shows the all-done state`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let repository = InMemoryTodoRepository(items: [done])
        let model = Fixture.model(over: repository)
        await model.load()
        model.setHideCompleted(true)
        await repository.fail(.fetchAll, with: .storageFailure)
        await model.load()
        #expect(model.phase == .failed)
        #expect(!model.showsAllDoneState)
    }

    // MARK: - Deleting what is shown

    /// `List.onDelete` hands over offsets into what the `ForEach` iterates —
    /// `visibleItems` — so resolving them against `items` would delete a hidden row.
    @Test
    func `deleting by offset while hiding deletes the visible row`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let open = try Fixture.item("Open", minute: 2)
        let repository = InMemoryTodoRepository(items: [done, open])
        let model = Fixture.model(over: repository)
        await model.load()
        model.setHideCompleted(true)
        await model.delete(atOffsets: IndexSet(integer: 0))
        #expect(model.items == [done])
        #expect(await repository.snapshot == [done])
    }

    @Test
    func `an offset past the visible rows is ignored while hiding`() async throws {
        let done = try Fixture.doneItem("Done", minute: 1)
        let open = try Fixture.item("Open", minute: 2)
        let repository = InMemoryTodoRepository(items: [done, open])
        let model = Fixture.model(over: repository)
        await model.load()
        model.setHideCompleted(true)
        await model.delete(atOffsets: IndexSet(integer: 1))
        #expect(model.items == [done, open])
        #expect(await repository.calls == [.fetchAll])
    }
}
