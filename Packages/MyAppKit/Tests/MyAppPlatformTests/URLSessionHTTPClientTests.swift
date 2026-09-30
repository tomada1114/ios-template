import Foundation
import MyAppCore
@testable import MyAppPlatform
import MyAppTestSupport
import Testing

/// Runs ``HTTPClientContract`` against `URLSessionHTTPClient` over ``StubURLProtocol``:
/// the real `URLSession` stack, answered by a stub on a host no other test uses.
struct URLSessionHarness: HTTPClientContractHarness {
    let host = StubURLProtocol.uniqueHost()
    let session = StubURLProtocol.session()

    var baseURL: URL {
        URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/")
    }

    func client(answering outcome: HTTPStubOutcome) -> any HTTPClient {
        StubURLProtocol.register(host: host, reply: .outcome(outcome))
        return URLSessionHTTPClient(session: session)
    }

    func receivedRequests() -> [HTTPRequest] {
        StubURLProtocol.received(host: host)
    }
}

/// The adapter half of the `HTTPClient` contract suite, plus what only the adapter can
/// get wrong: mapping `URLError` codes it alone sees, a response that is not HTTP, and
/// converting the timeout.
///
/// Every request goes to ``StubURLProtocol`` on a `.invalid` host, so these run under
/// plain `just test` and in CI, and none of them touches the network.
@Suite("URLSessionHTTPClient")
struct URLSessionHTTPClientTests {
    /// Sends one GET to a fresh stub host that answers with `reply`.
    static func send(
        answering reply: StubURLProtocol.Reply,
    ) async throws(HTTPClientError) -> HTTPResponse {
        let host = StubURLProtocol.uniqueHost()
        StubURLProtocol.register(host: host, reply: reply)
        let url = URL(string: "https://\(host)/items") ?? URL(fileURLWithPath: "/")
        let client = URLSessionHTTPClient(session: StubURLProtocol.session())
        return try await client.send(HTTPRequest(url: url))
    }

    @Test
    func `the URLSession adapter keeps the contract`() async {
        await HTTPClientContract.check(URLSessionHarness())
    }

    @Test(arguments: [
        (URLError.Code.cannotFindHost, HTTPClientError.notConnected),
        (.cannotConnectToHost, .notConnected),
        (.dataNotAllowed, .notConnected),
        (.networkConnectionLost, .notConnected),
        (.notConnectedToInternet, .notConnected),
        (.timedOut, .timedOut),
        (.badServerResponse, .transport(code: URLError.badServerResponse.rawValue)),
        (.secureConnectionFailed, .transport(code: URLError.secureConnectionFailed.rawValue)),
    ])
    func `a URLError from the transport maps to Core's error`(
        code: URLError.Code,
        expected: HTTPClientError,
    ) async {
        await #expect(throws: expected) {
            try await Self.send(answering: .urlError(code))
        }
    }

    @Test
    func `a response that is not HTTP throws nonHTTPResponse`() async {
        await #expect(throws: HTTPClientError.nonHTTPResponse) {
            try await Self.send(answering: .outcome(.fail(.nonHTTPResponse)))
        }
    }

    @Test
    func `a request's timeout reaches the transport in seconds`() async throws {
        let harness = URLSessionHarness()
        let client = harness.client(
            answering: .respond(HTTPResponse(statusCode: 204, headers: [:], body: Data())),
        )
        let request = HTTPRequest(url: harness.baseURL, timeout: .milliseconds(1_500))
        _ = try await client.send(request)
        let received = harness.receivedRequests()
        #expect(received.map(\.timeout) == [.milliseconds(1_500)])
    }

    @Test(arguments: [
        (Duration.seconds(30), 30.0),
        (.milliseconds(1_500), 1.5),
        (.zero, 0.0),
    ])
    func `a Duration converts to a TimeInterval in seconds`(
        duration: Duration,
        seconds: TimeInterval,
    ) {
        #expect(URLSessionHTTPClient.timeInterval(duration) == seconds)
    }

    @Test(arguments: [
        (CancellationError() as any Error, HTTPClientError.cancelled),
        (URLError(.cancelled), .cancelled),
        (NSError(domain: NSCocoaErrorDomain, code: 42), .transport(code: 42)),
    ])
    func `an error that is not a transport URLError still maps to Core's error`(
        error: any Error,
        expected: HTTPClientError,
    ) {
        #expect(URLSessionHTTPClient.clientError(for: error) == expected)
    }
}
