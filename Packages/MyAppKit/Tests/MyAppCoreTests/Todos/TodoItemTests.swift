import Foundation
import MyAppCore
import Testing

@Suite("TodoItem")
struct TodoItemTests {
    static let created = Date(timeIntervalSinceReferenceDate: 0)

    @Test
    func `a title is stored trimmed`() throws {
        let item = try TodoItem(id: UUID(), title: "  Buy milk \n", createdAt: Self.created)
        #expect(item.title == "Buy milk")
        #expect(!item.isDone)
    }

    @Test(arguments: ["", " ", "\n\t "])
    func `a blank title is rejected`(title: String) {
        #expect(throws: TodoItemError.emptyTitle) {
            try TodoItem(id: UUID(), title: title, createdAt: Self.created)
        }
    }

    @Test
    func `normalizing keeps inner whitespace and drops a blank title`() {
        #expect(TodoItem.normalizedTitle(" a  b ") == "a  b")
        #expect(TodoItem.normalizedTitle("   ") == nil)
    }

    @Test
    func `older items come first`() throws {
        let older = try TodoItem(id: UUID(), title: "Older", createdAt: Self.created)
        let newer = try TodoItem(
            id: UUID(),
            title: "Newer",
            createdAt: Self.created.addingTimeInterval(1),
        )
        #expect(TodoItem.isOrderedBefore(older, newer))
        #expect(!TodoItem.isOrderedBefore(newer, older))
    }

    @Test
    func `a tie in creation time is broken by identifier`() throws {
        let low = try TodoItem(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            title: "Low",
            createdAt: Self.created,
        )
        let high = try TodoItem(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            title: "High",
            createdAt: Self.created,
        )
        #expect(TodoItem.isOrderedBefore(low, high))
        #expect(!TodoItem.isOrderedBefore(high, low))
        #expect(!TodoItem.isOrderedBefore(low, low))
    }
}
