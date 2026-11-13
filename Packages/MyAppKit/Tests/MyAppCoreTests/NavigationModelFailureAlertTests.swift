import Foundation
import MyAppCore
import Testing

/// ``NavigationModel`` holding a link back while its window presents a failure alert:
/// nothing moves under an alert, so the link waits for the person's answer, and the path
/// stays what the screen shows (#140). The model comes from
/// ``AppModel/makeNavigationModel(for:)``, which is what tells it about its window's
/// alerts.
@MainActor
@Suite("NavigationModel under a failure alert")
struct NavigationModelFailureAlertTests {
    static let linked = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()

    static func link() throws -> URL {
        try #require(URL(string: "my-app://todo/\(linked.uuidString)"))
    }

    /// The person taps the alert's button: the failure is dismissed, then the view
    /// reports the alert gone.
    static func answerTheAlert(
        in fixture: FailurePresentationFixture,
        of navigation: NavigationModel,
    ) {
        fixture.list.dismissFailure()
        navigation.failureAlertDidLeave()
    }

    @Test
    func `a link with no failure presented shows its screen at once`() async throws {
        let fixture = try await FailurePresentationFixture()
        let navigation = fixture.app.makeNavigationModel(for: fixture.scene(.active))
        #expect(try navigation.open(Self.link()))
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a link under this window's failure alert waits for the alert's answer`() async throws {
        let fixture = try await FailurePresentationFixture()
        let scene = fixture.scene(.active)
        let navigation = fixture.app.makeNavigationModel(for: scene)
        await fixture.failAToggle(from: scene)
        #expect(try navigation.open(Self.link()))
        #expect(navigation.path.isEmpty)
        Self.answerTheAlert(in: fixture, of: navigation)
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `the same link again after its screen showed leaves that screen on top`() async throws {
        let fixture = try await FailurePresentationFixture()
        let scene = fixture.scene(.active)
        let navigation = fixture.app.makeNavigationModel(for: scene)
        await fixture.failAToggle(from: scene)
        try navigation.open(Self.link())
        Self.answerTheAlert(in: fixture, of: navigation)
        navigation.popToRoot()
        try navigation.open(Self.link())
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a link under an alert over a sheet leaves the sheet up until the answer`() async throws {
        let fixture = try await FailurePresentationFixture()
        let scene = fixture.scene(.active)
        let navigation = fixture.app.makeNavigationModel(for: scene)
        navigation.present(.about)
        navigation.sheetDidStartPresenting()
        await fixture.failAToggle(from: scene)
        try navigation.open(Self.link())
        #expect(navigation.sheet == .about)
        #expect(navigation.path.isEmpty)

        Self.answerTheAlert(in: fixture, of: navigation)
        #expect(navigation.sheet == nil)
        #expect(navigation.path.isEmpty)
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a failure that arrives while the sheet leaves keeps the link waiting`() async throws {
        let fixture = try await FailurePresentationFixture()
        let scene = fixture.scene(.active)
        let navigation = fixture.app.makeNavigationModel(for: scene)
        navigation.present(.about)
        navigation.sheetDidStartPresenting()
        try navigation.open(Self.link())
        await fixture.failAToggle(from: scene)
        navigation.sheetDidLeave()
        #expect(navigation.path.isEmpty)
        Self.answerTheAlert(in: fixture, of: navigation)
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `an alert answered while a newer failure is up keeps the link waiting`() async throws {
        let fixture = try await FailurePresentationFixture()
        let scene = fixture.scene(.active)
        let navigation = fixture.app.makeNavigationModel(for: scene)
        await fixture.failAToggle(from: scene)
        try navigation.open(Self.link())
        let shown = scene.presented(fixture.list.reportedFailure)
        await fixture.failAToggle(from: scene)
        // The first alert's button: it names the failure it showed, which is gone.
        fixture.list.dismissFailure(shown)
        navigation.failureAlertDidLeave()
        #expect(navigation.path.isEmpty)
        Self.answerTheAlert(in: fixture, of: navigation)
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a link in a window that does not present the failure shows at once`() async throws {
        let fixture = try await FailurePresentationFixture()
        let presenter = fixture.scene(.active)
        let other = fixture.scene(.active)
        let navigation = fixture.app.makeNavigationModel(for: other)
        await fixture.failAToggle(from: presenter)
        #expect(fixture.presenters(among: [presenter, other]) == [0])
        try navigation.open(Self.link())
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a model built without a window waits on no alert`() async throws {
        let fixture = try await FailurePresentationFixture()
        let scene = fixture.scene(.active)
        await fixture.failAToggle(from: scene)
        let navigation = NavigationModel()
        try navigation.open(Self.link())
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }
}
