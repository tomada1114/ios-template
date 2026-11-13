import MyAppCore

/// How a stubbed server answers one request: the one vocabulary ``FakeHTTPClient`` and
/// `MyAppPlatformTests`' `StubURLProtocol` both speak, so ``HTTPClientContract`` can ask
/// either for the same answer.
package enum HTTPStubOutcome: Sendable {
    /// The request fails without a response, as this error.
    case fail(HTTPClientError)
    /// The server never answers. The request ends only when the calling task is
    /// cancelled, so a test of cancellation has something in flight to cancel.
    case hang
    /// The server answers with this response, whatever its status.
    case respond(HTTPResponse)
}
