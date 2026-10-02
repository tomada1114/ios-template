import MyAppCore
import MyAppPlatform
import MyAppUI
import SwiftUI

/// One window's root: its own navigation over the app's shared models.
///
/// A scene, not the app, owns the `NavigationModel`: the app supports multiple scenes
/// (two windows on iPad), and a path shared between them would move every window in
/// lockstep, and a deep link would move them all instead of the window it arrived in.
private struct SceneRoot: View {
    let app: AppModel
    @State private var navigation = NavigationModel()

    var body: some View {
        // A `my-app://` link (project.yml registers the scheme) goes to Core, which
        // decides what it opens.
        RootView(app: app, navigation: navigation)
            .onOpenURL { navigation.open($0) }
    }
}

/// Application entry point — wiring only. All real code lives in Packages/MyAppKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It opens the SwiftData store and the `UserDefaults` preferences through their
/// `MyAppPlatform` adapters and hands them, as ports, to Core's `AppModel`, which builds
/// every view model over them — so nothing below `App/` depends on which store answers,
/// and `App/` decides nothing but which adapter each port gets
/// (`docs/architecture.md` › Composition root).
@main
struct MyAppApp: App {
    /// The launch argument `LaunchUITests` passes: an in-memory store and a scratch
    /// preferences suite, so every UI test run starts empty and at every setting's
    /// default, and leaves nothing behind that the app's own data would see.
    private static let uiTestingArgument = "-uiTesting"

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    /// Owned here, in `@State`, so the model outlives any one scene's view tree and every
    /// window shows the same items. Navigation is per window (`SceneRoot`).
    @State private var app = AppModel(
        repository: Self.makeRepository(),
        preferences: Self.makePreferences(),
    )

    var body: some Scene {
        WindowGroup {
            SceneRoot(app: app)
        }
    }

    /// The store the app runs on, opened once: every SwiftData repository is built over
    /// this one container (a second one joins `SwiftDataTodoRepository` here, over the
    /// same `container`), never over a container of its own. When the on-disk store
    /// cannot be opened, the app still launches — over a repository that reports every
    /// call as failed — rather than crashing, or quietly keeping edits in memory that
    /// would vanish on the next launch.
    private static func makeRepository() -> any TodoRepository {
        let storage: PersistenceStore.Storage = isUITesting ? .inMemory : .onDisk
        do {
            let container = try PersistenceStore.makeContainer(storage: storage)
            return SwiftDataTodoRepository(modelContainer: container)
        } catch {
            // `makeContainer` has logged the failure; the null object is the handling.
            return UnavailableTodoRepository()
        }
    }

    /// The preferences the app runs on: the standard defaults, or — under UI testing — a
    /// suite of its own, cleared at launch. `just uitest` reuses the simulator, so without
    /// the scratch suite one run's Hide Completed would still be on in the next.
    private static func makePreferences() -> any PreferencesStoring {
        if isUITesting {
            return UserDefaultsPreferences.scratch(suiteName: "\(AppLog.subsystem).uiTesting")
        }
        return UserDefaultsPreferences()
    }
}
