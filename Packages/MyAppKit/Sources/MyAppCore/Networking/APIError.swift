/// Everything an ``APIClient`` call can end in other than a decoded response: the
/// question "what went wrong, and what should the app do about it?" answered once, in
/// Core's vocabulary.
///
/// A closed set, so a feature switches over it exhaustively and a new case breaks every
/// caller that must decide about it. No payload carries a response body, a URL, or an
/// underlying error: a body and a URL can hold user data, and an error value travels —
/// into logs, crash reports, and test output.
public enum APIError: Error, Equatable, Sendable {
    /// The calling task was cancelled before the call finished. Not a failure: the caller
    /// no longer wants the answer, so it drops it quietly — no error state, no log line,
    /// no retry.
    case cancelled

    /// A 2xx response arrived, but its body did not decode as the endpoint's response
    /// type — the server and the app disagree about the schema. Retrying will not help.
    /// The client logs the response type's name, never the body.
    case decoding

    /// The endpoint's ``Endpoint/body`` could not be encoded as JSON (a `Double.nan`, say,
    /// or an `encode(to:)` that throws), so nothing was sent. A programming error in the
    /// request type, not a network condition: report it, never retry it.
    case encoding

    /// The server answered 403: the credentials are valid but not allowed this resource.
    /// Signing in again will not help; show that the action is not permitted.
    case forbidden

    /// The server answered 404: the resource does not exist, or no longer does.
    case notFound

    /// The device has no usable connection, or the host could not be found or reached.
    /// Show an offline state; retry once connectivity returns.
    case offline

    /// The server answered 429. `retryAfter` is how long its `Retry-After` header asked
    /// the client to wait — read as delta-seconds or an HTTP-date, never negative — or
    /// `nil` when the header was missing or unreadable, in which case the caller picks
    /// its own backoff.
    case rateLimited(retryAfter: Duration?)

    /// The server answered with a 5xx: its own failure. `status` says which, for a log
    /// or a decision (a 503 is often worth a retry; a 501 never is).
    case server(status: Int)

    /// The server went silent for longer than the request's idle timeout. Retry, ideally
    /// with a backoff, or show a "try again" state.
    case timedOut

    /// The request failed without an HTTP response for a reason other than
    /// connectivity, a timeout, or cancellation — a TLS failure, a malformed or non-HTTP
    /// response (``HTTPClientError/transport(code:)``,
    /// ``HTTPClientError/nonHTTPResponse``). The adapter has already logged the detail;
    /// treat it as a generic failure.
    case transport

    /// The server answered 401: the request carried no credentials, or ones it no longer
    /// accepts. The caller signs the user in again (or refreshes a token) before retrying.
    case unauthorized

    /// Any status none of the cases above names: a 1xx or 3xx the transport did not
    /// handle, a 4xx other than 401, 403, 404, or 429, or a code outside 100–599. The
    /// status is kept so a log or a bug report can name it; branching on a specific
    /// value is a sign it deserves a case of its own here.
    case unexpectedStatus(Int)
}
