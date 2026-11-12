import MyAppCore
import MyAppPlatform
import MyAppUI
import SwiftUI

/// One window's root: its own navigation over the app's shared models.
///
/// A scene, not the app, owns the `NavigationModel`: the app supports multiple scenes
/// (two windows on iPad), and a path shared between them would move every window in
/// lockstep, and a deep link would move them all instead of the window it arrived in.
/// So does its `SceneLifecycleModel`, whose state lives exactly as long as the window.
private struct SceneRoot: View {
    let app: AppModel
    @State private var navigation = NavigationModel()
    @State private var lifecycle: SceneLifecycleModel
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some View {
        // A `my-app://` link (project.yml registers the scheme) goes to Core, which
        // decides what it opens. So does this window's phase, initial value included:
        // recorded synchronously, so phases apply in order, and only the refresh it may
        // ask for runs in a `Task` — not `.task(id:)`, which the next phase change would
        // cancel mid-refresh.
        RootView(app: app, navigation: navigation)
            .onOpenURL { navigation.open($0) }
            .onChange(of: scenePhase, initial: true) { _, phase in
                lifecycle.sceneDidEnter(Self.lifecyclePhase(phase))
                Task { await lifecycle.refreshIfNeeded() }
            }
    }

    init(app: AppModel) {
        self.app = app
        // A re-render builds a spare model, which `@State` discards: building one has no
        // side effects.
        _lifecycle = State(initialValue: app.makeSceneLifecycleModel())
    }

    /// SwiftUI's phase as Core's. A phase a later SDK adds is `inactive`, the one value
    /// that neither arms nor asks for a refresh.
    private static func lifecyclePhase(_ phase: ScenePhase) -> LifecyclePhase {
        switch phase {
        case .active:
            .active

        case .background:
            .background

        case .inactive:
            .inactive

        @unknown default:
            .inactive
        }
    }
}

/// Application entry point — wiring only. All real code lives in Packages/MyAppKit.
///
/// This is also the composition root: the one place that knows both halves of a port.
/// It opens the SwiftData store and the `UserDefaults` preferences through their
/// `MyAppPlatform` adapters and hands them, as ports, to Core's `AppModel`, which builds
/// every view model over them — so nothing below `App/` depends on which store answers,
/// and `App/` decides nothing but which adapter each port gets; each scene forwards its
/// opened URLs and its scene phase to Core and decides nothing about either
/// (the `designing-core-logic` skill's `references/view-models.md`). It also reads this
/// build's `AppConfiguration` from `Info.plist`, once, and builds the `APIClient` over
/// `URLSessionHTTPClient` at the base URL that configuration names.
@main
struct MyAppApp: App {
    /// The launch argument `LaunchUITests` passes: an in-memory store and a scratch
    /// preferences suite, so every UI test run starts empty and at every setting's
    /// default, and leaves nothing behind that the app's own data would see.
    private static let uiTestingArgument = "-uiTesting"

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    #if DEBUG
        /// Debug-only fault injection: every save that replaces a stored item — a toggle —
        /// fails (`UpdateFailingTodoRepository`), so a failure alert can be seen and
        /// UI-tested. Release builds neither read the argument nor contain the type.
        private static let failUpdatesArgument = "-failUpdates"

        /// With `-failUpdates`, followed by a whole number of seconds: each failure arrives
        /// that long after the save began, so `LaunchUITests` — which passes the value — can
        /// open a sheet over a save still in flight. Missing or malformed, no delay.
        private static let delayFailedUpdatesArgument = "-delayFailedUpdates"
    #endif

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

    /// Builds the client every networked feature's Core service is built over, at every
    /// launch, so a misconfigured build fails there rather than at its first request. No
    /// feature calls an API yet, so nothing keeps it: the first one stores it here and
    /// passes it to `AppModel` as a new initializer parameter. Until then a stored
    /// property nothing reads is dead code `just analyze` (`unused_declaration`) rejects.
    init() {
        _ = Self.makeAPIClient()
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
            let repository = SwiftDataTodoRepository(modelContainer: container)
            #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains(failUpdatesArgument) {
                    return UpdateFailingTodoRepository(
                        wrapping: repository,
                        failureDelay: failedUpdateDelay(in: arguments),
                    )
                }
            #endif
            return repository
        } catch {
            // `makeContainer` has logged the failure; the null object is the handling.
            return UnavailableTodoRepository()
        }
    }

    #if DEBUG
        /// The seconds that follow `-delayFailedUpdates`, or no delay when they are missing
        /// or not a whole number.
        private static func failedUpdateDelay(in arguments: [String]) -> Duration {
            guard let index = arguments.firstIndex(of: delayFailedUpdatesArgument),
                  arguments.indices.contains(index + 1),
                  let seconds = Int(arguments[index + 1])
            else {
                return .zero
            }
            return .seconds(seconds)
        }
    #endif

    /// The API client at this build's base URL (`Config/Debug.xcconfig` or
    /// `Config/Release.xcconfig`). A missing or malformed value is a build
    /// misconfiguration no user can cause or recover from, so the launch stops on it
    /// with the key that is wrong, rather than running against no server.
    private static func makeAPIClient() -> APIClient {
        let configuration: AppConfiguration
        do {
            configuration = try AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
        } catch {
            // The error names the key, never the value: a value is build input, and the
            // key is all a reader needs to find the xcconfig line.
            let key = AppConfiguration.apiBaseURLKey
            AppLog.network.fault(
                "Info.plist \(key, privacy: .public) is unusable: \(String(describing: error), privacy: .public)",
            )
            fatalError("The build's Info.plist has no usable API base URL: \(error)")
        }
        return APIClient(httpClient: URLSessionHTTPClient(), baseURL: configuration.apiBaseURL)
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
