import Foundation

/// How long a UI test waits for the app, in one place for every test file: a wait is
/// always a predicate with one of these timeouts, never a `sleep`.
enum Timeout {
    static let launch: TimeInterval = 20
    static let elementAppears: TimeInterval = 5
    /// How long a held failure takes to appear once the test releases it
    /// (`HeldFailure.release()`): the notification's trip to the app, the app's answer,
    /// and the alert's presentation. Four `elementAppears`, because on a loaded
    /// simulator one look at the screen has taken 4–11 s (#141), and a wait that passes
    /// costs only as long as the alert takes.
    static let releasedFailureAppears: TimeInterval =
        elementAppears + elementAppears + elementAppears + elementAppears
    static let keyboardFocus: TimeInterval = 3
    /// How long the keyboard may take to present once a field holds focus. As long as a
    /// launch, because on a cold-booted simulator its first presentation is one: the
    /// keyboard is a process of its own.
    static let keyboardPresents: TimeInterval = launch
    /// How long one check of a condition that is polled alongside another may wait.
    static let poll: TimeInterval = 0.5
}
