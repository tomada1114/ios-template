import os

/// This app's unified-log entry point: one subsystem, one `Logger` per concern.
///
/// `MyAppCore` is allowed to `import os`: it is Apple's logging facility, not a UI or
/// OS-integration framework, and it works unchanged on every platform Core serves, so a
/// logging port would buy nothing and cost every call site an injection
/// (`docs/architecture.md` › Logging). `MyAppUI`, `MyAppPlatform`, and `App/` log through
/// these same loggers, which they already see by importing `MyAppCore`.
///
/// Never `print`, `debugPrint`, or `NSLog` under `Sources/` or `App/`: an app launched
/// from the Home Screen has nowhere to send stdout, so those lines vanish exactly when
/// they would matter. `.swiftlint.yml`'s `no_print_in_sources` rejects them. Anything
/// user-derived that reaches a log message is interpolated `.private` — a to-do's title
/// is the user's data; its identifier and a count are not.
public enum AppLog {
    /// The subsystem every logger below is created with: this app's bundle identifier,
    /// and the value `just logs` filters the stream on.
    ///
    /// A literal rather than `Bundle.main.bundleIdentifier`, which answers for the test
    /// runner under `swift test` and for the preview agent in an Xcode preview. It must
    /// equal `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
    public static let subsystem = "com.example.MyApp"

    /// The to-do list concern: ``TodoListViewModel`` and what it asks of the repository.
    ///
    /// One category per concern, named for the concern rather than for a type, so
    /// `log stream --predicate 'category == "todos"'` narrows the stream to one story.
    /// A new concern adds a `Logger` here instead of building one inline.
    public static let todos = Logger(subsystem: subsystem, category: "todos")

    /// The persistence concern: opening the store and the adapters that read and write it.
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// The networking concern: the ``HTTPClient`` adapter's failed requests. A request's
    /// method and host are `.public`; its path, query, and the framework's error text are
    /// `.private`, since a URL can carry user data.
    public static let network = Logger(subsystem: subsystem, category: "network")
}
