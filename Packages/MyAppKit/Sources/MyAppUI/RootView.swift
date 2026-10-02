import MyAppCore
import SwiftUI

/// One window's navigation root: the stack every screen is pushed onto, its root screen,
/// the one place a route becomes a screen, and the one place a failure is presented
/// (`failureAlert(_:dismiss:)`).
///
/// The app's only `NavigationStack(path:)` and its only
/// `navigationDestination(for: AppRoute.self)` live here, so a new screen adds an
/// ``AppRoute`` case and a branch of ``destination(for:)`` without touching any other
/// screen. A pushed screen that needs a view model of its own gets it from the
/// ``AppModel``'s `make…ViewModel(…)` factory for its route — Core decides what the model
/// is built over, so this view never needs an adapter (`docs/architecture.md` ›
/// Navigation).
///
/// It owns neither model: `App/` creates the app model once for the app and the
/// navigation model once per scene (both in `@State`), and hands them down. `@Bindable`
/// is only what lets the stack bind to ``NavigationModel/path``, so a row's link, the
/// back button, and a deep link all move the same Core state.
public struct RootView: View {
    private let app: AppModel
    @Bindable private var navigation: NavigationModel

    public var body: some View {
        NavigationStack(path: $navigation.path) {
            TodoListView(model: app.todoList)
                .navigationDestination(for: AppRoute.self) { route in
                    // Identified by its route, so a deep link that swaps one pushed item
                    // for another gets a fresh screen, and a fresh model, rather than
                    // the previous screen's `@State`.
                    destination(for: route).id(route)
                }
        }
        // Outside the stack, so a failure presents over whichever screen is on top: a
        // toggle on the pushed detail screen is the list's, and fails as the list's.
        .failureAlert(app.todoList.failure) { app.todoList.dismissFailure() }
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
