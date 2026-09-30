import Foundation
import MyAppCore
import Testing

/// The server side of one ``MyAppCore/HTTPClient`` implementation under
/// ``HTTPClientContract``: it makes a client whose server answers as told, and reports
/// what that server received.
///
/// The contract cannot talk to a server itself — for the fake the "server" is the fake's
/// queue, for `URLSessionHTTPClient` it is a `URLProtocol` stub — so each implementation
/// brings a harness, and the contract is written once over the protocol.
package protocol HTTPClientContractHarness: Sendable {
    /// The origin every request the contract sends goes to. A harness that routes by
    /// host (the `URLProtocol` stub does) returns one no other harness uses, so contract
    /// runs in parallel tests never answer each other's requests.
    var baseURL: URL { get }

    /// A client whose server answers every request with `outcome`. Each call makes a new
    /// client and forgets what the previous one's server received.
    func client(answering outcome: HTTPStubOutcome) async -> any HTTPClient

    /// What the server behind the last client made has received, in order.
    func receivedRequests() async -> [HTTPRequest]
}

/// The harness that runs ``HTTPClientContract`` against ``FakeHTTPClient``: each client is
/// a fresh fake with the outcome queued, and its ``FakeHTTPClient/requests`` is what the
/// "server" received.
package actor FakeHTTPClientHarness: HTTPClientContractHarness {
    private var lastClient = FakeHTTPClient()

    package nonisolated var baseURL: URL {
        HTTPClientContract.Fixture.fakeOrigin
    }

    /// Starts with no client made.
    package init() {
        // `lastClient` starts as an empty fake, so `receivedRequests()` answers `[]`.
    }

    package func client(answering outcome: HTTPStubOutcome) async -> any HTTPClient {
        let client = FakeHTTPClient()
        await client.enqueue(outcome)
        lastClient = client
        return client
    }

    package func receivedRequests() async -> [HTTPRequest] {
        await lastClient.requests
    }
}

