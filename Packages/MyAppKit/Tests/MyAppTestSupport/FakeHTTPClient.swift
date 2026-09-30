import MyAppCore

/// The one fake of ``MyAppCore/HTTPClient``, shared by every test target.
///
/// A fake, not a mock: a real conforming implementation that answers each request with
/// the next outcome a test queued (``enqueue(_:)``) and records what it was sent
/// (``requests``) — no expectations are declared up front. ``HTTPClientContract`` holds
/// it to the same promises as `URLSessionHTTPClient`, so a Core service tested against
/// it is tested against the port, not against a convenient invention.
///
/// An actor, like ``InMemoryTodoRepository``, so it is `Sendable` without a lock.
package actor FakeHTTPClient: HTTPClient {
    /// How long a `hang` waits for a cancellation that a test forgot to send.
    private static let hangSeconds = 3_600

    /// Every request sent so far, in the order it was sent — including the ones that
    /// failed. A request sent from an already-cancelled task is not recorded: it never
    /// reached the server.
    package private(set) var requests: [HTTPRequest] = []

    private var outcomes: [HTTPStubOutcome] = []

    /// Starts with no queued outcomes.
    package init() {
        // Nothing queued and nothing sent: the stored defaults are the whole state.
    }

    /// Queues `outcome` as the answer to the next request that finds the queue at this
    /// point. Outcomes are played first in, first out, one per request.
    package func enqueue(_ outcome: HTTPStubOutcome) {
        outcomes.append(outcome)
    }

    /// Records `request`, then plays the next queued outcome.
    ///
    /// With nothing queued it throws ``MyAppCore/HTTPClientError/notConnected`` — a
    /// server nobody set up is a server that cannot be reached, and a test that forgot to
    /// queue an answer sees a failure rather than a made-up success.
    package func send(_ request: HTTPRequest) async throws(HTTPClientError) -> HTTPResponse {
        if Task.isCancelled {
            throw .cancelled
        }
        requests.append(request)
        guard !outcomes.isEmpty else {
            throw .notConnected
        }
        switch outcomes.removeFirst() {
        case let .respond(response):
            return response

        case let .fail(error):
            throw error

        case .hang:
            do {
                try await Task.sleep(for: .seconds(Self.hangSeconds))
            } catch {
                // `Task.sleep` throws only `CancellationError`: the caller gave up.
                throw .cancelled
            }
            // An hour without an answer: the request would have timed out long ago.
            throw .timedOut
        }
    }
}
