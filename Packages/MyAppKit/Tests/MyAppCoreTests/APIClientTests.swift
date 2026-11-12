import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

@Suite("APIClient")
struct APIClientTests {
    private static let itemJSON =
        #"{"createdAt":"\#(APIClientFixture.nowISO8601)","id":7,"title":"Milk"}"#

    /// The error each status that reads `Retry-After` throws, given the wait it read.
    private static let waitingErrors: [
        (statusCode: Int, error: @Sendable (Duration?) -> APIError)
    ] =
        [
            (429, { .rateLimited(retryAfter: $0) }),
            (503, { .server(status: 503, retryAfter: $0) }),
        ]

    // MARK: - 2xx

    @Test(arguments: [200, 201, 299])
    func `a 2xx response decodes its body as the endpoint's response type`(
        statusCode: Int,
    ) async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            statusCode,
            headers: ["Content-Type": "application/json"],
            body: Self.itemJSON,
        )))
        let client = APIClientFixture.client(over: fake)

        let item = try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))

        #expect(item == RemoteItem(id: 7, title: "Milk", createdAt: APIClientFixture.now))
    }

    @Test
    func `a snake-case key is not converted, so a camel-case property misses it`() async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            200,
            headers: [:],
            body: #"{"created_at":"\#(APIClientFixture.nowISO8601)","id":7,"title":"Milk"}"#,
        )))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: APIError.decoding) {
            try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))
        }
    }

    @Test(arguments: [
        #"{"id":"seven","title":"Milk","createdAt":"1994-11-06T08:49:37Z"}"#,
        #"{"id":7,"title":"Milk","createdAt":"06/11/1994"}"#,
        #"<html>Service page</html>"#,
        "",
    ])
    func `a 2xx body that does not decode throws decoding`(body: String) async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(200, headers: [:], body: body)))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: APIError.decoding) {
            try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))
        }
    }

    // MARK: - 2xx with no body

    @Test(arguments: [204, 200])
    func `an empty 2xx body returns the empty response for an EmptyResponse endpoint`(
        statusCode: Int,
    ) async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(statusCode, headers: [:], body: "")))
        let client = APIClientFixture.client(over: fake)

        let response = try await client.send(
            Endpoint<EmptyResponse>(method: .delete, path: "items/7"),
        )

        #expect(response == EmptyResponse())
    }

    @Test(arguments: [204, 200])
    func `an empty 2xx body still throws decoding for any other response type`(
        statusCode: Int,
    ) async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(statusCode, headers: [:], body: "")))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: APIError.decoding) {
            try await client.send(Endpoint<RemoteItem>(method: .delete, path: "items/7"))
        }
    }

    @Test(arguments: ["\n", "\r\n", " "])
    func `a whitespace-only 2xx body still throws decoding for any other response type`(
        body: String,
    ) async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(204, headers: [:], body: body)))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: APIError.decoding) {
            try await client.send(Endpoint<RemoteItem>(method: .delete, path: "items/7"))
        }
    }

    @Test(arguments: [
        "\n",
        "\r\n",
        " ",
        Self.itemJSON,
        "{}",
        "[1,2]",
        "null",
        "OK",
        "<html>Service page</html>",
    ])
    func `an EmptyResponse endpoint returns the empty response whatever the 2xx body is`(
        body: String,
    ) async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(200, headers: [:], body: body)))
        let client = APIClientFixture.client(over: fake)

        let response = try await client.send(
            Endpoint<EmptyResponse>(method: .put, path: "items/7"),
        )

        #expect(response == EmptyResponse())
    }

    // MARK: - Other statuses

    @Test(arguments: [
        (401, APIError.unauthorized),
        (403, .forbidden),
        (404, .notFound),
        (500, .server(status: 500, retryAfter: nil)),
        (503, .server(status: 503, retryAfter: nil)),
        (599, .server(status: 599, retryAfter: nil)),
        (400, .unexpectedStatus(400)),
        (409, .unexpectedStatus(409)),
        (422, .unexpectedStatus(422)),
        (499, .unexpectedStatus(499)),
        (199, .unexpectedStatus(199)),
        (300, .unexpectedStatus(300)),
        (304, .unexpectedStatus(304)),
        (600, .unexpectedStatus(600)),
    ])
    func `a non-2xx status throws the error its band names`(
        statusCode: Int,
        expected: APIError,
    ) async {
        let fake = FakeHTTPClient()
        // A decodable body, so only the status can be what fails the call.
        await fake.enqueue(.respond(APIClientFixture.response(
            statusCode,
            headers: [:],
            body: Self.itemJSON,
        )))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: expected) {
            try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))
        }
    }

    // MARK: - 429, 503, and Retry-After

    @Test(arguments: waitingErrors, [
        ([:], nil),
        (["Retry-After": "120"], Duration.seconds(120)),
        (["retry-after": "0"], .zero),
        (["RETRY-AFTER": " 30 "], .seconds(30)),
        // An HTTP-date two minutes after the pinned `now`.
        (["Retry-After": "Sun, 06 Nov 1994 08:51:37 GMT"], .seconds(120)),
        // An HTTP-date already past: retry now, never a negative wait.
        (["Retry-After": "Sat, 05 Nov 1994 08:49:37 GMT"], .zero),
        (["Retry-After": "-5"], nil),
        (["Retry-After": "1.5"], nil),
        (["Retry-After": "soon"], nil),
        (["Retry-After": ""], nil),
        (["Retry-After": "99999999999999999999999"], nil),
        // RFC 850's obsolete form, which Foundation's HTTP-date parser does not read.
        (["Retry-After": "Sunday, 06-Nov-94 08:51:37 GMT"], nil),
    ])
    func `a 429 or a 503 throws its error with the Retry-After delay it could read`(
        status: (statusCode: Int, error: @Sendable (Duration?) -> APIError),
        retryAfter: (headers: [String: String], expected: Duration?),
    ) async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            status.statusCode,
            headers: retryAfter.headers,
            body: "",
        )))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: status.error(retryAfter.expected)) {
            try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))
        }
    }

    @Test(arguments: [500, 502, 504, 599])
    func `a 5xx other than 503 does not read its Retry-After`(statusCode: Int) async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            statusCode,
            headers: ["Retry-After": "120"],
            body: "",
        )))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: APIError.server(status: statusCode, retryAfter: nil)) {
            try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))
        }
    }

    // MARK: - No response

    @Test(arguments: [
        (HTTPClientError.notConnected, APIError.offline),
        (.timedOut, .timedOut),
        (.cancelled, .cancelled),
        (.transport(code: -1_200), .transport),
        (.nonHTTPResponse, .transport),
    ])
    func `a request that ends without a response throws the matching API error`(
        failure: HTTPClientError,
        expected: APIError,
    ) async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.fail(failure))
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: expected) {
            try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))
        }
    }

    /// The time limit only bounds a regression that never reaches the fake; the wait
    /// below yields rather than sleeps, so a passing run takes no measurable time.
    @Test(.timeLimit(.minutes(1)))
    func `cancelling the calling task while the request is in flight throws cancelled`() async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.hang)
        let client = APIClientFixture.client(over: fake)

        let call = Task {
            try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))
        }
        // Cancel only once the fake holds the request, so this is the in-flight path
        // rather than the fake's already-cancelled check.
        while await fake.requests.isEmpty {
            await Task.yield()
        }
        call.cancel()

        await #expect(throws: APIError.cancelled) {
            try await call.value
        }
    }
}
