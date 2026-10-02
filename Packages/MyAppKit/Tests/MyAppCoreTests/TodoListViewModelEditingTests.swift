import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// Toggling, deleting, and how failures are presented.
@MainActor
@Suite("TodoListViewModel — editing and failures")
struct TodoListViewModelEditingTests {
    typealias Fixture = TodoListViewModelFixture

    // MARK: - Toggling

    @Test
    func `toggling saves and flips the item`() async throws {
        let item = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [item])
        let model = Fixture.model(over: repository)
        await model.load()
        await model.toggle(item.id)
        #expect(model.items.first?.isDone == true)
        #expect(await repository.snapshot.first?.isDone == true)
        await model.toggle(item.id)
        #expect(model.items.first?.isDone == false)
    }

    @Test
    func `a failed toggle leaves the row as it was`() async throws {
        let item = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [item])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.fail(.save, with: .storageFailure)
        await model.toggle(item.id)
        #expect(model.items == [item])
        #expect(model.failure == .saveFailed)
    }

    @Test
    func `toggling an unknown item does nothing`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        await model.toggle(UUID())
        #expect(await repository.calls.isEmpty)
    }

    @Test
    func `the toggle is named for what it would do`() throws {
        let model = Fixture.model(over: InMemoryTodoRepository())
        let open = try Fixture.item("Open", minute: 1)
        let done = try Fixture.doneItem("Done", minute: 1)
        #expect(model.toggleLabel(for: open).english == "Mark as Done")
        #expect(model.toggleLabel(for: done).english == "Mark as Not Done")
    }

    // MARK: - Deleting

    @Test
    func `deleting by offset removes those rows from the store and the list`() async throws {
        let first = try Fixture.item("First", minute: 1)
        let second = try Fixture.item("Second", minute: 2)
        let repository = InMemoryTodoRepository(items: [first, second])
        let model = Fixture.model(over: repository)
        await model.load()
        await model.delete(atOffsets: IndexSet(integer: 0))
        #expect(model.items == [second])
        #expect(await repository.snapshot == [second])
    }

    @Test
    func `an offset past the end is ignored`() async throws {
        let item = try Fixture.item("Only", minute: 1)
        let repository = InMemoryTodoRepository(items: [item])
        let model = Fixture.model(over: repository)
        await model.load()
        await model.delete(atOffsets: IndexSet(integer: 5))
        #expect(model.items == [item])
        #expect(await repository.calls == [.fetchAll])
    }

    @Test
    func `a row already gone from the store is removed without a failure`() async throws {
        let item = try Fixture.item("Stale", minute: 1)
        let repository = InMemoryTodoRepository(items: [item])
        let model = Fixture.model(over: repository)
        await model.load()
        try await repository.delete(id: item.id)
        await model.delete([item.id])
        #expect(model.items.isEmpty)
        #expect(model.failure == nil)
    }

    @Test
    func `a failed delete stops and keeps the rows the store still has`() async throws {
        let first = try Fixture.item("First", minute: 1)
        let second = try Fixture.item("Second", minute: 2)
        let repository = InMemoryTodoRepository(items: [first, second])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.fail(.delete, with: .storageFailure)
        await model.delete([first.id, second.id])
        #expect(model.items == [first, second])
        #expect(model.failure == .deleteFailed)
        #expect(await repository.calls == [.fetchAll, .delete])
    }

    // MARK: - Failures

    @Test
    func `dismissing clears the failure`() async {
        let repository = InMemoryTodoRepository()
        await repository.fail(.fetchAll, with: .storageFailure)
        let model = Fixture.model(over: repository)
        await model.load()
        model.dismissFailure()
        #expect(model.failure == nil)
    }

    @Test(arguments: [
        (TodoListFailure.loadFailed, "Your items could not be loaded."),
        (TodoListFailure.saveFailed, "Your change could not be saved."),
        (TodoListFailure.deleteFailed, "The item could not be deleted."),
    ])
    func `each failure has its own message`(failure: TodoListFailure, english: String) {
        #expect(failure.message.english == english)
    }

    @Test(arguments: [TodoListFailure.loadFailed, .saveFailed, .deleteFailed])
    func `every failure presents under one title`(failure: TodoListFailure) {
        // Through the protocol, as the shared failure alert reads it.
        let presented: any PresentableFailure = failure
        #expect(presented.title.english == "Something Went Wrong")
        #expect(presented.message.english == failure.message.english)
    }

    @Test
    func `the failure alert is dismissed with OK`() {
        #expect(FailureStrings.dismiss.english == "OK")
    }

    @Test
    func `an unavailable store fails every operation`() async throws {
        let model = Fixture.model(over: UnavailableTodoRepository())
        await model.load()
        #expect(model.failure == .loadFailed)
        model.draftTitle = "Milk"
        await model.addDraft()
        #expect(model.failure == .saveFailed)
        let item = try Fixture.item("Ghost", minute: 1)
        await model.delete([item.id])
        #expect(model.failure == .deleteFailed)
    }
}
