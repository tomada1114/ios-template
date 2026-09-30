import MyAppCore
import SwiftUI

/// One row: the done toggle and the title.
private struct TodoRow: View {
    let item: TodoItem
    let toggleLabel: LocalizedStringResource
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xSmall) {
            Button(action: toggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
                    // The glyph is smaller than a fingertip; the hit region is not.
                    .frame(
                        minWidth: DesignTokens.Size.minimumHitTarget,
                        minHeight: DesignTokens.Size.minimumHitTarget,
                    )
                    .contentShape(Rectangle())
            }
            // Borderless, so only the glyph toggles and a tap on the title does not.
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(toggleLabel))
            .accessibilityIdentifier("toggle-\(item.id.uuidString)")

            // The user's own text: verbatim, never looked up in a catalog.
            Text(verbatim: item.title)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
        }
    }
}

/// The app's single screen: the to-do list, with a quick-add bar pinned to the bottom.
///
/// Deliberately thin — every behavior it renders is owned and unit-tested by
/// `TodoListViewModel` in MyAppCore, and so is every word: the view has no localizable
/// literal of its own. It turns each user intent into one view-model call and reads
/// back the state to draw.
///
/// It does not own the model: the app shell creates it (in `@State`, so it survives the
/// scene) and hands it down. `@Bindable` is only what lets the text field bind to
/// ``TodoListViewModel/draftTitle``.
public struct TodoListView: View {
    @Bindable private var model: TodoListViewModel
    @FocusState private var isDraftFocused: Bool

    public var body: some View {
        NavigationStack {
            list
                .overlay { placeholder }
                .navigationTitle(Text(TodoListStrings.title))
                .safeAreaInset(edge: .bottom) { addBar }
                .refreshable { await model.load() }
                .task {
                    // Only the first appearance loads; a return to this screen keeps what
                    // is shown, and pull-to-refresh is the explicit way to reload.
                    if model.phase == .idle {
                        await model.load()
                    }
                }
                .alert(
                    Text(TodoListStrings.failureTitle),
                    isPresented: isFailurePresented,
                    presenting: model.failure,
                ) { _ in
                    Button(TodoListStrings.dismiss) { model.dismissFailure() }
                } message: { failure in
                    Text(failure.message)
                }
        }
    }

    private var list: some View {
        List {
            ForEach(model.items) { item in
                TodoRow(item: item, toggleLabel: model.toggleLabel(for: item)) {
                    Task { await model.toggle(item.id) }
                }
            }
            .onDelete { offsets in
                Task { await model.delete(atOffsets: offsets) }
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        if model.showsProgress {
            ProgressView()
        } else if model.showsLoadFailure {
            ContentUnavailableView {
                Label {
                    Text(TodoListStrings.failureTitle)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(TodoListFailure.loadFailed.message)
            } actions: {
                Button(TodoListStrings.retry) {
                    Task { await model.load() }
                }
                .accessibilityIdentifier("retryButton")
            }
        } else if model.showsEmptyState {
            ContentUnavailableView {
                Label {
                    Text(TodoListStrings.emptyTitle)
                } icon: {
                    Image(systemName: "checklist")
                }
            } description: {
                Text(TodoListStrings.emptyDescription)
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            TextField(
                text: $model.draftTitle,
                prompt: Text(TodoListStrings.draftPlaceholder),
            ) {
                Text(TodoListStrings.draftPlaceholder)
            }
            // Plain field on a filled, continuous rounded rectangle: the system's
            // `.roundedBorder` field is 34 pt tall and ignores a taller frame, so it
            // cannot reach the minimum hit target. A plain field takes focus only from a
            // tap on its text line, so the pill behind it is a button that focuses it:
            // a tap anywhere on the pill lands in the field. VoiceOver skips that button
            // and reaches the field itself.
            .textFieldStyle(.plain)
            .focused($isDraftFocused)
            .frame(minHeight: DesignTokens.Size.minimumHitTarget)
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .background {
                Button {
                    isDraftFocused = true
                } label: {
                    draftFieldShape.fill(.fill.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            .submitLabel(.done)
            .onSubmit { Task { await model.addDraft() } }
            .accessibilityIdentifier("newItemField")

            Button(TodoListStrings.add) {
                Task { await model.addDraft() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canAdd)
            .accessibilityIdentifier("addButton")
        }
        .padding()
        .background(.bar)
    }

    private var draftFieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
    }

    /// The alert's presentation, derived from the model: dismissing it (by any route)
    /// clears the failure, and a new failure presents it again.
    private var isFailurePresented: Binding<Bool> {
        Binding(
            get: { model.failure != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissFailure()
                }
            },
        )
    }

    /// Creates the view over `model`, which the caller owns.
    public init(model: TodoListViewModel) {
        self.model = model
    }
}

#if DEBUG
    #Preview("Items") {
        TodoListView(model: TodoListViewModel(
            repository: PreviewTodoRepository(titles: [
                "Buy milk",
                "Call the bank",
                "Water plants",
            ]),
        ))
    }

    #Preview("Empty") {
        TodoListView(model: TodoListViewModel(repository: PreviewTodoRepository(titles: [])))
    }

    #Preview("Load failed") {
        TodoListView(model: TodoListViewModel(repository: UnavailableTodoRepository()))
    }
#endif
