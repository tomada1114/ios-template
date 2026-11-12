/// How a failed call is retried: how many times, and how long to wait before each try.
///
/// A plain value held by ``Tuning`` (``Tuning/retry``), so the numbers are tuned in one
/// place and a test hands ``RetryingAPIClient`` a policy whose waits it can write down.
/// The arithmetic lives here, as pure functions of the policy, the attempt, and an
/// injected generator — nothing reads a clock or the system's randomness — so a test
/// asserts the exact wait.
public struct RetryPolicy: Sendable, Equatable {
    /// How many times a call is sent in all, the first attempt included. `1` — or
    /// anything lower — never retries.
    public var maxAttempts: Int

    /// The wait before the first retry, ahead of jitter.
    public var baseDelay: Duration

    /// What each further retry multiplies the previous wait by: `2` doubles it, `1`
    /// keeps it constant. A value that is not a finite number of at least 1 is read
    /// as 1.
    public var multiplier: Double

    /// The fraction of each backoff wait that is random, `0` through `1`: `0` waits the
    /// full backoff every time, `0.5` somewhere in its upper half, `1` anywhere from
    /// nothing up to it. Jitter only ever shortens a wait — so ``maxDelay`` holds — and
    /// spreads out clients that failed at the same moment, which would otherwise retry
    /// at the same moment too. A value outside the range is read as its nearest bound.
    public var jitter: Double

    /// The longest any single wait may be: the ceiling the backoff grows to, and the
    /// longest `Retry-After` that is waited out — a server asking for more is not
    /// retried at all (``delay(honoring:)``).
    public var maxDelay: Duration

    /// ``multiplier`` as the backoff uses it: a finite number of at least 1. Anything
    /// else — `nan`, an infinity, a value below 1 — is read as 1, a constant wait, so a
    /// mistyped policy can slow a retry down but never shrink a wait below zero.
    private var growth: Double {
        multiplier.isFinite ? max(multiplier, 1) : 1
    }

    /// A policy with every value given. The app's own is ``Tuning/default``'s.
    public init(
        maxAttempts: Int,
        baseDelay: Duration,
        multiplier: Double,
        jitter: Double,
        maxDelay: Duration,
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.jitter = jitter
        self.maxDelay = maxDelay
    }

    /// How long to wait after the `attempt`-th send failed (counting from 1) when the
    /// server did not say: ``baseDelay`` multiplied by ``multiplier`` once per earlier
    /// retry, held to ``maxDelay``, then shortened by a random share of ``jitter``.
    ///
    /// Always within zero through ``maxDelay``, whatever the policy holds: a negative
    /// delay is read as zero, and a multiplier too large for a `Duration` stops at the
    /// cap instead of overflowing. The generator is a parameter so a test seeds it; with
    /// no jitter nothing is drawn.
    public func delay(
        afterAttempt attempt: Int,
        using generator: inout some RandomNumberGenerator,
    ) -> Duration {
        let cap = max(maxDelay, .zero)
        var backoff = max(min(baseDelay, cap), .zero)
        let factor = growth
        var failures = 1
        // A wait of zero, or a factor of 1, never changes: there is nothing to repeat.
        while factor > 1, attempt > failures, backoff > .zero, backoff < cap {
            // Compared as a ratio first: multiplying a `Duration` past its range traps.
            backoff = factor >= cap / backoff ? cap : min(backoff * factor, cap)
            failures += 1
        }
        let fraction = min(max(jitter, 0), 1)
        guard fraction > 0 else {
            return backoff
        }
        return backoff * (1 - fraction * Double.random(in: 0 ..< 1, using: &generator))
    }

    /// How long to wait when the server asked for `retryAfter`: exactly that — the
    /// server knows when it will accept the call, and the backoff is only a guess — or
    /// `nil` when it is longer than ``maxDelay``.
    ///
    /// Never a shortened wait: coming back sooner than the server asked would only earn
    /// another refusal, and count against the client. So a `Retry-After` past the cap is
    /// not a wait at all; the caller gives up and reports the 429 or the 503. No jitter,
    /// for the same reason. A negative value is read as zero.
    public func delay(honoring retryAfter: Duration) -> Duration? {
        let wait = max(retryAfter, .zero)
        return wait > max(maxDelay, .zero) ? nil : wait
    }
}
