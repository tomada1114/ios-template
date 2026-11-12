import Foundation

/// How long a UI test waits for the app, in one place for every test file: a wait is
/// always a predicate with one of these timeouts, never a `sleep`.
enum Timeout {
    static let launch: TimeInterval = 20
    static let elementAppears: TimeInterval = 5
    /// How long a failed save waits before it reports, passed to the app as
    /// `-delayFailedUpdates`' value. Longer than every wait between the tap that starts the
    /// save and the check that its failure has not arrived yet: the About sheet appearing
    /// and then settling (one `elementAppears` each), plus one more for the About tap.
    static let failedUpdateDelay: TimeInterval = elementAppears + elementAppears + elementAppears
    /// How long a failure takes to appear under `-delayFailedUpdates`.
    static let delayedFailure: TimeInterval = failedUpdateDelay + elementAppears
    static let keyboardFocus: TimeInterval = 3
    /// How long one check of a condition that is polled alongside another may wait.
    static let poll: TimeInterval = 0.5
}
