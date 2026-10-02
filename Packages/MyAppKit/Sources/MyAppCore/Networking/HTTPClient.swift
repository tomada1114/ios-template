/// A port: send one HTTP request, get one HTTP response.
///
/// The networking twin of ``TodoRepository`` (`docs/architecture.md` › Repositories ›
/// The HTTP client port). Core declares the protocol; `MyAppPlatform` holds the adapter
/// (`URLSessionHTTPClient`); `MyAppTestSupport` holds the fake every Core test uses
/// (`FakeHTTPClient`); and `App/` — the composition root — decides which one a Core
/// service gets. A Core service that calls a remote API takes an `HTTPClient`, so it is
/// tested against the fake, never against the real network.
///
/// Deliberately small: one request in, one response out. JSON encoding, decoding, and
/// the meaning of a status are ``APIClient``'s, built over it; retries, auth, and
/// caching are Core services built over that, not features of the port.
///
/// `HTTPClientContract` in `MyAppTestSupport` checks the promises below against the fake
/// and against the adapter, both under `just test`; a new promise is stated here first,
/// then added there.
///
/// 1. Any HTTP status, including a 4xx or 5xx, is returned as an ``HTTPResponse``, never
///    thrown — the decision about a status is the caller's.
/// 2. The request's method, URL, headers, and body are what the server receives.
/// 3. The response's status, header values, and body are returned unchanged; a header
///    name may arrive in another case (see ``HTTPResponse/headers``).
/// 4. No connection throws ``HTTPClientError/notConnected``; a server silent for longer
///    than ``HTTPRequest/timeout`` — an idle timeout, not a total deadline — throws
///    ``HTTPClientError/timedOut``.
/// 5. Cancelling the calling task throws ``HTTPClientError/cancelled``, promptly — an
///    in-flight request is abandoned, not waited out.
public protocol HTTPClient: Sendable {
    /// Sends `request` and returns the server's response, whatever its status; throws
    /// only when no HTTP response arrived.
    func send(_ request: HTTPRequest) async throws(HTTPClientError) -> HTTPResponse
}
