import MyAppCore
import MyAppTestSupport
import Testing

/// What moves a failure from the window presenting it, and what does not: the presenter
/// is sticky (`designing-ui`'s `references/navigation.md` › A failure presents in one
/// window). It keeps the failure until its window closes, or goes to the background
/// while another window is in the foreground; `FailurePresentationTests` holds how it is
/// chosen in the first place.
@MainActor
@Suite("Failure presenter")
struct FailurePresenterTests {
    // MARK: - The presenter is sticky

    /// The presenting window hands the failure on when it leaves the foreground while
    /// another window is in it, so the failure is never left where nobody can see it —
    /// and does not take it back from under the person when it returns, even though its
    /// own action caused it.
    @Test
    func `a failure whose window left the foreground moves to another and stays there`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        scenes[1].sceneDidEnter(.inactive)
        #expect(loaded.presenters(among: scenes) == [1])
        scenes[1].sceneDidEnter(.background)
        #expect(loaded.presenters(among: scenes) == [0])
        scenes[1].sceneDidEnter(.inactive)
        scenes[1].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [0])
    }

    @Test
    func `a failure no window caused moves on only when its window leaves the foreground`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: nil)
        scenes[1].sceneDidEnter(.background)
        scenes[1].sceneDidEnter(.active)
        scenes[0].sceneDidEnter(.inactive)
        #expect(loaded.presenters(among: scenes) == [0])
        scenes[0].sceneDidEnter(.background)
        #expect(loaded.presenters(among: scenes) == [1])
        scenes[0].sceneDidEnter(.inactive)
        scenes[0].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [1])
    }

    /// The app going to the background and coming back moves nothing: the presenter is
    /// the last window to leave, so no other window is in the foreground to take the
    /// failure, and a window that comes back before it does not take it either.
    @Test(arguments: [[0, 1], [1, 0]])
    func `an app-wide trip through the background leaves the failure where it was`(
        returnOrder: [Int],
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[1])
        scenes[0].sceneDidEnter(.background)
        scenes[1].sceneDidEnter(.background)
        #expect(loaded.presenters(among: scenes) == [1])
        for index in returnOrder {
            scenes[index].sceneDidEnter(.inactive)
            scenes[index].sceneDidEnter(.active)
            #expect(loaded.presenters(among: scenes) == [1])
        }
    }

    /// Windows report the background one at a time. A presenter that reports it while
    /// another window is still recorded in the foreground cannot be told from one window
    /// being put away, so it hands the failure on — and the window that took it keeps it.
    @Test
    func `a presenter that leaves before the other window does hands the failure on for good`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[0])
        scenes[0].sceneDidEnter(.background)
        scenes[1].sceneDidEnter(.background)
        #expect(loaded.presenters(among: scenes) == [1])
        scenes[0].sceneDidEnter(.active)
        scenes[1].sceneDidEnter(.active)
        #expect(loaded.presenters(among: scenes) == [1])
    }

    @Test
    func `while every window is in the background a new failure still has one presenter`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active, .background), loaded.scene(.background)]
        await loaded.failAToggle(from: nil)
        #expect(loaded.presenters(among: scenes) == [0])
        await loaded.failAToggle(from: scenes[1])
        #expect(loaded.presenters(among: scenes) == [1])
    }

    // MARK: - A window that closes, or was never one

    /// Closing is a change the other window observes, so it presents at once.
    @Test
    func `a failure whose window closed presents in a window that is still open`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scenes = [loaded.scene(.active), loaded.scene(.active), loaded.scene(.active)]
        await loaded.failAToggle(from: scenes[2])
        scenes[2].sceneDidClose()
        #expect(loaded.presenters(among: scenes) == [0])
        scenes[0].sceneDidEnter(.background)
        scenes[0].sceneDidClose()
        #expect(loaded.presenters(among: scenes) == [1])
    }

    @Test
    func `the last window closing leaves the failure for the next window to open`() async throws {
        let loaded = try await FailurePresentationFixture()
        let only = loaded.scene(.active)
        await loaded.failAToggle(from: only)
        only.sceneDidClose()
        #expect(only.presented(loaded.list.reportedFailure) == nil)
        let next = loaded.scene(.inactive)
        #expect(next.presented(loaded.list.reportedFailure)?.failure == .saveFailed)
    }

    /// A phase reported after a close opens the window again: a close delivered for a
    /// window that is still there costs nothing lasting.
    @Test
    func `a closed window that reports a phase is an open window again`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scene = loaded.scene(.active)
        scene.sceneDidClose()
        scene.sceneDidEnter(.active)
        await loaded.failAToggle(from: scene)
        #expect(scene.presented(loaded.list.reportedFailure)?.failure == .saveFailed)
    }

    /// A window discarded without closing is not waited for: it is dropped at the next
    /// change any window reports.
    @Test
    func `a window that went without closing gives the failure up at the next change`(
    ) async throws {
        let loaded = try await FailurePresentationFixture()
        var gone: SceneLifecycleModel? = loaded.scene(.active)
        let open = loaded.scene(.active)
        await loaded.failAToggle(from: gone)
        gone = nil
        #expect(gone == nil)
        open.sceneDidEnter(.inactive)
        #expect(open.presented(loaded.list.reportedFailure)?.failure == .saveFailed)
    }

    /// `SceneRoot` builds a spare model on every re-render, which reports nothing: it is
    /// not a window, and must never be the one a failure is handed to.
    @Test
    func `a scene that has reported no phase presents nothing`() async throws {
        let loaded = try await FailurePresentationFixture()
        let spare = loaded.scene()
        let window = loaded.scene(.active)
        await loaded.failAToggle(from: nil)
        #expect(loaded.presenters(among: [spare, window]) == [1])
        await loaded.failAToggle(from: spare)
        #expect(loaded.presenters(among: [spare, window]) == [1])
    }

    @Test
    func `a failure reported before any window opened presents in the first to open`() async throws {
        let loaded = try await FailurePresentationFixture()
        await loaded.failAToggle(from: nil)
        let scenes = [loaded.scene(.active), loaded.scene(.active)]
        #expect(loaded.presenters(among: scenes) == [0])
    }

    @Test
    func `each scene has an identity of its own`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scene = loaded.scene()
        let ids = [scene.id, loaded.scene().id, loaded.scene(.active).id]
        #expect(Set(ids).count == 3)
        let copy = scene.id
        #expect(copy == scene.id)
    }

    @Test
    func `no failure is presented nowhere`() async throws {
        let loaded = try await FailurePresentationFixture()
        let scene = loaded.scene(.active)
        #expect(scene.presented(loaded.list.reportedFailure) == nil)
    }
}
