import Foundation
import MyAppCore
import Testing

/// ``NavigationModel``'s stored path: what ``NavigationModel/encodedPath`` writes, what
/// ``NavigationModel/restore(from:)`` accepts, and the stored format itself, which is
/// contract — a scene's stored path is read back by whichever build launches next.
@MainActor
@Suite("NavigationModel restoration")
struct NavigationModelRestorationTests {
    static let firstID = "00000000-0000-0000-0000-000000000001"
    static let secondID = "00000000-0000-0000-0000-000000000002"
    static let first = AppRoute.todoDetail(UUID(uuidString: firstID) ?? UUID())
    static let second = AppRoute.todoDetail(UUID(uuidString: secondID) ?? UUID())

    /// The stored form of `[first]`, byte for byte as version 1 writes it. Typed by hand,
    /// never produced by the encoder: a build that stops reading or writing these bytes
    /// has changed the contract (`AGENTS.md` › What is contract and what is private).
    static let pinnedPayload =
        #"{"routes":[{"id":"00000000-0000-0000-0000-000000000001","screen":"todoDetail"}],"version":1}"#

    @Test
    func `a stored path restores into a fresh model`() {
        let source = NavigationModel()
        source.show(Self.first)
        source.show(Self.second)
        let restored = NavigationModel()
        restored.restore(from: source.encodedPath)
        #expect(restored.path == [Self.first, Self.second])
    }

    @Test
    func `the root's stored path restores to the root`() {
        let restored = NavigationModel()
        restored.restore(from: NavigationModel().encodedPath)
        #expect(restored.path.isEmpty)
    }

    @Test
    func `the pinned version 1 payload restores its route`() {
        let navigation = NavigationModel()
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        #expect(navigation.path == [Self.first])
    }

    @Test
    func `a path is stored as the pinned version 1 payload`() {
        let navigation = NavigationModel()
        navigation.show(Self.first)
        #expect(String(bytes: navigation.encodedPath, encoding: .utf8) == Self.pinnedPayload)
    }

    @Test
    func `the root is stored as version 1 with no routes`() {
        let stored = String(bytes: NavigationModel().encodedPath, encoding: .utf8)
        #expect(stored == #"{"routes":[],"version":1}"#)
    }

    @Test(arguments: [
        "",
        "not json",
        "[]",
        "{}",
        #"{"version":1}"#,
        #"{"routes":{},"version":1}"#,
        #"{"routes":[{"id":"00000000-0000-0000-0000-000000000001","screen":"todoDetail"}]}"#,
        #"{"routes":[{"id":"00000000-0000-0000-0000-000000000001","screen":"todoDetail"}],"version":"1"}"#,
    ])
    func `a payload that is not a stored path restores to the root`(payload: String) {
        let navigation = NavigationModel()
        navigation.restore(from: Data(payload.utf8))
        #expect(navigation.path.isEmpty)
    }

    @Test
    func `bytes that are not text restore to the root`() {
        let navigation = NavigationModel()
        navigation.restore(from: Data([0xFF, 0x00, 0xFE]))
        #expect(navigation.path.isEmpty)
    }

    @Test(arguments: [0, 2])
    func `a payload of a version this build does not know restores to the root`(version: Int) {
        let payload =
            #"{"routes":[{"id":"\#(Self.firstID)","screen":"todoDetail"}],"version":\#(version)}"#
        let navigation = NavigationModel()
        navigation.restore(from: Data(payload.utf8))
        #expect(navigation.path.isEmpty)
    }

    @Test(arguments: [
        #"{"id":"00000000-0000-0000-0000-000000000009","screen":"settings"}"#,
        #"{"screen":"settings"}"#,
        #"{"id":"not-a-uuid","screen":"todoDetail"}"#,
        #"{"id":7,"screen":"todoDetail"}"#,
        #"{"screen":"todoDetail"}"#,
        #"{"id":"00000000-0000-0000-0000-000000000009"}"#,
        #""todoDetail""#,
        "null",
    ])
    func `the path restores up to the first route this build cannot read`(
        unreadable: String,
    ) {
        let payload = """
        {"routes":[{"id":"\(Self.firstID)","screen":"todoDetail"},\(unreadable),\
        {"id":"\(Self.secondID)","screen":"todoDetail"}],"version":1}
        """
        let navigation = NavigationModel()
        navigation.restore(from: Data(payload.utf8))
        #expect(navigation.path == [Self.first])
    }

