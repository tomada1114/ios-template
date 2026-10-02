import Foundation
import MyAppCore
import MyAppTestSupport

/// A resource as a server returns it — what the 2xx tests decode.
struct RemoteItem: Codable, Equatable, Sendable {
    var id: Int
    var title: String
    var createdAt: Date
}

/// A request body the encoding tests send.
struct NewRemoteItem: Encodable, Sendable {
    var title: String
    var dueAt: Date
}

/// A body `JSONEncoder` refuses: its default non-conforming-float strategy throws on NaN.
struct UnencodableBody: Encodable, Sendable {
    var ratio = Double.nan
}

/// Shared values and builders for the `APIClient` suites.
enum APIClientFixture {
    /// The base URL every client in these suites is made with. `.invalid` is reserved
    /// (RFC 2606), so nothing here could reach a real host even by mistake.
    static let baseURL = URL(string: "https://api.example.invalid/v1") ?? URL(fileURLWithPath: "/")

    /// What the injected `now` answers: Sun, 06 Nov 1994 08:49:37 GMT — the example date
    /// RFC 9110 uses for an HTTP-date.
    static let now = Date(timeIntervalSince1970: nowSince1970)

    private static let nowSince1970: TimeInterval = 784_111_777

    /// ``now`` as the client's encoder writes it and its decoder reads it.
    static let nowISO8601 = "1994-11-06T08:49:37Z"

    /// A client over `fake` whose clock is pinned to ``now``.
    static func client(over fake: FakeHTTPClient) -> APIClient {
        let pinnedNow = now
        return APIClient(httpClient: fake, baseURL: baseURL) { pinnedNow }
    }

    /// A response with `statusCode`, `headers`, and `body` as UTF-8.
    static func response(
        _ statusCode: Int,
        headers: [String: String],
        body: String,
    ) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, headers: headers, body: Data(body.utf8))
    }
}
