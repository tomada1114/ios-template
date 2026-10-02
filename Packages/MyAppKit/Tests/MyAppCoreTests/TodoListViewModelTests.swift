import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// Loading and adding. Editing an existing item is in `TodoListViewModelEditingTests`.
@MainActor
@Suite("TodoListViewModel — loading and adding")
struct TodoListViewModelTests {
    typealias Fixture = TodoListViewModelFixture

    // MARK: - Loading

    @Test
    func `starts idle, before anything asks the repository`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        #expect(model.phase == .idle)
        #expect(!model.showsEmptyState)
        #expect(!model.showsProgress)
        #expect(await repository.calls.isEmpty)
    }

    @Test
    func `load publishes the stored items in display order`() async throws {
        let first = try Fixture.item("First", minute: 1)
        let second = try Fixture.item("Second", minute: 2)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [second, first]))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.items == [first, second])
        #expect(!model.showsEmptyState)
    }

    @Test
    func `an empty store shows the empty state only once loaded`() async {
        let model = Fixture.model(over: InMemoryTodoRepository())
        #expect(!model.showsEmptyState)
        await model.load()
        #expect(model.showsEmptyState)
        #expect(!model.showsLoadFailure)
    }

    @Test
    func `a failed load offers a retry and reports the failure`() async {
        let repository = InMemoryTodoRepository()
        await repository.fail(.fetchAll, with: .storageFailure)
        let model = Fixture.model(over: repository)
        await model.load()
        #expect(model.phase == .failed)
        #expect(model.showsLoadFailure)
        #expect(!model.showsEmptyState)
        #expect(model.failure == .loadFailed)
    }

    @Test
    func `a retry after a failed load recovers`() async throws {
        let stored = try Fixture.item("Stored", minute: 1)
        let repository = InMemoryTodoRepository(items: [stored])
        await repository.fail(.fetchAll, with: .storageFailure)
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.succeed(.fetchAll)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.items == [stored])
    }

    @Test
    func `progress shows while the first load runs`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        let loading = Task { await model.load() }
        // The load sets its phase before its first suspension point.
        await Task.yield()
        #expect(model.phase == .loading || model.phase == .loaded)
        await loading.value
        #expect(!model.showsProgress)
    }

    // MARK: - Overlapping loads and cancellation

    @Test
    func `a refresh during a load applies only the newest result`() async throws {
        let old = try Fixture.item("Old", minute: 1)
        let new = try Fixture.item("New", minute: 2)
        let repository = InMemoryTodoRepository(items: [old])
        let model = Fixture.model(over: repository)
        await repository.onFetch { fetched in
            // Only the first fetch acts; its answer, `[old]`, is already stale once the
            // store gains `new` and a refresh loads that.
            guard fetched == [old] else {
                return
            }
            do {
                try await repository.save(new)
            } catch {
                Issue.record(error)
            }
            await model.load()
        }
        await model.load()
        #expect(model.items == [old, new])
        #expect(model.phase == .loaded)
        #expect(await repository.calls == [.fetchAll, .save, .fetchAll])
    }

    @Test
    func `an edit that finishes during a load survives it`() async throws {
        let stored = try Fixture.item("Stored", minute: 1)
        let repository = InMemoryTodoRepository(items: [stored])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.onFetch { _ in
            await MainActor.run { model.draftTitle = "Added" }
            await model.addDraft()
        }
        await model.load()
        let added = try TodoItem(id: Fixture.fixedID, title: "Added", createdAt: Fixture.now)
        #expect(model.items == [stored, added])
        #expect(await repository.snapshot == [stored, added])
        #expect(model.phase == .loaded)
    }

    @Test
    func `a toggle and a delete that finish during a load survive it`() async throws {
        let kept = try Fixture.item("Kept", minute: 1)
        let deleted = try Fixture.item("Deleted", minute: 2)
        let repository = InMemoryTodoRepository(items: [kept, deleted])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.onFetch { _ in
            await model.toggle(kept.id)
            await model.delete([deleted.id])
        }
        await model.load()
        var done = kept
        done.isDone = true
        #expect(model.items == [done])
        #expect(await repository.snapshot == [done])
    }

    @Test
    func `a cancelled load reports no failure`() async {
        let repository = InMemoryTodoRepository()
        // What a store that maps cancellation into its general failure answers.
        await repository.fail(.fetchAll, with: .storageFailure)
        let model = Fixture.model(over: repository)
        // Cancelled before it starts: the task cannot run until this test suspends.
        let loading = Task { await model.load() }
        loading.cancel()
        await loading.value
        #expect(model.failure == nil)
        #expect(!model.showsLoadFailure)
        // Back to idle, so the screen's next appearance asks again.
        #expect(model.phase == .idle)
    }

    @Test
    func `a cancelled reload keeps what was shown`() async throws {
        let shown = try Fixture.item("Shown", minute: 1)
        let arrived = try Fixture.item("Arrived", minute: 2)
        let repository = InMemoryTodoRepository(items: [shown])
        let model = Fixture.model(over: repository)
        await model.load()
        try await repository.save(arrived)
        let reloading = Task { await model.load() }
        reloading.cancel()
        await reloading.value
        #expect(model.items == [shown])
        #expect(model.phase == .loaded)
        #expect(model.failure == nil)
    }

    // MARK: - Adding

    @Test
    func `add is enabled only for a usable title`() {
        let model = Fixture.model(over: InMemoryTodoRepository())
        #expect(!model.canAdd)
        model.draftTitle = "   "
        #expect(!model.canAdd)
        model.draftTitle = "Milk"
        #expect(model.canAdd)
    }

    @Test
    func `adding stores a trimmed item, shows it, and clears the draft`() async throws {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        await model.load()
        model.draftTitle = "  Buy milk "
        await model.addDraft()
        let expected = try TodoItem(
            id: Fixture.fixedID,
            title: "Buy milk",
            createdAt: Fixture.now,
        )
        #expect(model.items == [expected])
        #expect(await repository.snapshot == [expected])
        #expect(model.draftTitle.isEmpty)
        #expect(!model.isAdding)
    }

    @Test
    func `adding a blank draft does nothing`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        model.draftTitle = " "
        await model.addDraft()
        #expect(await repository.calls.isEmpty)
        #expect(model.items.isEmpty)
    }

    @Test
    func `a failed add keeps the draft and shows no row`() async {
        let repository = InMemoryTodoRepository()
        await repository.fail(.save, with: .storageFailure)
        let model = Fixture.model(over: repository)
        model.draftTitle = "Buy milk"
        await model.addDraft()
        #expect(model.items.isEmpty)
        #expect(model.draftTitle == "Buy milk")
        #expect(model.failure == .saveFailed)
        #expect(!model.isAdding)
    }

    @Test
    func `text typed while a save is in flight is kept`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        await repository.onSave { _ in
            await MainActor.run { model.draftTitle = "Typed meanwhile" }
        }
        model.draftTitle = "Buy milk"
        await model.addDraft()
        #expect(model.items.map(\.title) == ["Buy milk"])
        #expect(model.draftTitle == "Typed meanwhile")
    }

    @Test
    func `a second add while the first is in flight is ignored`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        await repository.onSave { _ in
            await MainActor.run {
                #expect(model.isAdding)
                #expect(!model.canAdd)
            }
        }
        model.draftTitle = "Buy milk"
        async let first: Void = model.addDraft()
        async let second: Void = model.addDraft()
        _ = await (first, second)
        #expect(await repository.calls == [.save])
        #expect(model.items.count == 1)
    }

    @Test
    func `a new item is placed by creation time`() async throws {
        let later = try Fixture.item("Later", minute: 120)
        let model = Fixture.model(over: InMemoryTodoRepository(items: [later]))
        await model.load()
        model.draftTitle = "Now"
        await model.addDraft()
        #expect(model.items.map(\.title) == ["Now", "Later"])
    }
}
