import Foundation

/// What a server answered, whatever the status: an ``HTTPClient`` returns every HTTP
/// response as this value and throws only when no response arrived.
///
/// A 404 or a 503 is data, not an error, so the decision about it — "gone", "retry
/// later", "show the server's message" — stays in the Core service that made the
/// request, where a test hands it the status and sees what it does.
public struct HTTPResponse: Equatable, Sendable {
    /// The status codes ``isSuccess`` accepts: every 2xx.
    private static let successCodes = 200 ..< 300

    /// The HTTP status code, as the server sent it.
    public var statusCode: Int
    /// The response's header fields, as the server sent them.
    public var headers: [String: String]
    /// The response body; empty when the server sent none.
    public var body: Data

    /// Whether the status is a 2xx — the one question every caller asks first. Anything
    /// finer (a 304, a 429's `Retry-After`) is the caller's to read from ``statusCode``
    /// and ``headers``.
    public var isSuccess: Bool {
        Self.successCodes.contains(statusCode)
    }

    /// A response with exactly these fields — what an adapter builds from the wire, and
    /// what a test hands a fake to answer with.
    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}
