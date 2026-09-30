import Foundation
import MyAppCore

/// The `URLSession`-backed adapter for ``MyAppCore/HTTPClient``.
///
/// Translation only, in the manner of `SwiftDataTodoRepository`: it builds a
/// `URLRequest` from Core's ``MyAppCore/HTTPRequest``, returns every HTTP response as an
/// ``MyAppCore/HTTPResponse`` whatever its status, and maps every `URLError` into
/// ``MyAppCore/HTTPClientError``. What a status or a failure means is Core's decision.
/// `HTTPClientContract` checks the translation in `MyAppPlatformTests`, over a
/// `URLProtocol` stub — under plain `just test`, without touching the network.
///
/// A struct: `URLSession` is `Sendable` and does its own synchronization, so the adapter
/// needs no actor of its own.
public struct URLSessionHTTPClient: HTTPClient {
    /// The `URLError` codes that mean "no usable connection to that host" — the ones
    /// Core answers with an offline state rather than a generic failure.
    private static let notConnectedCodes: Set<URLError.Code> = [
        .cannotConnectToHost,
        .cannotFindHost,
        .dataNotAllowed,
        .networkConnectionLost,
        .notConnectedToInternet,
    ]

    private static let attosecondsPerSecond = 1e18

    private let session: URLSession

    /// An adapter over `session` — `.shared` for the app; a session configured with a
    /// stub `URLProtocol` for tests.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// `duration` in seconds, as `URLRequest.timeoutInterval` wants it.
    static func timeInterval(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / attosecondsPerSecond
    }

    /// Core's error for what `URLSession` threw. A `URLError` maps by its code; a
    /// `CancellationError` is the calling task's cancellation; anything else is a
    /// transport failure identified by its `NSError` code.
    static func clientError(for error: any Error) -> HTTPClientError {
        if let urlError = error as? URLError {
            // `URLError.Code` is the SDK's, not Core's: the codes named here are the ones
            // Core decides on, and every other one is identified only by its number.
            switch urlError.code {
            case .cancelled:
                return .cancelled

            case .timedOut:
                return .timedOut

            case let code where notConnectedCodes.contains(code):
                return .notConnected

            default:
                return .transport(code: urlError.code.rawValue)
            }
        }
        if error is CancellationError {
            return .cancelled
        }
        return .transport(code: (error as NSError).code)
    }

    private static func urlRequest(for request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(
            url: request.url,
            timeoutInterval: timeInterval(request.timeout),
        )
        urlRequest.httpMethod = request.method.rawValue
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    private static func headers(of response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (field, value) in response.allHeaderFields {
            headers[String(describing: field.base)] = String(describing: value)
        }
        return headers
    }

    /// Maps `error`, logging it unless it is the caller's own cancellation — which is not
    /// a failure (the `designing-errors` skill).
    private static func failure(
        _ error: any Error,
        sending request: HTTPRequest,
    ) -> HTTPClientError {
        let mapped = clientError(for: error)
        if mapped != .cancelled {
            log(mapped, sending: request, detail: String(describing: error))
        }
        return mapped
    }

    /// The method and host are `.public`, so a log shows which API failed; the path and
    /// the framework's text are `.private`, because a URL can carry user data and the
    /// text quotes it.
    private static func log(
        _ mapped: HTTPClientError,
        sending request: HTTPRequest,
        detail: String,
    ) {
        let method = request.method.rawValue
        let host = request.url.host() ?? "(no host)"
        let path = request.url.path()
        let failure = String(describing: mapped)
        AppLog.network.error(
            """
            \(method, privacy: .public) \(host, privacy: .public) \
            \(path, privacy: .private) failed as \(failure, privacy: .public): \
            \(detail, privacy: .private)
            """,
        )
    }

    public func send(_ request: HTTPRequest) async throws(HTTPClientError) -> HTTPResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: Self.urlRequest(for: request))
        } catch {
            throw Self.failure(error, sending: request)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.log(.nonHTTPResponse, sending: request, detail: String(describing: response))
            throw .nonHTTPResponse
        }
        return HTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: Self.headers(of: httpResponse),
            body: data,
        )
    }
}