/// The promises ``MyAppCore/HTTPClient`` makes, checked against any implementation.
///
/// A fake stands in for the adapter only while both keep the port's promises, so they
/// are written once, here, over the protocol. `MyAppCoreTests` runs ``check(_:)`` against
/// ``FakeHTTPClient`` through ``FakeHTTPClientHarness``; `MyAppPlatformTests` runs it
/// against `URLSessionHTTPClient` over a `URLProtocol` stub. Both run under `just test`
/// and in CI, and neither touches the real network. Every clause is one the port's `///`
/// states; a new clause is stated there first.
package enum HTTPClientContract {
    /// Fixed values, so a failure message names the same request on every run.
    enum Fixture {
        static let fakeOrigin = URL(string: "https://contract.invalid")
            ?? URL(fileURLWithPath: "/")
        static let testHeader = "X-Contract-Test"
        static let notFound = 404
        static let serverError = 500
        static let created = 201
        static let notFoundBody = Data("no such item".utf8)
        static let postBody = Data(#"{"title":"Contract"}"#.utf8)
        /// How often, in milliseconds, the cancellation clause looks for its request at
        /// the server.
        static let pollMilliseconds = 10
    }

    private enum Race: Sendable {
        case deadlinePassed
        case finished(Result<HTTPResponse, HTTPClientError>)
    }

    /// How long a cancelled, hanging request may take to end before the contract calls
    /// it a violation — so a client that ignores cancellation fails the check instead of
    /// hanging the suite.
    package static let cancellationDeadline: Duration = .seconds(cancellationDeadlineSeconds)

    private static let cancellationDeadlineSeconds = 5

    /// A description of every broken promise, empty when the harness's client keeps
    /// them all.
    ///
    /// Separate from ``check(_:)`` so a test can hand it a client that breaks a promise
    /// and see the contract notice — the proof it is not vacuous.
    package static func violations(
        of harness: some HTTPClientContractHarness,
    ) async -> [String] {
        await violations(of: harness, cancellationDeadline: cancellationDeadline)
    }

    /// ``violations(of:)`` with a shorter cancellation deadline, so an oracle test of a
    /// client that ignores cancellation fails fast instead of waiting out five seconds.
    package static func violations(
        of harness: some HTTPClientContractHarness,
        cancellationDeadline: Duration,
    ) async -> [String] {
        var broken = await statusesAreData(harness)
        broken += await requestArrivesUnchanged(harness)
        broken += await failuresAreReported(harness)
        broken += await cancellationEndsTheRequest(harness, within: cancellationDeadline)
        return broken
    }

    /// Records an issue for every promise the harness's client breaks.
    package static func check(_ harness: some HTTPClientContractHarness) async {
        let broken = await violations(of: harness)
        #expect(broken.isEmpty, "\(type(of: harness)) breaks the HTTPClient contract: \(broken)")
    }

    // MARK: - Clauses

    /// Promises 1 and 3: a 4xx or 5xx is returned, not thrown, with its status, headers,
    /// and body unchanged.
    private static func statusesAreData(
        _ harness: some HTTPClientContractHarness,
    ) async -> [String] {
        var broken: [String] = []
        let notFound = HTTPResponse(
            statusCode: Fixture.notFound,
            headers: [Fixture.testHeader: "missing"],
            body: Fixture.notFoundBody,
        )
        let request = HTTPRequest(url: harness.baseURL.appending(path: "items/missing"))
        switch await outcome(of: harness.client(answering: .respond(notFound)), sending: request) {
        case let .success(response):
            if response.statusCode != Fixture.notFound {
                broken.append("a 404 response came back with status \(response.statusCode)")
            }
            if headerValue(Fixture.testHeader, in: response.headers) != "missing" {
                broken.append("a 404 response's headers did not come back unchanged")
            }
            if response.body != Fixture.notFoundBody {
                broken.append("a 404 response's body did not come back unchanged")
            }

        case let .failure(error):
            broken.append("a 404 response threw \(error): a 4xx status is data, not an error")
        }

        let serverError = HTTPResponse(statusCode: Fixture.serverError, headers: [:], body: Data())
        let answer = await outcome(
            of: harness.client(answering: .respond(serverError)),
            sending: request,
        )
        switch answer {
        case let .success(response) where response.statusCode != Fixture.serverError:
            broken.append("a 500 response came back with status \(response.statusCode)")

        case .success:
            break

        case let .failure(error):
            broken.append("a 500 response threw \(error): a 5xx status is data, not an error")
        }
        return broken
    }

    /// Promise 2: the method, URL, headers, and body are what the server receives. Only
    /// the test's own header is compared: a real transport adds its own.
    private static func requestArrivesUnchanged(
        _ harness: some HTTPClientContractHarness,
    ) async -> [String] {
        var broken: [String] = []
        let request = HTTPRequest(
            method: .post,
            url: harness.baseURL.appending(path: "items")
                .appending(queryItems: [URLQueryItem(name: "source", value: "contract")]),
            headers: [Fixture.testHeader: "arrives"],
            body: Fixture.postBody,
        )
        let created = HTTPResponse(statusCode: Fixture.created, headers: [:], body: Data())
        let client = await harness.client(answering: .respond(created))
        if case let .failure(error) = await outcome(of: client, sending: request) {
            broken.append("a POST the server answered with 201 threw \(error)")
        }
        let received = await harness.receivedRequests()
        guard received.count == 1, let seen = received.first else {
            return broken + ["one POST reached the server \(received.count) times"]
        }
        if seen.method != .post {
            broken.append("a POST arrived as \(seen.method.rawValue)")
        }
        if seen.url != request.url {
            broken.append("a request for \(request.url) arrived for \(seen.url)")
        }
        if headerValue(Fixture.testHeader, in: seen.headers) != "arrives" {
            broken.append("a request's \(Fixture.testHeader) header did not arrive unchanged")
        }
        if seen.body != Fixture.postBody {
            broken.append("a request's body did not arrive unchanged")
        }
        return broken
    }

    /// Promise 4: no connection throws `notConnected`; a timeout throws `timedOut`.
    private static func failuresAreReported(
        _ harness: some HTTPClientContractHarness,
    ) async -> [String] {
        var broken: [String] = []
        let request = HTTPRequest(url: harness.baseURL.appending(path: "items"))
        for expected in [HTTPClientError.notConnected, .timedOut] {
            let client = await harness.client(answering: .fail(expected))
            switch await outcome(of: client, sending: request) {
            case let .success(response):
                broken.append(
                    "a request that failed as \(expected) returned status \(response.statusCode)",
                )

            case let .failure(error) where error != expected:
                broken.append("a request that failed as \(expected) threw \(error)")

            case .failure:
                break
            }
        }
        return broken
    }

    /// Promise 5: cancelling the calling task while the request is in flight throws
    /// `cancelled`, within `deadline`.
    ///
    /// The request is cancelled only once the server has it — polled, because the
    /// harness offers no signal — so what is tested is abandoning an in-flight request,
    /// not refusing one from a task that was already cancelled.
    private static func cancellationEndsTheRequest(
        _ harness: some HTTPClientContractHarness,
        within deadline: Duration,
    ) async -> [String] {
        let client = await harness.client(answering: .hang)
        let request = HTTPRequest(url: harness.baseURL.appending(path: "hang"))
        let sending = Task { await outcome(of: client, sending: request) }

        let clock = ContinuousClock()
        let started = clock.now
        while await harness.receivedRequests().isEmpty, clock.now - started < deadline {
            try? await Task.sleep(for: .milliseconds(Fixture.pollMilliseconds))
        }
        sending.cancel()

        switch await result(of: sending, before: deadline) {
        case .none:
            return ["a hanging request did not end within \(deadline) of its task being cancelled"]

        case let .success(response):
            return [
                "a cancelled hanging request returned status \(response.statusCode), not cancelled",
            ]

        case .failure(.cancelled):
            return []

        case let .failure(error):
            return ["a cancelled hanging request threw \(error), not cancelled"]
        }
    }

    // MARK: - Helpers

    private static func outcome(
        of client: any HTTPClient,
        sending request: HTTPRequest,
    ) async -> Result<HTTPResponse, HTTPClientError> {
        do {
            return try await .success(client.send(request))
        } catch {
            return .failure(error)
        }
    }

    /// `sending`'s result, or `nil` when `deadline` passes first. Neither side is a
    /// child task: a task group waits for every child, so a client that never ends
    /// would hang the group — exactly what the deadline exists to prevent.
    private static func result(
        of sending: Task<Result<HTTPResponse, HTTPClientError>, Never>,
        before deadline: Duration,
    ) async -> Result<HTTPResponse, HTTPClientError>? {
        let (races, continuation) = AsyncStream.makeStream(of: Race.self)
        let watcher = Task { await continuation.yield(.finished(sending.value)) }
        let timer = Task {
            try? await Task.sleep(for: deadline)
            continuation.yield(.deadlinePassed)
        }
        var iterator = races.makeAsyncIterator()
        let first = await iterator.next()
        continuation.finish()
        timer.cancel()
        watcher.cancel()
        guard case let .finished(result) = first else {
            return nil
        }
        return result
    }

    /// A header's value, looked up by name case-insensitively, as HTTP field names are.
    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
