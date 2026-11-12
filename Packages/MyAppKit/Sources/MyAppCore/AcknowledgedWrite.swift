/// A write the repository acknowledged while a load of the list was in flight
/// (``TodoListViewModel/load(from:)``). That load's fetch may have read the store before
/// the write landed, so the write is replayed over its result rather than lost until the
/// next load.
enum AcknowledgedWrite {
    case deleted(TodoItem.ID)
    case saved(TodoItem)

    /// `loaded` with `writes` applied in order: a save replaces the item with its
    /// identifier or adds it, a delete removes it. Replaying a write the fetch already saw
    /// changes nothing, so it is safe whether the fetch read the store before or after it.
    static func replaying(_ writes: [Self], over loaded: [TodoItem]) -> [TodoItem] {
        var result = loaded
        for write in writes {
            switch write {
            case let .deleted(id):
                result.removeAll { $0.id == id }

            case let .saved(item):
                if let index = result.firstIndex(where: { $0.id == item.id }) {
                    result[index] = item
                } else {
                    result.append(item)
                }
            }
        }
        return result.sorted(by: TodoItem.isOrderedBefore)
    }
}