    @Test
    func `a path whose first route this build cannot read restores to the root`() {
        let payload = """
        {"routes":[{"id":"\(Self.firstID)","screen":"settings"},\
        {"id":"\(Self.secondID)","screen":"todoDetail"}],"version":1}
        """
        let navigation = NavigationModel()
        navigation.restore(from: Data(payload.utf8))
        #expect(navigation.path.isEmpty)
    }

    @Test(arguments: [
        "not json",
        #"{"routes":[{"id":"00000000-0000-0000-0000-000000000001","screen":"todoDetail"}],"version":2}"#,
        #"{"routes":[{"id":"00000000-0000-0000-0000-000000000001","screen":"settings"}],"version":1}"#,
    ])
    func `after a restore that ends at the root, the path to store is the root's`(payload: String) {
        let navigation = NavigationModel()
        navigation.restore(from: Data(payload.utf8))
        #expect(String(bytes: navigation.encodedPath, encoding: .utf8) ==
            #"{"routes":[],"version":1}"#)
    }

    @Test
    func `a field this build does not know is ignored`() {
        let payload = """
        {"future":true,"routes":[{"id":"\(Self.firstID)","note":"x","screen":"todoDetail"}],\
        "version":1}
        """
        let navigation = NavigationModel()
        navigation.restore(from: Data(payload.utf8))
        #expect(navigation.path == [Self.first])
    }

    @Test
    func `a lowercase identifier restores the same route`() {
        let payload =
            #"{"routes":[{"id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","screen":"todoDetail"}],"version":1}"#
        let navigation = NavigationModel()
        navigation.restore(from: Data(payload.utf8))
        let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()
        #expect(navigation.path == [.todoDetail(id)])
    }

    @Test
    func `only the first restore applies`() {
        let navigation = NavigationModel()
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        navigation.popToRoot()
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        #expect(navigation.path.isEmpty)
    }

    @Test
    func `a restore that read nothing still uses up the one restore`() {
        let navigation = NavigationModel()
        navigation.restore(from: Data("not json".utf8))
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        #expect(navigation.path.isEmpty)
    }

    @Test
    func `a restore after a push leaves the pushed path alone`() {
        let navigation = NavigationModel()
        navigation.show(Self.second)
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        #expect(navigation.path == [Self.second])
    }

    @Test
    func `a restore after a deep link leaves the linked screen alone`() throws {
        let navigation = NavigationModel()
        let url = try #require(URL(string: "my-app://todo/\(Self.secondID)"))
        navigation.open(url)
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        #expect(navigation.path == [Self.second])
    }

    @Test
    func `a restore after the path moved and came back to the root stays at the root`() {
        let navigation = NavigationModel()
        navigation.show(Self.second)
        navigation.popToRoot()
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        #expect(navigation.path.isEmpty)
    }

    @Test
    func `a sheet is not part of the stored path, so a restore presents none`() {
        let source = NavigationModel()
        source.show(Self.first)
        source.present(.about)
        let restored = NavigationModel()
        restored.restore(from: source.encodedPath)
        #expect(restored.path == [Self.first])
        #expect(restored.sheet == nil)
    }

    @Test
    func `a restore that pushes a route dismisses a sheet already up`() {
        let navigation = NavigationModel()
        navigation.present(.about)
        navigation.restore(from: Data(Self.pinnedPayload.utf8))
        #expect(navigation.path == [Self.first])
        #expect(navigation.sheet == nil)
    }

    @Test
    func `a route encodes to its stored name and identifier and decodes back`() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let stored = try String(bytes: encoder.encode(Self.first), encoding: .utf8)
        #expect(stored == #"{"id":"\#(Self.firstID)","screen":"todoDetail"}"#)
        let decoded = try JSONDecoder().decode(AppRoute.self, from: Data((stored ?? "").utf8))
        #expect(decoded == Self.first)
    }

    @Test
    func `decoding a route with an unknown stored name throws`() {
        let stored = Data(#"{"id":"\#(Self.firstID)","screen":"settings"}"#.utf8)
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppRoute.self, from: stored)
        }
        guard case let .dataCorrupted(context) = error else {
            Issue.record("expected dataCorrupted, got \(String(describing: error))")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["screen"])
    }

    @Test
    func `decoding a route whose identifier is not a UUID throws`() {
        let stored = Data(#"{"id":"not-a-uuid","screen":"todoDetail"}"#.utf8)
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppRoute.self, from: stored)
        }
        guard case let .dataCorrupted(context) = error else {
            Issue.record("expected dataCorrupted, got \(String(describing: error))")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["id"])
    }
}
