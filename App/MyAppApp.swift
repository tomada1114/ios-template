import MyAppCore
import MyAppPlatform
import MyAppUI
import SwiftUI

/// Application entry point — wiring only. All real code lives in Packages/MyAppKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It opens the SwiftData store through the `MyAppPlatform` adapter and hands it to a
/// `MyAppCore` view model, so nothing below `App/` — not the view model, not the view —
/// depends on which store answers (`docs/architecture.md` › Layers).
@main
struct MyAppApp: App {
    /// The launch argument `LaunchUITests` passes: an in-memory store, so every UI test
    /// run starts empty and leaves nothing behind on the simulator.
    private static let uiTestingArgument = "-uiTesting"

    /// Owned here, in `@State`, so the model outlives any one scene's view tree.
    @State private var todoList = TodoListViewModel(repository: Self.makeRepository())

    var body: some Scene {
        WindowGroup {
            TodoListView(model: todoList)
        }
    }

    /// The store the app runs on. When the on-disk store cannot be opened, the app still
    /// launches — over a repository that reports every call as failed — rather than
    /// crashing, or quietly keeping edits in memory that would vanish on the next launch.
    private static func makeRepository() -> any TodoRepository {
        let storage: SwiftDataTodoRepository.Storage =
            ProcessInfo.processInfo.arguments.contains(uiTestingArgument) ? .inMemory : .onDisk
        do {
            return try SwiftDataTodoRepository.make(storage: storage)
        } catch {
            return UnavailableTodoRepository()
        }
    }
}
