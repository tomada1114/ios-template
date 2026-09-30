import MyAppCore
import SwiftUI

/// One row: the done toggle, and the title as a link to the item's detail screen.
private struct TodoRow: View {
    let item: TodoItem
    let toggleLabel: LocalizedStringResource
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xSmall) {
            // Borderless inside, so a tap on the glyph toggles and does not follow the link.
            TodoDoneToggle(isDone: item.isDone, label: toggleLabel, toggle: toggle)
                .accessibilityIdentifier("toggle-\(item.id.uuidString)")

            NavigationLink(value: AppRoute.todoDetail(item.id)) {
                // The user's own text: verbatim, never looked up in a catalog.
                Text(verbatim: item.title)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
            }
        }
    }
}

/// The app's root screen: the to-do list, with a quick-add bar pinned to the bottom, and
/// the navigation stack every other screen is pushed onto.
///
/// Deliberately thin — every behavior it renders is owned and unit-tested by
/// `TodoListViewModel` in MyAppCore, and so is every word: the view has no localizable
/// literal of its own. It turns each user intent into one view-model call and reads
/// back the state to draw.
///
/// It owns neither model: the app shell creates the view model once for the app and the
/// navigation model once per scene (both in `@State`), and hands them down. `@Bindable`
/// is only what lets the text field bind to
/// ``TodoListViewModel/draftTitle`` and the stack bind to ``NavigationModel/path``, so a
/// row's link, the back button, and a deep link all move the same Core state.
public struct TodoListView: View {
    @Bindable private var model: TodoListViewModel
    @Bindable private var navigation: NavigationModel
    @FocusState private var isDraftFocused: Bool

    public var body: some View {
        NavigationStack(path: $navigation.path) {
            list
                .overlay { placeholder }
                .navigationTitle(Text(TodoListStrings.title))
                .toolbar {
                    // `.primaryAction` rather than an iOS-only placement: MyAppUI also
                    // compiles for macOS.
                    ToolbarItem(placement: .primaryAction) { hideCompletedToggle }
                }
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
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .todoDetail(id):
                        TodoDetailView(model: model, id: id)
                    }
                }
        }
    }

    private var list: some View {
        List {
            ForEach(model.visibleItems) { item in
                TodoRow(item: item, toggleLabel: model.toggleLabel(for: item)) {
                    Task { await model.toggle(item.id) }
                }
            }
            // The offsets index `visibleItems`, which is what the view model resolves them
            // against.
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
        } else if model.showsAllDoneState {
            ContentUnavailableView {
                Label {
                    Text(TodoListStrings.allDoneTitle)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            } description: {
                Text(TodoListStrings.allDoneDescription)
            }
        }
    }

    /// A toolbar button that stays pressed while done items are hidden. The toolbar gives
    /// it the system's hit target and shows the symbol alone; the title is what VoiceOver
    /// reads.
    private var hideCompletedToggle: some View {
        Toggle(isOn: isHidingCompleted) {
            Label {
                Text(TodoListStrings.hideCompleted)
            } icon: {
                Image(systemName: "eye.slash")
            }
        }
        .toggleStyle(.button)
        .accessibilityIdentifier("hideCompletedToggle")
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

    /// Hide Completed, built from the model's action so every change is remembered.
    private var isHidingCompleted: Binding<Bool> {
        Binding(
            get: { model.hideCompleted },
            set: { model.setHideCompleted($0) },
        )
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

    /// Creates the view over `model` and `navigation`, which the caller owns.
    public init(model: TodoListViewModel, navigation: NavigationModel) {
        self.model = model
        self.navigation = navigation
    }
}

#if DEBUG
    #Preview("Items") {
        TodoListView(
            model: TodoListViewModel(
                repository: PreviewTodoRepository(titles: [
                    "Buy milk",
                    "Call the bank",
                    "Water plants",
                ]),
                preferences: PreviewPreferences(),
            ),
            navigation: NavigationModel(),
        )
    }

    #Preview("Empty") {
        TodoListView(
            model: TodoListViewModel(
                repository: PreviewTodoRepository(titles: []),
                preferences: PreviewPreferences(),
            ),
            navigation: NavigationModel(),
        )
    }

    #Preview("Load failed") {
        TodoListView(
            model: TodoListViewModel(
                repository: UnavailableTodoRepository(),
                preferences: PreviewPreferences(),
            ),
            navigation: NavigationModel(),
        )
    }

    #Preview("All done hidden") {
        // PreviewTodoRepository checks off its first item, so one title is all done.
        TodoListView(
            model: TodoListViewModel(
                repository: PreviewTodoRepository(titles: ["Buy milk"]),
                preferences: PreviewPreferences(hideCompleted: true),
            ),
            navigation: NavigationModel(),
        )
    }
#endif
