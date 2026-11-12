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
///   ``APIError/server(status:)``, and ``APIError/rateLimited(retryAfter:)`` — failures
///   that describe the moment, not the request. Every other case would fail the same
///   way again and is thrown at once.
/// - **How long it waits:** a 429's `Retry-After`, up to ``RetryPolicy/maxDelay``;
///   otherwise the policy's jittered exponential backoff.
/// - **What is never repeated:** a call whose method is not idempotent
///   (``HTTPRequest/Method/isIdempotent``), unless its endpoint opts in with
///   ``Endpoint/isSafeToRepeat``. A timed-out `POST` may have reached the server; sending
///   it again could create the thing twice.
/// - **Cancellation** ends the call at once with ``APIError/cancelled``, mid-wait
///   included, and is never retried.
///
/// It waits on an injected `Clock` and draws jitter from an injected generator, so
/// `RetryPolicyTests` cover every wait without one passing — the worked example of
/// both (`.claude/rules/core.md` › Inject what Core would read from the world). An
/// actor because the generator is state that concurrent calls draw from; calls still
/// run concurrently, since each suspends while it sends and while it waits.
public actor RetryingAPIClient {
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
    /// calling task is cancelled.
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
                let failedAttempt = attempt
                AppLog.network
                    .debug("Retrying an API call after attempt \(failedAttempt, privacy: .public)")
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
        case .offline, .server, .timedOut:
            return policy.delay(afterAttempt: attempt, using: &generator)

        case let .rateLimited(retryAfter):
            guard let retryAfter else {
                return policy.delay(afterAttempt: attempt, using: &generator)
            }
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

    private func wait(for delay: Duration) async throws(APIError) {
        do {
            try await clock.sleep(for: delay)
        } catch {
            // A clock's sleep throws only `CancellationError`: the caller gave up.
            throw .cancelled
        }
    }
}
