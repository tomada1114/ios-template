import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// ``TodoListViewModel/refresh()``: the quiet reload a scene's return to the foreground
/// asks for. It refreshes only a list that has loaded, never shows progress or a failure,
/// and shares ``TodoListViewModel/load()``'s latest-wins fetch.
@MainActor
@Suite("TodoListViewModel refresh")
struct TodoListViewModelRefreshTests {
    typealias Fixture = TodoListViewModelFixture

    @Test
    func `a refresh before the first load fetches nothing`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        await model.refresh()
        #expect(await repository.calls.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test
    func `a refresh during a load fetches nothing`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Fixture.model(over: repository)
        await repository.onFetch { _ in
            await model.refresh()
        }
        await model.load()
        #expect(await repository.calls == [.fetchAll])
        #expect(model.items == [milk])
    }

    @Test
    func `a refresh during a refresh fetches nothing`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.onFetch { _ in
            await model.refresh()
        }
        await model.refresh()
        #expect(await repository.calls == [.fetchAll, .fetchAll])
    }

    @Test
    func `a refresh after a load shows what the store holds now`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let bread = try Fixture.item("Bread", minute: 2)
        let preferences = InMemoryPreferences()
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Fixture.model(over: repository, preferences: preferences)
        await model.load()
        try await repository.save(bread)
        preferences.set(true, for: PreferenceKeys.hideCompleted)
        await model.refresh()
        #expect(model.items == [milk, bread])
        #expect(model.phase == .loaded)
        #expect(model.hideCompleted)
    }

    @Test
    func `a refresh keeps the items on screen while it fetches`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.onFetch { _ in
            await MainActor.run {
                #expect(model.phase == .loaded)
                #expect(!model.showsProgress)
            }
        }
        await model.refresh()
        #expect(model.phase == .loaded)
    }

    @Test
    func `a failing refresh after a load keeps the items and presents no failure`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.fail(.fetchAll, with: .storageFailure)
        await model.refresh()
        #expect(await repository.calls == [.fetchAll, .fetchAll])
        #expect(model.items == [milk])
        #expect(model.phase == .loaded)
        #expect(model.failure == nil)
    }

    @Test
    func `a refresh after a failed load that succeeds shows the items`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Fixture.model(over: repository)
        await repository.fail(.fetchAll, with: .storageFailure)
        await model.load()
        model.dismissFailure()
        await repository.succeed(.fetchAll)
        await model.refresh()
        #expect(model.items == [milk])
        #expect(model.phase == .loaded)
        #expect(model.failure == nil)
    }

    @Test
    func `a failing refresh after a failed load stays failed and presents nothing new`() async {
        let repository = InMemoryTodoRepository()
        let model = Fixture.model(over: repository)
        await repository.fail(.fetchAll, with: .storageFailure)
        await model.load()
        model.dismissFailure()
        await model.refresh()
        #expect(model.phase == .failed)
        #expect(model.failure == nil)
    }

    @Test
    func `a load during a refresh supersedes it, and a later refresh still runs`() async throws {
        let old = try Fixture.item("Old", minute: 1)
        let new = try Fixture.item("New", minute: 2)
        let repository = InMemoryTodoRepository(items: [old])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.onFetch { _ in
            // Only the refresh's fetch acts: the second call overall.
            guard await repository.calls == [.fetchAll, .fetchAll] else {
                return
            }
            do {
                try await repository.save(new)
            } catch {
                Issue.record(error)
            }
            await model.load()
        }
        await model.refresh()
        #expect(model.items == [old, new])
        #expect(model.phase == .loaded)
        await model.refresh()
        #expect(await repository.calls.count { $0 == .fetchAll } == 4)
    }

    @Test
    func `an edit that finishes during a refresh survives it`() async throws {
        let stored = try Fixture.item("Stored", minute: 1)
        let repository = InMemoryTodoRepository(items: [stored])
        let model = Fixture.model(over: repository)
        await model.load()
        await repository.onFetch { _ in
            await MainActor.run { model.draftTitle = "Added" }
            await model.addDraft()
        }
        await model.refresh()
        let added = try TodoItem(id: Fixture.fixedID, title: "Added", createdAt: Fixture.now)
        #expect(model.items == [stored, added])
    }

    @Test
    func `a cancelled refresh changes nothing`() async throws {
        let milk = try Fixture.item("Milk", minute: 1)
        let bread = try Fixture.item("Bread", minute: 2)
        let repository = InMemoryTodoRepository(items: [milk])
        let model = Fixture.model(over: repository)
        await model.load()
        try await repository.save(bread)
        // Cancelled before it starts: the task cannot run until this test suspends.
        let refreshing = Task { await model.refresh() }
        refreshing.cancel()
        await refreshing.value
        #expect(model.items == [milk])
        #expect(model.phase == .loaded)
        #expect(model.failure == nil)
    }
}
