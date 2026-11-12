import MyAppCore
import SwiftUI

/// One window's navigation root: the stack every screen is pushed onto, its root screen,
/// the one place a route becomes a screen, the one place a sheet is presented, and the
/// one place a failure is presented (`failureAlert(_:dismiss:)`) — over the top screen,
/// or over the sheet while one is up.
///
/// The app's only `NavigationStack(path:)`, its only
/// `navigationDestination(for: AppRoute.self)`, and its only `.sheet(item:)` live here, so
/// a new screen adds an ``AppRoute`` case and a branch of ``destination(for:)``, and a new
/// sheet an ``AppSheet`` case and a branch of ``sheet(for:)``, without touching any other
/// screen. A pushed screen that needs a view model of its own gets it from the
/// ``AppModel``'s `make…ViewModel(…)` factory for its route — Core decides what the model
/// is built over, so this view never needs an adapter (`designing-ui`'s
/// `references/navigation.md`).
///
/// It owns neither model: `App/` creates the app model once for the app and the
/// navigation model once per scene (both in `@State`), and hands them down. `@Bindable`
/// is only what lets the stack bind to ``NavigationModel/path``, so a row's link, the
/// back button, and a deep link all move the same Core state. The sheet binds through
/// ``NavigationModel/dismissSheet(_:)`` instead, since ``NavigationModel/sheet`` is
/// read-only.
public struct RootView: View {
    private let app: AppModel
    @Bindable private var navigation: NavigationModel

    public var body: some View {
        NavigationStack(path: $navigation.path) {
            TodoListView(model: app.todoList) { navigation.present(.about) }
                .navigationDestination(for: AppRoute.self) { route in
                    // Identified by its route, so a deep link that swaps one pushed item
                    // for another gets a fresh screen, and a fresh model, rather than
                    // the previous screen's `@State`.
                    destination(for: route).id(route)
                }
        }
        // Outside the stack, like the alert below, so it presents whichever screen is on
        // top.
        .sheet(item: presentedSheet) { sheet in
            // SwiftUI presents nothing from a view already presenting a sheet, so while
            // one is up the failure presents from the sheet's content instead (#124).
            self.sheet(for: sheet)
                .failureAlert(app.todoList.failure) { app.todoList.dismissFailure() }
        }
        // Outside the stack, so a failure presents over whichever screen is on top: a
        // toggle on the pushed detail screen is the list's, and fails as the list's.
        // Withheld while a sheet is up, so one failure is never bound to two alerts.
        .failureAlert(navigation.sheet == nil ? app.todoList.failure : nil) {
            app.todoList.dismissFailure()
        }
    }

    /// ``NavigationModel/sheet``, written back only through its action. SwiftUI writes
    /// `nil` to dismiss (a swipe down); presenting stays ``NavigationModel/present(_:)``'s,
    /// so any other write is ignored. The binding is rebuilt on every render and names the
    /// sheet that was up when it was built, so a write-back from an earlier presentation
    /// reaches ``NavigationModel/dismissSheet(_:)`` naming the old sheet and leaves a newer
    /// one up.
    private var presentedSheet: Binding<AppSheet?> {
        let shown = navigation.sheet
        return Binding(
            get: { navigation.sheet },
            set: { newValue in
                if newValue == nil, let shown {
                    navigation.dismissSheet(shown)
                }
            },
        )
    }

    /// Creates the root over `app` and `navigation`, which the caller owns.
    public init(app: AppModel, navigation: NavigationModel) {
        self.app = app
        self.navigation = navigation
    }

    /// The screen `route` names. A model built here is handed to a screen that keeps the
    /// first one it gets for as long as it is pushed (`TodoDetailView`'s `@State`), so the
    /// fresh model a later re-render builds is discarded unused — which is why a view
    /// model's construction has no side effects.
    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .todoDetail(id):
            TodoDetailView(model: app.makeTodoDetailViewModel(id: id))
        }
    }

    /// The sheet `sheet` names. A sheet that needs a view model gets it from an
    /// ``AppModel`` factory here, as a pushed screen does in ``destination(for:)``.
    @ViewBuilder
    private func sheet(for sheet: AppSheet) -> some View {
        switch sheet {
        case .about:
            AboutView { navigation.dismissSheet(sheet) }
        }
    }
}

#if DEBUG
    #Preview("Items") {
        RootView(
            app: AppModel(
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
#endif
