import Foundation
import MyAppCore
import Testing

/// ``NavigationModel``: the navigation path as Core state, and what a deep link does to it.
@MainActor
@Suite("NavigationModel")
struct NavigationModelTests {
    static let first = AppRoute.todoDetail(
        UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
    )
    static let second = AppRoute.todoDetail(
        UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
    )
    static let linked = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()

    @Test
    func `starts at the root`() {
        #expect(NavigationModel().path.isEmpty)
    }

    @Test
    func `show appends the route to the path`() {
        let navigation = NavigationModel()
        navigation.show(Self.first)
        #expect(navigation.path == [Self.first])
        navigation.show(Self.second)
        #expect(navigation.path == [Self.first, Self.second])
    }

    @Test
    func `popToRoot empties the path`() {
        let navigation = NavigationModel()
        navigation.show(Self.first)
        navigation.show(Self.second)
        navigation.popToRoot()
        #expect(navigation.path.isEmpty)
    }

    @Test
    func `popToRoot at the root leaves it there`() {
        let navigation = NavigationModel()
        navigation.popToRoot()
        #expect(navigation.path.isEmpty)
    }

    @Test
    func `opening a valid link replaces a deeper path with its one route`() throws {
        let navigation = NavigationModel()
        navigation.show(Self.first)
        navigation.show(Self.second)
        let url = try #require(URL(string: "my-app://todo/\(Self.linked.uuidString)"))
        #expect(navigation.open(url))
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test
    func `opening a valid link at the root shows its route`() throws {
        let navigation = NavigationModel()
        let url = try #require(URL(string: "my-app://todo/\(Self.linked.uuidString)"))
        #expect(navigation.open(url))
        #expect(navigation.path == [.todoDetail(Self.linked)])
    }

    @Test(arguments: [
        "https://example.com/todo/3F2504E0-4F89-11D3-9A0C-0305E82C3301",
        "my-app://todo/not-a-uuid",
        "my-app://settings",
    ])
    func `opening an invalid link leaves the path alone`(link: String) throws {
        let navigation = NavigationModel()
        navigation.show(Self.first)
        let url = try #require(URL(string: link))
        #expect(!navigation.open(url))
        #expect(navigation.path == [Self.first])
    }
}
