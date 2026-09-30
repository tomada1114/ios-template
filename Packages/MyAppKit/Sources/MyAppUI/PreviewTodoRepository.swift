#if DEBUG
    import Foundation
    import MyAppCore

    /// A preview-only store, so each `#Preview` shows one state without SwiftData.
    ///
    /// `MyAppTestSupport`'s fake is test code no shipped module may import, and SwiftData
    /// lives in `MyAppPlatform`, which `MyAppUI` must not see — hence this small copy,
    /// compiled into Debug builds only.
    actor PreviewTodoRepository: TodoRepository {
        private var items: [TodoItem]

        init(titles: [String]) {
            let start = Date(timeIntervalSinceReferenceDate: 0)
            items = titles.enumerated().compactMap { offset, title in
                try? TodoItem(
                    id: UUID(),
                    title: title,
                    createdAt: start.addingTimeInterval(Double(offset)),
                    isDone: offset == 0,
                )
            }
        }

        func fetchAll() -> [TodoItem] {
            items
        }

        func save(_ item: TodoItem) {
            items.removeAll { $0.id == item.id }
            items.append(item)
            items.sort(by: TodoItem.isOrderedBefore)
        }

        func delete(id: TodoItem.ID) {
            items.removeAll { $0.id == id }
        }
    }
#endif
