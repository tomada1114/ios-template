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

/// The to-do list screen, with a quick-add bar pinned to the bottom: the root screen of
/// `RootView`'s navigation stack, which a row's link pushes onto.
///
/// Deliberately thin — every behavior it renders is owned and unit-tested by
/// `TodoListViewModel` in MyAppCore, and so is every word: the view has no localizable
/// literal of its own. It turns each user intent into one view-model call and reads
/// back the state to draw.
///
/// It does not own its model: `App/` creates it once for the app, inside `AppModel`, and
/// `RootView` hands it down. `@Bindable` is only what lets the text field bind to
/// ``TodoListViewModel/draftTitle``.
///
/// It presents no alert of its own: a ``TodoListViewModel/failure`` presents from
/// `RootView`, over whichever screen is on top, in the window whose action caused it —
/// which is why every action that can fail is passed `scene`.
public struct TodoListView: View {
    @Bindable private var model: TodoListViewModel
    /// The window this list is in, or `nil` in a preview, which has none.
    private let scene: SceneID?
    @FocusState private var isDraftFocused: Bool
    /// What the About button does: `RootView` presents the About sheet through its
    /// navigation model, which this view never holds.
    private let showAbout: () -> Void

    public var body: some View {
        list
            .overlay { placeholder }
            .navigationTitle(Text(TodoListStrings.title))
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { addBar }
            .refreshable { await model.load(from: scene) }
            .task {
                // Only the first appearance loads; a return to this screen keeps what
                // is shown. Pull-to-refresh reloads, and so does Core when a window
                // returns to the foreground (`SceneLifecycleModel`).
                if model.phase == .idle {
                    await model.load(from: scene)
                }
            }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // `.primaryAction` rather than an iOS-only placement: MyAppUI also compiles for
        // macOS.
        // One group, so the two trailing items keep this order rather than whatever
        // order SwiftUI merges separately declared items in.
        ToolbarItemGroup(placement: .primaryAction) {
            hideCompletedToggle
            aboutButton
        }
        #if os(iOS)
            // The non-gesture way to delete: Edit mode shows a delete control on every
            // row and reuses `.onDelete`, so a swipe is never the only way. The system
            // button localizes its own title and takes the toolbar's hit target, like
            // the toggle beside it. `EditButton` is iOS-only.
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .accessibilityIdentifier("editButton")
            }
        #endif
    }

    private var list: some View {
        List {
            ForEach(model.visibleItems) { item in
                TodoRow(item: item, toggleLabel: model.toggleLabel(for: item)) {
                    Task { await model.toggle(item.id, from: scene) }
                }
            }
            // The offsets index `visibleItems`, which is what the view model resolves them
            // against.
            .onDelete { offsets in
                Task { await model.delete(atOffsets: offsets, from: scene) }
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
                    Task { await model.load(from: scene) }
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

    /// The button that presents the About sheet. The toolbar shows the glyph alone; the
    /// title is what VoiceOver reads.
    private var aboutButton: some View {
        Button(action: showAbout) {
            Label {
                Text(AboutStrings.show)
            } icon: {
                Image(systemName: "info.circle")
            }
        }
        .accessibilityIdentifier("aboutButton")
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
            .onSubmit { Task { await model.addDraft(from: scene) } }
            .accessibilityIdentifier("newItemField")

            Button(TodoListStrings.add) {
                Task { await model.addDraft(from: scene) }
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

    /// Creates the view over `model`, which the caller owns, in the window `scene` names,
    /// calling `showAbout` when the About button is tapped. The caller also provides the
    /// navigation stack a row's link pushes onto (`RootView`).
    public init(model: TodoListViewModel, scene: SceneID?, showAbout: @escaping () -> Void) {
        self.model = model
        self.scene = scene
        self.showAbout = showAbout
    }
}

#if DEBUG
    /// The list over `repository` and `preferences`, inside a plain stack for its title
    /// and toolbar — the stack `RootView` gives it in the app.
    @MainActor
    private func listPreview(
        over repository: any TodoRepository,
        preferences: PreviewPreferences,
    ) -> some View {
        NavigationStack {
            TodoListView(
                model: AppModel(repository: repository, preferences: preferences).todoList,
                scene: nil,
            ) {
                // Nothing to present: a preview has no navigation model.
            }
        }
    }

    #Preview("Items") {
        listPreview(
            over: PreviewTodoRepository(titles: [
                "Buy milk",
                "Call the bank",
                "Water plants",
            ]),
            preferences: PreviewPreferences(),
        )
    }

    #Preview("Empty") {
        listPreview(over: PreviewTodoRepository(titles: []), preferences: PreviewPreferences())
    }

    #Preview("Load failed") {
        listPreview(over: UnavailableTodoRepository(), preferences: PreviewPreferences())
    }

    #Preview("All done hidden") {
        // PreviewTodoRepository checks off its first item, so one title is all done.
        listPreview(
            over: PreviewTodoRepository(titles: ["Buy milk"]),
            preferences: PreviewPreferences(hideCompleted: true),
        )
    }
#endif
