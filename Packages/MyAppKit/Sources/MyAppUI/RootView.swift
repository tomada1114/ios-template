import MyAppCore
import SwiftUI

/// One window's navigation root: the stack every screen is pushed onto, its root screen,
/// the one place a route becomes a screen, the one place a sheet is presented, and the
/// one place a failure is presented (``failureAlerts(on:isTopmost:)``) — over the top
/// screen, or over the sheet while one is on screen, and only in the one window Core
/// picks for it.
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
/// It owns none of its models: `App/` creates the app model once for the app, and the
/// navigation model and the lifecycle model once per scene (all in `@State`), and hands
/// them down. The lifecycle model is the window's identity here: its ``SceneLifecycleModel/id``
/// goes with every action that can fail, and it says whether this window presents a
/// failure. `@Bindable`
/// is only what lets the stack bind to ``NavigationModel/path``, so a row's link, the
/// back button, and a deep link all move the same Core state. The sheet binds through
/// ``NavigationModel/dismissSheet(_:)`` instead, since ``NavigationModel/sheet`` is
/// read-only.
public struct RootView: View {
    private let app: AppModel
    @Bindable private var navigation: NavigationModel
    private let lifecycle: SceneLifecycleModel

    public var body: some View {
        failureAlerts(on: stackAndSheet, isTopmost: !navigation.isSheetOnScreen)
            // Whichever model's failure it is: an alert taken down by code, with no button
            // tapped, strands a link that was waiting for its answer, and Core drops it.
            .onChange(of: lifecycle.presentsFailure) {
                navigation.failureAlertsDidChange()
            }
    }

    private var stackAndSheet: some View {
        NavigationStack(path: $navigation.path) {
            TodoListView(model: app.todoList, scene: lifecycle.id) { navigation.present(.about) }
                .navigationDestination(for: AppRoute.self) { route in
                    // Identified by its route, so a deep link that swaps one pushed item
                    // for another gets a fresh screen, and a fresh model, rather than
                    // the previous screen's `@State`.
                    destination(for: route).id(route)
                }
        }
        // Outside the stack, like the failure alerts, so it presents whichever screen is
        // on top. Core is told when a sheet starts presenting and when it has finished
        // leaving (`onDismiss`, after its slide-out): what is on screen, which
        // `NavigationModel.sheet` alone does not say, decides which layer gets the
        // failures and when a link may move the stack.
        .sheet(item: presentedSheet, onDismiss: navigation.sheetDidLeave) { sheet in
            failureAlerts(on: self.sheet(for: sheet), isTopmost: true)
        }
        .onChange(of: navigation.sheet != nil, initial: true) { _, isAskedFor in
            if isAskedFor {
                navigation.sheetDidStartPresenting()
            }
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

    /// Creates the root over `app`, and over this window's `navigation` and `lifecycle`,
    /// all of which the caller owns.
    public init(app: AppModel, navigation: NavigationModel, lifecycle: SceneLifecycleModel) {
        self.app = app
        self.navigation = navigation
        self.lifecycle = lifecycle
    }

    /// Every feature's failure alert, attached to one presentation layer: the stack, or
    /// the sheet over it. SwiftUI presents nothing from a view that is already presenting
    /// a sheet (#124), so only the topmost layer is handed the failures, and one failure is
    /// never bound to two alerts. Outside the stack, so a failure presents over whichever
    /// screen is pushed: a toggle on the detail screen is the list's, and fails as the
    /// list's (#78). A new feature adds its `.failureAlert` here, once.
    ///
    /// The list is shared by every window, so its failure is read through this window's
    /// lifecycle model: Core hands it to exactly one window, and the button dismisses the
    /// failure it was shown for, so only that window's button can (#133). The button then
    /// tells the navigation model the alert was answered, which is when a link that
    /// arrived under it may move the stack (#140): UIKit has taken an alert down by the
    /// time it runs a button's action, and SwiftUI reports no later moment. Whether the
    /// window presents a failure at all, the navigation model asks Core
    /// (`SceneLifecycleModel.presentsFailure`), not this list, so an alert added here is
    /// waited on without a second line anywhere.
    private func failureAlerts(on layer: some View, isTopmost: Bool) -> some View {
        let shown = isTopmost ? lifecycle.presented(app.todoList.reportedFailure) : nil
        return layer.failureAlert(shown?.failure) {
            app.todoList.dismissFailure(shown)
            navigation.failureAlertDidLeave()
        }
    }

    /// The screen `route` names. A model built here is handed to a screen that keeps the
    /// first one it gets for as long as it is pushed (`TodoDetailView`'s `@State`), so the
    /// fresh model a later re-render builds is discarded unused — which is why a view
    /// model's construction has no side effects.
    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .todoDetail(id):
            TodoDetailView(model: app.makeTodoDetailViewModel(id: id, scene: lifecycle.id))
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
        let app = AppModel(
            repository: PreviewTodoRepository(titles: [
                "Buy milk",
                "Call the bank",
                "Water plants",
            ]),
            preferences: PreviewPreferences(),
        )
        RootView(
            app: app,
            navigation: NavigationModel(),
            lifecycle: app.makeSceneLifecycleModel(),
        )
    }
#endif
