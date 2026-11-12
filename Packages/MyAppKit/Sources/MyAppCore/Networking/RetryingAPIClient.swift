import os

/// An ``APIClient`` that tries a failed call again: the Core service a feature sends
/// through when a transient failure should not reach the person.
///
/// A wrapper over ``APIClient``, not a decorator over the ``HTTPClient`` port, because
/// every fact a retry is decided on already exists one level up, in Core's vocabulary:
/// ``APIError`` has sorted the failure into "worth another try" and "will fail again",
/// it carries the `Retry-After` wait already parsed, and the ``Endpoint`` says whether
/// the call may be repeated. A decorator would re-read status codes and headers the
/// client reads anyway, and need a retry flag on ``HTTPRequest``, which describes only
/// what the server receives.
///
/// - **What is retried:** ``APIError/timedOut``, ``APIError/offline``,
///   ``APIError/rateLimited(retryAfter:)``, and ``APIError/server(status:)`` for a 500,
///   502, 503, or 504 — failures that describe the moment, not the request. Every other
///   case would fail the same way again and is thrown at once; that includes a 501, a
///   505, and every other 5xx, which say the server will not do this, not that it
///   cannot right now.
/// - **How long it waits:** exactly a 429's `Retry-After`, when the server sent one;
///   otherwise the policy's jittered exponential backoff. A `Retry-After` longer than
///   ``RetryPolicy/maxDelay`` is not shortened to fit — coming back early would only be
///   refused again — so that 429 is thrown at once, for the feature to show.
/// - **What is never repeated:** a call whose method is not idempotent
///   (``HTTPRequest/Method/isIdempotent``), unless its endpoint opts in with
///   ``Endpoint/isSafeToRepeat``. A timed-out `POST` may have reached the server; sending
///   it again could create the thing twice.
/// - **What a repeat can answer:** an idempotent call is safe to send twice, but its
///   second answer need not match the first. When a `DELETE` or a `PUT` reached the
///   server and only its response was lost, the retry meets the state the first attempt
///   left: a repeated `DELETE` can answer 404 (``APIError/notFound``), and a repeated
///   conditional or create-style `PUT` a 409 or 412 (``APIError/unexpectedStatus(_:)``).
///   Neither is retried, so the feature sees it — and must treat a 404 from a `DELETE`
///   as done, not as a failure.
/// - **Cancellation** ends the call at once with ``APIError/cancelled``, mid-wait
///   included, and is never retried.
///
/// It waits on an injected `Clock` and draws jitter from an injected generator, so
/// `RetryPolicyTests` cover every wait without one passing — the worked example of
/// both (`.claude/rules/core.md` › Inject what Core would read from the world). An
/// actor because the generator is state that concurrent calls draw from; calls still
/// run concurrently, since each suspends while it sends and while it waits.
public actor RetryingAPIClient {
    private static let internalServerError = 500
    private static let badGateway = 502
    private static let serviceUnavailable = 503
    private static let gatewayTimeout = 504

    /// The 5xx statuses that describe the server's moment rather than the request. Any
    /// other 5xx — a 501, a 505 — says the server will not do this at all.
    private static let transientServerStatuses: Set<Int> = [
        internalServerError, badGateway, serviceUnavailable, gatewayTimeout,
    ]

    private let client: APIClient
    private let policy: RetryPolicy
    private let clock: any Clock<Duration>
    private var generator: any RandomNumberGenerator & Sendable

    /// A retrying client over `client`.
    ///
    /// - Parameters:
    ///   - client: The client each attempt is sent through.
    ///   - tuning: Whose ``Tuning/retry`` decides the attempts and the waits.
    ///   - clock: What a wait sleeps on. Injected so a test advances it by hand instead
    ///     of waiting.
    ///   - generator: Where jitter is drawn from. Injected so a test seeds it.
    public init(
        client: APIClient,
        tuning: Tuning = .default,
        clock: any Clock<Duration> = ContinuousClock(),
        generator: some RandomNumberGenerator & Sendable = SystemRandomNumberGenerator(),
    ) {
        self.client = client
        policy = tuning.retry
        self.clock = clock
        self.generator = generator
    }

    /// Sends `endpoint` as ``APIClient/send(_:)`` does, trying again — after a wait —
    /// while the failure is one a retry can fix and the policy has attempts left.
    ///
    /// Throws the last attempt's ``APIError``, or ``APIError/cancelled`` as soon as the
    /// calling task is cancelled. The error can be the answer to a repeat rather than to
    /// the first attempt: a retried `DELETE` whose first response was lost throws
    /// ``APIError/notFound`` although the resource is gone as asked.
    public func send<Response>(
        _ endpoint: Endpoint<Response>,
    ) async throws(APIError) -> Response {
        let isRepeatable = endpoint.method.isIdempotent || endpoint.isSafeToRepeat
        var attempt = 1
        while true {
            if Task.isCancelled {
                throw .cancelled
            }
            do {
                return try await client.send(endpoint)
            } catch {
                guard isRepeatable,
                      let delay = delayBeforeRetry(after: error, attempt: attempt)
                else {
                    throw error
                }
                logRetry(after: error, attempt: attempt, delay: delay)
                try await wait(for: delay)
            }
            attempt += 1
        }
    }

    /// How long to wait before sending again after `error` ended the `attempt`-th send,
    /// or `nil` when the call should not be sent again.
    private func delayBeforeRetry(after error: APIError, attempt: Int) -> Duration? {
        guard attempt < policy.maxAttempts else {
            return nil
        }
        switch error {
        case .offline, .timedOut:
            return policy.delay(afterAttempt: attempt, using: &generator)

        case let .server(status):
            // Only a status that describes the moment. A 501 or a 505 says the server
            // will never do this, so asking again only delays the error.
            guard Self.transientServerStatuses.contains(status) else {
                return nil
            }
            return policy.delay(afterAttempt: attempt, using: &generator)

        case let .rateLimited(retryAfter):
            guard let retryAfter else {
                return policy.delay(afterAttempt: attempt, using: &generator)
            }
            // `nil` when the server asked for longer than the policy waits: the 429 is
            // thrown rather than retried early.
            return policy.delay(honoring: retryAfter)

        case .cancelled:
            // The caller gave up: there is nobody to retry for.
            return nil

        case .decoding, .encoding, .transport:
            // A fault in the request, the schema, or the connection's setup: the same
            // call fails the same way.
            return nil

        case .forbidden, .notFound, .unauthorized, .unexpectedStatus:
            // The server's answer about this request, which a repeat would not change.
            return nil
        }
    }

    /// Records that a call is about to be sent again: which attempt failed, as which
    /// ``APIError`` case, and the wait. All three are `.public` — an error case carries
    /// a status or a duration at most, never a URL or a body, which are not logged here
    /// at any privacy level.
    private func logRetry(after error: APIError, attempt: Int, delay: Duration) {
        let failure = String(describing: error)
        let wait = String(describing: delay)
        AppLog.network.debug(
            """
            Retrying an API call after attempt \(attempt, privacy: .public) failed as \
            \(failure, privacy: .public), in \(wait, privacy: .public)
            """,
        )
    }

    private func wait(for delay: Duration) async throws(APIError) {
        do {
            try await clock.sleep(for: delay)
        } catch {
            // A clock's sleep throws only `CancellationError`: the caller gave up.
            throw .cancelled
        }
    }
}
