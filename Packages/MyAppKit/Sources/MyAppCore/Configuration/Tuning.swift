/// Every number someone might tune, in one place: a test reaches a boundary by handing a
/// type its own `Tuning`, and a product tweak is one edit here rather than a hunt for a
/// literal in a method body (`.claude/rules/core.md` › One `Tuning` type).
///
/// A type that needs a tunable takes a `Tuning` in its initializer, defaulting to
/// ``default`` — ``RetryingAPIClient`` is the worked example. A domain invariant is not
/// a tunable and does not belong here.
public struct Tuning: Sendable, Equatable {
    /// The values the shipped app runs with.
    public static let `default` = Self(
        retry: RetryPolicy(
            maxAttempts: defaultRetryAttempts,
            baseDelay: .milliseconds(defaultRetryBaseMilliseconds),
            multiplier: defaultRetryMultiplier,
            jitter: defaultRetryJitter,
            maxDelay: .seconds(defaultRetryMaxSeconds),
        ),
    )

    /// Three sends in all: a transient failure usually clears by the second, the third
    /// covers a blip that outlasts one wait, and past that the server is down rather
    /// than flickering — the person is better served by an error they can act on.
    private static let defaultRetryAttempts = 3

    /// Half a second: long enough for a dropped connection or a restarting server to
    /// come back, short enough that one retry does not read as a hang.
    private static let defaultRetryBaseMilliseconds = 500

    /// Doubling, the usual exponential backoff: each failure is evidence the server
    /// needs longer than the last wait gave it.
    private static let defaultRetryMultiplier = 2.0

    /// Up to half of each wait is shaved off at random, so clients that failed together
    /// do not all come back together, while the server still gets at least half the
    /// backoff to recover in.
    private static let defaultRetryJitter = 0.5

    /// Thirty seconds bounds what a `Retry-After` can make a call wait. A server asking
    /// for longer is telling the feature to show a "try again later" state, not to hold
    /// a spinner.
    private static let defaultRetryMaxSeconds = 30

    /// How ``RetryingAPIClient`` retries a failed call.
    public var retry: RetryPolicy

    /// A tuning with every value given — what a test builds to reach a boundary.
    public init(retry: RetryPolicy) {
        self.retry = retry
    }
}
