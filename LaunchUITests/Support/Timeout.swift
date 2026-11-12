import Foundation

/// How long a UI test waits for the app, in one place for every test file: a wait is
/// always a predicate with one of these timeouts, never a `sleep`.
enum Timeout {
    static let launch: TimeInterval = 20
    static let elementAppears: TimeInterval = 5
    /// The app's delay before a failed save reports under `-delayFailedUpdates`
    /// (`App/MyAppApp.swift`'s `failedUpdateDelaySeconds`).
    static let failedUpdateDelay: TimeInterval = 8
    /// How long a failure takes to appear under `-delayFailedUpdates`.
    static let delayedFailure: TimeInterval = failedUpdateDelay + elementAppears
    static let keyboardFocus: TimeInterval = 3
    /// How long one check of a condition that is polled alongside another may wait.
    static let poll: TimeInterval = 0.5
}
