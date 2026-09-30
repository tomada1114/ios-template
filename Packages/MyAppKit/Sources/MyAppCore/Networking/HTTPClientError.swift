/// Everything an ``HTTPClient`` can report, in Core's vocabulary: the ways a request can
/// end without an HTTP response.
///
/// A closed set, so a Core service switches over it exhaustively and a new case breaks
/// every caller that must decide about it. There is no status-code case — a 4xx or 5xx
/// arrives as an ``HTTPResponse`` — and no underlying-error payload: the framework's
/// error text can quote the URL, which can carry user data, so it goes to the adapter's
/// log only.
public enum HTTPClientError: Error, Equatable, Sendable {
    /// The calling task was cancelled before a response arrived. Not a failure: the
    /// caller no longer wants the answer, so Core drops it quietly — no error state, no
    /// log line, no retry.
    case cancelled

    /// A response arrived, but not an HTTP one (a `file:` or `data:` URL answered).
    /// A programming error in the request, not a network condition: Core reports it as a
    /// failure and does not retry.
    case nonHTTPResponse

    /// The device has no usable connection, or the host could not be found or reached.
    /// Core shows an offline state and may retry once connectivity returns.
    case notConnected

    /// The server did not answer within ``HTTPRequest/timeout``. Core may retry, ideally
    /// with a backoff, or show a "try again" state.
    case timedOut

    /// Any other transport failure (a TLS error, a malformed response), identified only
    /// by the platform's error code so a log or a bug report can name it. Core treats it
    /// as a generic failure; branching on a specific `code` is a sign the case deserves
    /// a name of its own here.
    case transport(code: Int)
}
