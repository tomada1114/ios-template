import MyAppCore
import MyAppTestSupport
import Testing

/// Which window presents the shared list's failure: the list is app-wide and every window
/// renders it, so Core picks exactly one of them (`designing-ui`'s
/// `references/navigation.md` › A failure presents in one window).
///
/// The presenter is chosen when the failure is reported — the window whose action caused
/// it if that window is in the foreground, otherwise the one that has been in the
/// foreground longest, otherwise the first open window — and is sticky: it keeps the
/// failure until it closes, or goes to the background while another window is in the
/// foreground.
@MainActor
@Suite("Failure presentation")
struct FailurePresentationTests {
    typealias Fixture = TodoListViewModelFixture

    // MARK: - The scene that caused it

    @Test
    func `a failure from one window presents there and not in the other open window`() async throws {
        let loaded = try await FailurePresentationFixture()
        let first = loaded.scene(.active)
        let second = loaded.scene(.active)
        await loaded.failAToggle(from: second)
        #expect(loaded.list.reportedFailure?.scene == second.id)
        #expect(second.presented(loaded.list.reportedFailure)?.failure == .saveFailed)
        #expect(first.presented(loaded.list.reportedFailure) == nil)
    }

    @Test
    func `every action that can fail names the window that asked for it`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scene = loaded.scene(.active)
        let list = loaded.list

        await loaded.repository.fail(.save, with: .storageFailure)
        list.draftTitle = "Bread"
        await list.addDraft(from: scene.id)
        #expect(list.failure == .saveFailed)
        #expect(list.reportedFailure?.scene == scene.id)
        list.dismissFailure()

        await loaded.repository.fail(.delete, with: .storageFailure)
        await list.delete(atOffsets: [0], from: scene.id)
        #expect(list.failure == .deleteFailed)
        #expect(list.reportedFailure?.scene == scene.id)
        list.dismissFailure()

        await list.delete([loaded.milk.id], from: scene.id)
        #expect(list.failure == .deleteFailed)
        #expect(list.reportedFailure?.scene == scene.id)
        list.dismissFailure()

        await loaded.repository.fail(.fetchAll, with: .storageFailure)
        await list.load(from: scene.id)
        #expect(list.failure == .loadFailed)
        #expect(list.reportedFailure?.scene == scene.id)
    }

    @Test
    func `a detail screen's toggle fails as its own window's`() async throws {
        let loaded = try await FailurePresentationFixture()
        let first = loaded.scene(.active)
        let second = loaded.scene(.active)
        let detail = loaded.app.makeTodoDetailViewModel(id: loaded.milk.id, scene: second.id)
        await loaded.repository.fail(.save, with: .storageFailure)
        await detail.toggle()
        #expect(loaded.list.failure == .saveFailed)
        #expect(loaded.presenters(among: [first, second]) == [1])
    }

    /// A deep link can push the detail screen before the list ever loaded, so its load is
    /// the list's first, and fails as its window's.
    @Test
    func `a detail screen's first load fails as its own window's`() async {
        let repository = InMemoryTodoRepository()
        let app = AppModel(repository: repository, preferences: InMemoryPreferences())
        let first = app.makeSceneLifecycleModel()
        let second = app.makeSceneLifecycleModel()
        first.sceneDidEnter(.active)
        second.sceneDidEnter(.active)
        await repository.fail(.fetchAll, with: .storageFailure)
        await app.makeTodoDetailViewModel(id: Fixture.fixedID, scene: second.id).load()
        #expect(second.presented(app.todoList.reportedFailure)?.failure == .loadFailed)
        #expect(first.presented(app.todoList.reportedFailure) == nil)
    }

    /// One failure is held at a time, as in one window: the newer one replaces the older,
    /// and its presenter is chosen afresh, where it was caused.
    @Test
    func `a second failure from another window replaces the first and presents there`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let first = loaded.scene(.active)
        let second = loaded.scene(.active)
        await loaded.failAToggle(from: first)
        await loaded.repository.fail(.delete, with: .storageFailure)
        await loaded.list.delete([loaded.milk.id], from: second.id)
        #expect(first.presented(loaded.list.reportedFailure) == nil)
        #expect(second.presented(loaded.list.reportedFailure)?.failure == .deleteFailed)
    }

    /// The first failure moved to another window; the next one does not inherit that.
    @Test
    func `a second failure is presented by the rule, not where the first one ended up`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[0])
        scenes[0].sceneDidEnter(.background)
        scenes[0].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [1])
        await loaded.failAToggle(from: scenes[0])
        #expect(loaded.presenters(among: scenes) == [0])
    }

    // MARK: - No scene caused it

    @Test
    func `a failure no window caused presents in the one that came to the foreground first`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: nil)
        #expect(loaded.list.failure == .saveFailed)
        #expect(loaded.list.reportedFailure?.scene == nil)
        #expect(loaded.presenters(among: scenes) == [0])
    }

    @Test
    func `a failure that arrives after its window went to the background presents in another`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active, .inactive, .background)]
        await loaded.failAToggle(from: scenes[1])
        #expect(loaded.presenters(among: scenes) == [0])
        scenes[1].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [0])
    }

    // MARK: - Dismissal

    @Test
    func `dismissing the failure a window presented clears it for every window`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[0])
        loaded.list.dismissFailure(scenes[0].presented(loaded.list.reportedFailure))
        #expect(loaded.list.failure == nil)
        #expect(loaded.list.reportedFailure == nil)
        #expect(loaded.presenters(among: scenes).isEmpty)
    }

    /// A window that presents nothing has nothing to dismiss: its alert's button is built
    /// over `nil`.
    @Test
    func `a dismissal from a window that is not presenting the failure changes nothing`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        loaded.list.dismissFailure(scenes[0].presented(loaded.list.reportedFailure))
        #expect(loaded.list.failure == .saveFailed)
        #expect(loaded.presenters(among: scenes) == [1])
    }

    /// A window whose alert was replaced by another failure may still deliver its button's
    /// tap: it names the failure it showed, so it cannot dismiss the one that replaced it —
    /// not even the same kind of failure from the same window.
    @Test
    func `a dismissal of a failure that was replaced changes nothing`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[0])
        let shown = scenes[0].presented(loaded.list.reportedFailure)
        await loaded.failAToggle(from: scenes[1])
        loaded.list.dismissFailure(shown)
        #expect(loaded.presenters(among: scenes) == [1])
        await loaded.failAToggle(from: scenes[0])
        loaded.list.dismissFailure(shown)
        #expect(loaded.list.failure == .saveFailed)
        #expect(loaded.presenters(among: scenes) == [0])
    }

    @Test
    func `a failure after a dismissed one is presented where it was caused`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        loaded.list.dismissFailure()
        #expect(loaded.list.reportedFailure == nil)
        await loaded.failAToggle(from: scenes[0])
        #expect(loaded.presenters(among: scenes) == [0])
    }
}
