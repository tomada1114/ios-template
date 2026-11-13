import MyAppCore
import MyAppPlatform
import MyAppUI
import SwiftUI

/// Keeps one window's navigation path across launches: `@SceneStorage` holds the model's
/// encoded path per scene, and the model takes it back when the scene is rebuilt, so a
/// window the system ended in the background reopens on the screen it showed. It only
/// carries the bytes: what a stored path restores to is Core's
/// (`NavigationModel.restore(from:)`).
private struct PathRestoration: ViewModifier {
    let navigation: NavigationModel
    /// The window's path as `NavigationModel.encodedPath` wrote it; empty until the
    /// window first stores one. The key names a value the system stores per scene: under
    /// a new key, each window opens at the root once.
    @SceneStorage("navigation.path")
    private var storedPath = Data()

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Core applies the stored path once, and only while nothing has moved the
                // path, so a link that opened the window wins whichever arrives first.
                // Without animation: the window opens on the restored screen, rather
                // than on the list with that screen sliding in over it.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    navigation.restore(from: storedPath)
                }
                // Whatever the restore made of the stored bytes is what is stored now, so
                // bytes that restored nothing or only in part are gone: the next launch,
                // and a later build that could read them, find the path the person saw.
                storedPath = navigation.encodedPath
            }
            // On change only, never initially: the first value is the empty path, which
            // would overwrite the stored one before it is restored.
            .onChange(of: navigation.path) {
                storedPath = navigation.encodedPath
            }
    }
}

/// One window's root: its own navigation over the app's shared models.
///
/// A scene, not the app, owns the `NavigationModel`: the app supports multiple scenes
/// (two windows on iPad), and a path shared between them would move every window in
/// lockstep, and a deep link would move them all instead of the window it arrived in.
/// So does its `SceneLifecycleModel`, whose state lives exactly as long as the window.
///
/// The path outlives the window's process (`PathRestoration`).
private struct SceneRoot: View {
    let app: AppModel
    /// Whether `LaunchUITests` launched the app. The window then neither stores nor
    /// restores its path — each launch must start at the root whatever the last one left
    /// pushed — and, in a Debug build, marks a link its navigation model holds back, which
    /// nothing on screen shows (`WaitingLinkMarker`).
    let isUITesting: Bool
    @State private var navigation: NavigationModel
    @State private var lifecycle: SceneLifecycleModel
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some View {
        // A `my-app://` link (project.yml registers the scheme) goes to Core, which
        // decides what it opens. So does this window's phase, initial value included:
        // recorded synchronously, so phases apply in order, and only the refresh it may
        // ask for runs in a `Task` — not `.task(id:)`, which the next phase change would
        // cancel mid-refresh.
        root
            .onOpenURL { navigation.open($0) }
            .onChange(of: scenePhase, initial: true) { _, phase in
                lifecycle.sceneDidEnter(Self.lifecyclePhase(phase))
                Task { await lifecycle.refreshIfNeeded() }
            }
            // The window is gone: Core hands a failure it was presenting to another one.
            .onDisappear { lifecycle.sceneDidClose() }
    }

    /// The root view: with path restoration, or under UI testing without it and with the
    /// waiting-link marker. The one place the opt-out is read: without the modifier
    /// nothing is stored, read, or encoded. `isUITesting` never changes while the process
    /// lives, so the branch never flips.
    @ViewBuilder private var root: some View {
        let rootView = RootView(app: app, navigation: navigation, lifecycle: lifecycle)
        if isUITesting {
            #if DEBUG
                rootView.modifier(WaitingLinkMarker(navigation: navigation))
            #else
                rootView
            #endif
        } else {
            rootView.modifier(PathRestoration(navigation: navigation))
        }
    }

    init(app: AppModel, isUITesting: Bool) {
        self.app = app
        self.isUITesting = isUITesting
        // A re-render builds a spare pair of models, which `@State` discards: building
        // one has no side effects. The navigation model is built over this window's
        // lifecycle model, whose failure alerts a link waits on.
        let sceneLifecycle = app.makeSceneLifecycleModel()
        _lifecycle = State(initialValue: sceneLifecycle)
        _navigation = State(initialValue: app.makeNavigationModel(for: sceneLifecycle))
    }

    /// SwiftUI's phase as Core's. A phase a later SDK adds is `background`: nothing says
    /// the window is on screen in it, so it must not be the window a failure is presented
    /// in. The price is one quiet refresh at the window's next active.
    private static func lifecyclePhase(_ phase: ScenePhase) -> LifecyclePhase {
        switch phase {
        case .active:
            .active

        case .background:
            .background

        case .inactive:
            .inactive

        @unknown default:
            .background
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
/// opened URLs, its scene phase, and its stored navigation path to Core and decides
/// nothing about any of them
/// (the `designing-core-logic` skill's `references/view-models.md`). It also reads this
/// build's `AppConfiguration` from `Info.plist`, once, and builds the `APIClient` over
/// `URLSessionHTTPClient` at the base URL that configuration names.
@main
struct MyAppApp: App {
    /// The launch argument `LaunchUITests` passes: an in-memory store, a scratch
    /// preferences suite, and no stored navigation path, so every UI test run starts
    /// empty, at the root, and at every setting's default, and leaves nothing behind that
    /// the app's own data would see.
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
            SceneRoot(app: app, isUITesting: Self.isUITesting)
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
