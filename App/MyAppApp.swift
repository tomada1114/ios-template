import MyAppCore
import MyAppPlatform
import MyAppUI
import SwiftUI

/// One window's root: its own navigation over the app's shared to-do list.
///
/// A scene, not the app, owns the `NavigationModel`: the app supports multiple scenes
/// (two windows on iPad), and a path shared between them would move every window in
/// lockstep, and a deep link would move them all instead of the window it arrived in.
private struct SceneRoot: View {
    let todoList: TodoListViewModel
    @State private var navigation = NavigationModel()

    var body: some View {
        // A `my-app://` link (project.yml registers the scheme) goes to Core, which
        // decides what it opens.
        TodoListView(model: todoList, navigation: navigation)
            .onOpenURL { navigation.open($0) }
    }
}

/// Application entry point — wiring only. All real code lives in Packages/MyAppKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It opens the SwiftData store and the `UserDefaults` preferences through their
/// `MyAppPlatform` adapters and hands them to a `MyAppCore` view model, so nothing below
/// `App/` — not the view model, not the view — depends on which store answers
/// (`docs/architecture.md` › Layers).
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
    @State private var todoList = TodoListViewModel(
        repository: Self.makeRepository(),
        preferences: Self.makePreferences(),
    )

    var body: some Scene {
        WindowGroup {
            SceneRoot(todoList: todoList)
        }
    }

    /// The store the app runs on. When the on-disk store cannot be opened, the app still
    /// launches — over a repository that reports every call as failed — rather than
    /// crashing, or quietly keeping edits in memory that would vanish on the next launch.
    private static func makeRepository() -> any TodoRepository {
        let storage: SwiftDataTodoRepository.Storage = isUITesting ? .inMemory : .onDisk
        do {
            return try SwiftDataTodoRepository.make(storage: storage)
        } catch {
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
