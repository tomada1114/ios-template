import notify

/// The failed saves the failure launch holds: `-holdFailedUpdates` names
/// ``releaseNotification``, and the app holds each failing save until the test posts it
/// (`App/MyAppApp.swift`, `FailedUpdateGate`). So a failure arrives when the test says,
/// after it has seen the screen the failure should land on, whatever the taps before
/// it took — a fixed delay held only while they took less than the delay (#141).
enum HeldFailure {
    /// The Darwin notification the test posts and the app observes; any name works, since
    /// the test passes it to the app at launch.
    static let releaseNotification = "LaunchUITests.releaseFailedUpdate"

    /// Lets the next held failure through: the one already held, or, when the save has
    /// not reached the gate yet, the next one to arrive. One call per failure, after the
    /// tap that starts its save: the system may merge two posts that come close together
    /// into one delivery.
    static func release() {
        notify_post(releaseNotification)
    }
}
