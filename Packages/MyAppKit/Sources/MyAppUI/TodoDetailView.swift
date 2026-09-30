import MyAppCore
import SwiftUI

/// One to-do item's detail screen: its title, when it was created, and its done toggle.
///
/// Pushed by ``AppRoute/todoDetail(_:)`` — from a row's link or a deep link — and handed
/// the list's view model rather than a copy of the item, so it shows the item as it is
/// now and a toggle here is the same action as on the row. An identifier no loaded item
/// has (a deleted item, a stale link) shows the not-found state instead.
public struct TodoDetailView: View {
    private let model: TodoListViewModel
    private let id: TodoItem.ID

    public var body: some View {
        Group {
            if let item = model.item(withID: id) {
                details(of: item)
            } else if model.isAwaitingItems {
                ProgressView()
            } else {
                notFound
            }
        }
        .accessibilityIdentifier("todoDetail")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                // A deep link can push this screen before the list under it ever
                // appeared, so it asks for the first load too; `load()` runs once either way.
                if model.phase == .idle {
                    await model.load()
                }
            }
    }

    private var notFound: some View {
        ContentUnavailableView {
            Label {
                Text(TodoDetailStrings.notFoundTitle)
            } icon: {
                Image(systemName: "questionmark.circle")
            }
        } description: {
            Text(TodoDetailStrings.notFoundDescription)
        }
    }

    /// Creates the detail screen of the item `id` names, looked up in `model`, which the
    /// caller owns.
    public init(model: TodoListViewModel, id: TodoItem.ID) {
        self.model = model
        self.id = id
    }

    private func details(of item: TodoItem) -> some View {
        Form {
            HStack(spacing: DesignTokens.Spacing.small) {
                TodoDoneToggle(isDone: item.isDone, label: model.toggleLabel(for: item)) {
                    Task { await model.toggle(item.id) }
                }
                .accessibilityIdentifier("detailToggle")

                // The user's own text: verbatim, never looked up in a catalog.
                Text(verbatim: item.title)
                    .font(.title2)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
            }

            LabeledContent {
                Text(item.createdAt, format: .dateTime)
            } label: {
                Text(TodoDetailStrings.created)
            }
        }
    }
}

#if DEBUG
    /// The detail screen of `stored`, over a store holding only it — or, when it is `nil`,
    /// of an identifier an empty store does not hold, for the not-found state.
    @MainActor
    private func detailPreview(of stored: TodoItem?) -> some View {
        let model = TodoListViewModel(
            repository: PreviewTodoRepository(items: stored.map { [$0] } ?? []),
            preferences: PreviewPreferences(),
        )
        return NavigationStack {
            TodoDetailView(model: model, id: stored?.id ?? UUID())
        }
    }

    #Preview("Found") {
        detailPreview(of: try? TodoItem(id: UUID(), title: "Buy milk", createdAt: .now))
    }

    #Preview("Found, done") {
        detailPreview(of: try? TodoItem(
            id: UUID(),
            title: "Buy milk",
            createdAt: .now,
            isDone: true,
        ))
    }

    #Preview("Not found") {
        detailPreview(of: nil)
    }
#endif
