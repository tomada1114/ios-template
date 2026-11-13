import Foundation
import MyAppCore
import Testing

/// ``NavigationModel`` holding a link back while a sheet covers the stack: UIKit drops a
/// change to the stack that arrives while a presentation is in flight, so the path moves
/// only once the sheet has left, and until then it stays what the screen shows (#140).
/// A failure alert covering the stack is `NavigationModelFailureAlertTests`.
@MainActor
@Suite("NavigationModel waiting link")
struct NavigationModelWaitingLinkTests {
    static let first = AppRoute.todoDetail(
        UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
    )
    static let linked = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()
    static let other = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3302") ?? UUID()

    static func link(to id: UUID) throws -> URL {
        try #require(URL(string: "my-app://todo/\(id.uuidString)"))
    }

    /// A model whose About sheet the root view has started presenting.
    static func navigationWithASheetOnScreen() -> NavigationModel {
        let navigation = NavigationModel()
        navigation.present(.about)
        navigation.sheetDidStartPresenting()
        return navigation
    }

    @Test
    func `no sheet is on screen at the start`() {
        #expect(!NavigationModel().isSheetOnScreen)
    }

    @Test
    func `a sheet is on screen once the view starts presenting it, until it has left`() {
        let navigation = NavigationModel()
        navigation.present(.about)
        #expect(!navigation.isSheetOnScreen)
        navigation.sheetDidStartPresenting()
        #expect(navigation.isSheetOnScreen)
        navigation.dismissSheet(.about)
        #expect(navigation.isSheetOnScreen)
        navigation.sheetDidLeave()
        #expect(!navigation.isSheetOnScreen)
    }

    @Test
    func `a sheet that left while another was asked for leaves a sheet on screen`() {
        let navigation = Self.navigationWithASheetOnScreen()
        navigation.dismissSheet(.about)
        navigation.present(.about)
        navigation.sheetDidLeave()
        #expect(navigation.isSheetOnScreen)
        #expect(navigation.sheet == .about)
    }

    @Test
    func `a link under a sheet on screen dismisses it and waits for it to leave`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        #expect(try navigation.open(Self.link(to: Self.linked)))
        #expect(navigation.sheet == nil)
        #expect(navigation.path.isEmpty)
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a waiting link replaces a deeper path with its one route`() throws {
        let navigation = NavigationModel()
        navigation.show(Self.first)
        navigation.present(.about)
        navigation.sheetDidStartPresenting()
        try navigation.open(Self.link(to: Self.linked))
        #expect(navigation.path == [Self.first])
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a second link replaces the one that is waiting`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        try navigation.open(Self.link(to: Self.other))
        #expect(navigation.path.isEmpty)
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.other)])
    }

    @Test
    func `the same link opened again while it waits still shows its screen once`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        try navigation.open(Self.link(to: Self.linked))
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a link that waited is applied once, not again when a later sheet leaves`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        navigation.sheetDidLeave()
        navigation.popToRoot()
        navigation.present(.about)
        navigation.sheetDidStartPresenting()
        navigation.dismissSheet(.about)
        navigation.sheetDidLeave()
        #expect(navigation.path.isEmpty)
    }

    @Test(arguments: [
        "https://example.com/todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301",
        "my-app://todo/not-a-uuid",
    ])
    func `an invalid link leaves a waiting link waiting`(link: String) throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        #expect(try !navigation.open(#require(URL(string: link))))
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a sheet asked for while a link waits is closed by the link`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        navigation.present(.about)
        navigation.sheetDidLeave()
        #expect(navigation.sheet == nil)
        #expect(navigation.path.isEmpty)
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `the stored path is the screen on show, not a link that still waits`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        let stored = String(bytes: navigation.encodedPath, encoding: .utf8)
        #expect(stored == #"{"routes":[],"version":1}"#)
    }

    @Test
    func `a restore after a link that still waits leaves the window to the link`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        let stored = #"{"routes":[{"id":"00000000-0000-0000-0000-000000000001","screen":"todoDetail"}],"version":1}"#
        navigation.restore(from: Data(stored.utf8))
        #expect(navigation.path.isEmpty)
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `a push while a link waits drops the link`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        navigation.show(Self.first)
        navigation.sheetDidLeave()
        #expect(navigation.path == [Self.first])
    }

    @Test
    func `popToRoot while a link waits drops the link`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        navigation.popToRoot()
        navigation.sheetDidLeave()
        #expect(navigation.path.isEmpty)
    }

    @Test
    func `a sheet or an alert leaving with no link waiting moves nothing`() {
        let navigation = NavigationModel()
        navigation.show(Self.first)
        navigation.present(.about)
        navigation.sheetDidStartPresenting()
        navigation.failureAlertDidLeave()
        #expect(navigation.sheet == .about)
        navigation.dismissSheet(.about)
        navigation.sheetDidLeave()
        #expect(navigation.path == [Self.first])
    }

    @Test
    func `an alert leaving while the sheet is still leaving keeps the link waiting`() throws {
        let navigation = Self.navigationWithASheetOnScreen()
        try navigation.open(Self.link(to: Self.linked))
        navigation.failureAlertDidLeave()
        #expect(navigation.path.isEmpty)
        navigation.sheetDidLeave()
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }
}
