import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// What an ``APIClient`` puts on the wire: the request ``FakeHTTPClient`` recorded.
@Suite("APIClient requests")
struct APIClientRequestTests {
    private static let createdJSON =
        #"{"createdAt":"\#(APIClientFixture.nowISO8601)","id":7,"title":"Milk"}"#

    @Test
    func `an endpoint with a body is sent as JSON with its method, path, query, and headers`(
    ) async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            201,
            headers: [:],
            body: Self.createdJSON,
        )))
        let client = APIClientFixture.client(over: fake)

        _ = try await client.send(Endpoint<RemoteItem>(
            method: .post,
            path: "lists/groceries/items",
            queryItems: [URLQueryItem(name: "notify", value: "true")],
            body: NewRemoteItem(title: "Milk", dueAt: APIClientFixture.now),
            headers: ["X-Request-ID": "42"],
        ))

        let url = try #require(
            URL(string: "https://api.example.invalid/v1/lists/groceries/items?notify=true"),
        )
        let expected = HTTPRequest(
            method: .post,
            url: url,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "X-Request-ID": "42",
            ],
            body: Data(#"{"dueAt":"\#(APIClientFixture.nowISO8601)","title":"Milk"}"#.utf8),
        )
        #expect(await fake.requests == [expected])
    }

    @Test
    func `an endpoint without a body or query sends no body, no Content-Type, and no question mark`(
    ) async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            200,
            headers: [:],
            body: Self.createdJSON,
        )))
        let client = APIClientFixture.client(over: fake)

        _ = try await client.send(Endpoint<RemoteItem>(method: .get, path: "items/7"))

        let url = try #require(URL(string: "https://api.example.invalid/v1/items/7"))
        let expected = HTTPRequest(
            method: .get,
            url: url,
            headers: ["Accept": "application/json"],
        )
        #expect(await fake.requests == [expected])
    }

    @Test
    func `a path with a leading slash still lands under the base URL's path`() async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            200,
            headers: [:],
            body: Self.createdJSON,
        )))
        let client = APIClientFixture.client(over: fake)

        _ = try await client.send(Endpoint<RemoteItem>(method: .get, path: "/items/7"))

        let sent = try #require(await fake.requests.first)
        #expect(sent.url.absoluteString == "https://api.example.invalid/v1/items/7")
    }

    @Test
    func `an endpoint's header replaces a default of the same name in any case`() async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(APIClientFixture.response(
            201,
            headers: [:],
            body: Self.createdJSON,
        )))
        let client = APIClientFixture.client(over: fake)

        _ = try await client.send(Endpoint<RemoteItem>(
            method: .put,
            path: "items/7",
            body: NewRemoteItem(title: "Milk", dueAt: APIClientFixture.now),
            headers: [
                "accept": "application/problem+json",
                "content-type": "application/merge-patch+json",
            ],
        ))

        let sent = try #require(await fake.requests.first)
        #expect(sent.headers == [
            "accept": "application/problem+json",
            "content-type": "application/merge-patch+json",
        ])
    }

    @Test
    func `a body that cannot be encoded throws encoding and sends nothing`() async {
        let fake = FakeHTTPClient()
        let client = APIClientFixture.client(over: fake)

        await #expect(throws: APIError.encoding) {
            try await client.send(Endpoint<RemoteItem>(
                method: .post,
                path: "items",
                body: UnencodableBody(),
            ))
        }
        #expect(await fake.requests.isEmpty)
    }

    @Test
    func `an endpoint defaults to no query, no body, and no extra headers`() {
        let endpoint = Endpoint<RemoteItem>(method: .delete, path: "items/7")

        #expect(endpoint.method == .delete)
        #expect(endpoint.path == "items/7")
        #expect(endpoint.queryItems.isEmpty)
        #expect(endpoint.body == nil)
        #expect(endpoint.headers.isEmpty)
    }
}
