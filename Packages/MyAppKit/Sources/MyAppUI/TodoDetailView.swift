import MyAppCore
import SwiftUI

/// One to-do item's detail screen: its title, when it was created, and its done toggle.
///
/// Pushed by ``AppRoute/todoDetail(_:)`` — from a row's link or a deep link — over a
/// `TodoDetailViewModel` of its own, which `RootView` asks `AppModel` for. The model
/// decides what shows: the item as the list holds it now, progress while the list is
/// still loading, or the not-found state for an identifier no loaded item has (a deleted
/// item, a stale link).
public struct TodoDetailView: View {
    /// Kept in `@State`, so the screen holds the first model it was handed for as long as
    /// it is pushed, and a parent re-render that builds a new one does not replace it.
    @State private var model: TodoDetailViewModel

    public var body: some View {
        Group {
            switch model.content {
            case let .item(item):
                details(of: item)

            case .loading:
                ProgressView()

            case .notFound:
                notFound
            }
        }
        .accessibilityIdentifier("todoDetail")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            // A deep link can push this screen before the list under it ever appeared,
            // so the model asks for the first load too.
            .task { await model.load() }
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

    /// Creates the detail screen over `model` — built for its route by
    /// `AppModel.makeTodoDetailViewModel(id:)`.
    public init(model: TodoDetailViewModel) {
        _model = State(initialValue: model)
    }

    private func details(of item: TodoItem) -> some View {
        Form {
            HStack(spacing: DesignTokens.Spacing.small) {
                TodoDoneToggle(isDone: item.isDone, label: model.toggleLabel(for: item)) {
                    Task { await model.toggle() }
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
        let app = AppModel(
            repository: PreviewTodoRepository(items: stored.map { [$0] } ?? []),
            preferences: PreviewPreferences(),
        )
        return NavigationStack {
            TodoDetailView(model: app.makeTodoDetailViewModel(id: stored?.id ?? UUID()))
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
