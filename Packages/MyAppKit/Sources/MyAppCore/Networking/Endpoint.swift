import Foundation

/// One call to a JSON API, described as a value: what to send, and the type the 2xx
/// body decodes as.
///
/// A feature declares its endpoints as values — usually `static func`s on a caseless
/// enum beside the feature (`Endpoint<[Item]>(method: .get, path: "items")`) — and an
/// ``APIClient`` turns each into an ``HTTPRequest``: it resolves ``path`` against its
/// base URL, encodes ``body`` with its one configured `JSONEncoder`, and decodes the
/// answer as `Response`. The endpoint never holds a host or a coder, so the same value
/// works against a staging server and production, and every call in the app encodes
/// dates and keys the same way.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    /// The request method.
    public var method: HTTPRequest.Method

    /// The path below the client's base URL, such as `"items/42"`. A leading `/` is
    /// harmless: it still lands below the base URL's own path, never at the host's root.
    /// Each segment is percent-encoded as needed, so a `?` here is part of the path —
    /// the query goes in ``queryItems``.
    public var path: String

    /// The query, in order, percent-encoded by the client. Empty sends no `?` at all.
    public var queryItems: [URLQueryItem]

    /// The JSON body, or `nil` for none. Encoded by the client's `JSONEncoder`, so a
    /// `Date` property goes out as ISO 8601 and keys go out as the type spells them
    /// (``APIClient``). A body sends `Content-Type: application/json` unless
    /// ``headers`` names its own.
    public var body: (any Encodable & Sendable)?

    /// Header fields for this call alone, such as an idempotency key. One whose name
    /// matches a default the client sets (`Accept`, `Content-Type`), in any case,
    /// replaces it.
    public var headers: [String: String]

    /// Whether sending this call twice leaves the server as sending it once would, though
    /// its method does not promise that — a `POST` the server deduplicates by an
    /// idempotency key, say. ``RetryingAPIClient`` never repeats a non-idempotent call
    /// (``HTTPRequest/Method/isIdempotent``) without it: only the feature that declares
    /// the endpoint knows a repeat is harmless, so the default is `false`. It changes
    /// nothing about a method that is idempotent already.
    public var isSafeToRepeat: Bool

    /// An endpoint with every field given; only `method` and `path` are required.
    public init(
        method: HTTPRequest.Method,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        headers: [String: String] = [:],
        isSafeToRepeat: Bool = false,
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.headers = headers
        self.isSafeToRepeat = isSafeToRepeat
    }
}
