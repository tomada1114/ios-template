import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// Throws for every 4xx — breaks "a status is data, not an error".
private actor ClientErrorThrowingClient: HTTPClient {
    private static let clientErrors = 400 ..< 500

    private let inner: any HTTPClient

    init(wrapping inner: any HTTPClient) {
        self.inner = inner
    }

    func send(_ request: HTTPRequest) async throws(HTTPClientError) -> HTTPResponse {
        let response = try await inner.send(request)
        if Self.clientErrors.contains(response.statusCode) {
            throw .transport(code: response.statusCode)
        }
        return response
    }
}

/// Returns every response with an empty body — breaks "returned unchanged".
private actor BodyDroppingClient: HTTPClient {
    private let inner: any HTTPClient

    init(wrapping inner: any HTTPClient) {
        self.inner = inner
    }

    func send(_ request: HTTPRequest) async throws(HTTPClientError) -> HTTPResponse {
        let response = try await inner.send(request)
        return HTTPResponse(
            statusCode: response.statusCode,
            headers: response.headers,
            body: Data(),
        )
    }
}

/// Keeps waiting after its caller is cancelled, and gives up only after `delay` —
/// breaks "cancelling the calling task throws `cancelled`, promptly".
private actor CancellationIgnoringClient: HTTPClient {
    private static let delaySeconds = 2

    private let inner: any HTTPClient

    init(wrapping inner: any HTTPClient) {
        self.inner = inner
    }

    func send(_ request: HTTPRequest) async throws(HTTPClientError) -> HTTPResponse {
        let wrapped = inner
        // Unstructured, so the caller's cancellation does not reach the inner request.
        let attempt = Task { () -> Result<HTTPResponse, HTTPClientError> in
            do throws(HTTPClientError) {
                return try await .success(wrapped.send(request))
            } catch {
                return .failure(error)
            }
        }
        let result = await withTaskCancellationHandler {
            await attempt.value
        } onCancel: {
            // Cancels the inner request only after the delay, so nothing outlives the test
            // run by more than that.
            Task {
                try? await Task.sleep(for: .seconds(Self.delaySeconds))
                attempt.cancel()
            }
        }
        return try result.get()
    }
}

/// Runs the contract against a deliberately broken client wrapped around the fake, so
/// the "server" side is still the fake's queue and request log.
private struct BrokenClientHarness: HTTPClientContractHarness {
    let inner = FakeHTTPClientHarness()
    let breaking: @Sendable (any HTTPClient) -> any HTTPClient

    var baseURL: URL {
        inner.baseURL
    }

    func client(answering outcome: HTTPStubOutcome) async -> any HTTPClient {
        await breaking(inner.client(answering: outcome))
    }

    func receivedRequests() async -> [HTTPRequest] {
        await inner.receivedRequests()
    }
}

/// The fake half of the `HTTPClient` contract suite: the same ``HTTPClientContract`` that
/// `MyAppPlatformTests` runs against `URLSessionHTTPClient` runs here against
/// ``FakeHTTPClient``, so the fake cannot drift from the port's promises.
@Suite("HTTPClientContract, against the fake")
struct HTTPClientContractTests {
    static let url = URL(string: "https://example.invalid/items") ?? URL(fileURLWithPath: "/")

    @Test
    func `the fake keeps the contract`() async {
        await HTTPClientContract.check(FakeHTTPClientHarness())
    }

    // The contract's own oracle: a client that breaks a promise must be reported, or
    // `check(_:)` would pass anything, the real adapter included.

    @Test
    func `a client that throws for a 404 is reported`() async {
        let harness = BrokenClientHarness { ClientErrorThrowingClient(wrapping: $0) }
        let violations = await HTTPClientContract.violations(of: harness)
        #expect(!violations.isEmpty)
        #expect(violations.contains { $0.contains("a 4xx status is data, not an error") })
    }

    @Test
    func `a client that drops the body is reported`() async {
        let harness = BrokenClientHarness { BodyDroppingClient(wrapping: $0) }
        let violations = await HTTPClientContract.violations(of: harness)
        #expect(violations == ["a 404 response's body did not come back unchanged"])
    }

    @Test
    func `a client that ignores cancellation is reported`() async {
        let harness = BrokenClientHarness { CancellationIgnoringClient(wrapping: $0) }
        let violations = await HTTPClientContract.violations(
            of: harness,
            cancellationDeadline: .milliseconds(200),
        )
        #expect(!violations.isEmpty)
        #expect(violations.contains { $0.contains("did not end within") })
    }

    // MARK: - What only the fake promises

    @Test
    func `the fake with nothing queued throws notConnected and still records the request`() async {
        let fake = FakeHTTPClient()
        let request = HTTPRequest(url: Self.url)
        await #expect(throws: HTTPClientError.notConnected) {
            try await fake.send(request)
        }
        #expect(await fake.requests == [request])
    }

    @Test
    func `the fake plays its queue in order and records every request`() async throws {
        let fake = FakeHTTPClient()
        let first = HTTPRequest(url: Self.url)
        let second = HTTPRequest(method: .delete, url: Self.url)
        let answer = HTTPResponse(statusCode: 200, headers: [:], body: Data("ok".utf8))
        await fake.enqueue(.respond(answer))
        await fake.enqueue(.fail(.timedOut))

        #expect(try await fake.send(first) == answer)
        await #expect(throws: HTTPClientError.timedOut) {
            try await fake.send(second)
        }
        #expect(await fake.requests == [first, second])
    }

    @Test
    func `the fake refuses a request from an already-cancelled task without recording it`() async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(HTTPResponse(statusCode: 200, headers: [:], body: Data())))
        let request = HTTPRequest(url: Self.url)
        let sending = Task { () -> HTTPClientError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(HTTPClientError) {
                _ = try await fake.send(request)
                return nil
            } catch {
                return error
            }
        }
        #expect(await sending.value == .cancelled)
        #expect(await fake.requests.isEmpty)
    }
}
