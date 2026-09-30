import Foundation

/// One HTTP request, in Core's vocabulary: what a Core service asks an ``HTTPClient`` to
/// send.
///
/// A plain value, so a test builds one with a literal and compares what a fake recorded
/// with `==`. Nothing here names the adapter's framework: Core describes the request, and
/// the adapter in `MyAppPlatform` decides how to put it on the wire.
public struct HTTPRequest: Equatable, Sendable {
    /// The request methods a Core service may send. A closed set rather than a string,
    /// so a typo is a compile error instead of a request the server rejects.
    public enum Method: String, Sendable {
        case delete = "DELETE"
        case get = "GET"
        case patch = "PATCH"
        case post = "POST"
        case put = "PUT"
    }

    /// How long a request waits for the server unless the caller says otherwise.
    public static let defaultTimeout: Duration = .seconds(defaultTimeoutSeconds)

    private static let defaultTimeoutSeconds = 30

    /// The request method.
    public var method: Method
    /// The absolute URL the request goes to.
    public var url: URL
    /// The header fields to send. The adapter may add its own (`User-Agent`,
    /// `Content-Length`); these are the ones the caller decides.
    public var headers: [String: String]
    /// The body to send, or `nil` for none.
    public var body: Data?
    /// How long the request may wait for the server before it fails with
    /// ``HTTPClientError/timedOut``. A `Duration` rather than a `TimeInterval`, so Core
    /// speaks the same unit as its `Clock`s.
    public var timeout: Duration

    /// A request with the defaults most calls want: a bodiless `GET` with no headers
    /// and a ``defaultTimeout``.
    ///
    /// Two initializers rather than one with `method: Method = .get` first: a defaulted
    /// parameter ahead of `url` is what SwiftLint's `function_default_parameter_at_end`
    /// rejects, and the pair keeps both call shapes — `HTTPRequest(url:)` and
    /// `HTTPRequest(method: .post, url:, …)`.
    public init(
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: Duration = defaultTimeout,
    ) {
        self.init(method: .get, url: url, headers: headers, body: body, timeout: timeout)
    }

    /// A request with an explicit method; the remaining fields default as in
    /// ``init(url:headers:body:timeout:)``.
    public init(
        method: Method,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: Duration = defaultTimeout,
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}
