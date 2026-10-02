import Foundation
import os

/// A JSON API, reached through an ``HTTPClient``: the Core service every networked
/// feature builds on, not a port of its own (`docs/architecture.md` › The HTTP client
/// port › A worked API service).
///
/// It turns an ``Endpoint`` into an ``HTTPRequest`` below one base URL, sends it, and
/// answers with the decoded 2xx body or a closed ``APIError`` — so a feature decides
/// about "offline", "signed out", and "slow down" once per case, and a test drives each
/// one through `FakeHTTPClient` without a network.
///
/// The JSON coders are configured here, once, for every call:
///
/// - **Dates are ISO 8601** (`2026-10-02T09:30:00Z`), both ways. A server that sends
///   fractional seconds needs its own `Date` decoding in that type's `init(from:)`.
/// - **Keys are used as the type spells them** (`useDefaultKeys`), both ways. A wire name
///   that differs from the Swift name — `created_at` for `createdAt` — is spelled in that
///   type's `CodingKeys`. Explicit beats converted: the mapping is visible in the type,
///   round-trips exactly, and cannot mangle an acronym (`convertFromSnakeCase` reads
///   `image_url` as `imageUrl`, never `imageURL`).
/// - **Encoded keys are sorted**, so the same body is the same bytes every time — a test
///   compares it to a literal, and a log or a cache key is stable.
///
/// Auth, retries, caching, and pagination are not here: each is its own service over
/// this one, or a decision in the feature that calls it.
public struct APIClient: Sendable {
    private static let jsonMediaType = "application/json"
    private static let acceptHeader = "Accept"
    private static let contentTypeHeader = "Content-Type"
    private static let retryAfterHeader = "Retry-After"

    private static let successCodes = 200 ..< 300
    private static let serverErrorCodes = 500 ..< 600
    private static let unauthorizedCode = 401
    private static let forbiddenCode = 403
    private static let notFoundCode = 404
    private static let tooManyRequestsCode = 429

    private let httpClient: any HTTPClient
    private let baseURL: URL
    private let now: @Sendable () -> Date
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// A client for the API at `baseURL`, sending through `httpClient`.
    ///
    /// - Parameters:
    ///   - httpClient: The transport — `URLSessionHTTPClient` in the app,
    ///     `FakeHTTPClient` in a test.
    ///   - baseURL: The URL every ``Endpoint/path`` is resolved below, such as
    ///     `https://api.example.com/v1`. The composition root decides it, so a staging
    ///     build points somewhere else without touching a feature.
    ///   - now: Today's date, read only to turn a `Retry-After` HTTP-date into a wait.
    ///     Injected so a test pins it (the `designing-core-logic` skill).
    public init(
        httpClient: any HTTPClient,
        baseURL: URL,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.now = now
        decoder = Self.makeDecoder()
        encoder = Self.makeEncoder()
    }

    /// The decoder every response goes through: ISO 8601 dates, keys as spelled.
    private static func makeDecoder() -> JSONDecoder {
        let configured = JSONDecoder()
        configured.dateDecodingStrategy = .iso8601
        configured.keyDecodingStrategy = .useDefaultKeys
        return configured
    }

    /// The encoder every body goes through: ISO 8601 dates, keys as spelled, sorted.
    private static func makeEncoder() -> JSONEncoder {
        let configured = JSONEncoder()
        configured.dateEncodingStrategy = .iso8601
        configured.keyEncodingStrategy = .useDefaultKeys
        configured.outputFormatting = [.sortedKeys]
        return configured
    }

    /// Sends `endpoint` and returns its 2xx body decoded as `Response`.
    ///
    /// Throws ``APIError/cancelled`` when the calling task is cancelled — which the
    /// caller treats as a no-op, not a failure — and another ``APIError`` case for every
    /// other way the call can end without a decoded body. A status the server sent is
    /// never retried here; that is the caller's decision, made on the case.
    public func send<Response>(
        _ endpoint: Endpoint<Response>,
    ) async throws(APIError) -> Response {
        let request = try makeRequest(for: endpoint)
        let response: HTTPResponse
        do {
            response = try await httpClient.send(request)
        } catch {
            throw apiError(for: error)
        }
        guard Self.successCodes.contains(response.statusCode) else {
            throw apiError(for: response)
        }
        do {
            return try decoder.decode(Response.self, from: response.body)
        } catch {
            // The type's name only: the body, and the decoder's description of it, can
            // quote user data.
            let typeName = String(describing: Response.self)
            AppLog.network.error("API response did not decode as \(typeName, privacy: .public)")
            throw .decoding
        }
    }

    private func makeRequest(
        for endpoint: Endpoint<some Decodable & Sendable>,
    ) throws(APIError) -> HTTPRequest {
        var url = baseURL.appending(path: endpoint.path)
        if !endpoint.queryItems.isEmpty {
            url.append(queryItems: endpoint.queryItems)
        }
        var headers = [Self.acceptHeader: Self.jsonMediaType]
        var body: Data?
        if let payload = endpoint.body {
            do {
                body = try encoder.encode(payload)
            } catch {
                let typeName = String(describing: type(of: payload))
                AppLog.network
                    .error("API request body \(typeName, privacy: .public) did not encode")
                throw .encoding
            }
            headers[Self.contentTypeHeader] = Self.jsonMediaType
        }
        for (name, value) in endpoint.headers {
            // HTTP field names are case-insensitive: `accept` replaces `Accept` rather
            // than sending both.
            headers = headers.filter { $0.key.caseInsensitiveCompare(name) != .orderedSame }
            headers[name] = value
        }
        return HTTPRequest(method: endpoint.method, url: url, headers: headers, body: body)
    }

    private func apiError(for response: HTTPResponse) -> APIError {
        let status = response.statusCode
        switch status {
        case Self.unauthorizedCode:
            return .unauthorized

        case Self.forbiddenCode:
            return .forbidden

        case Self.notFoundCode:
            return .notFound

        case Self.tooManyRequestsCode:
            let delay = headerValue(named: Self.retryAfterHeader, in: response)
                .flatMap { RetryAfter.delay(fromHeaderValue: $0, now: now()) }
            return .rateLimited(retryAfter: delay)

        case Self.serverErrorCodes:
            return .server(status: status)

        default:
            return .unexpectedStatus(status)
        }
    }

    private func apiError(for error: HTTPClientError) -> APIError {
        switch error {
        case .cancelled:
            .cancelled

        case .notConnected:
            .offline

        case .timedOut:
            .timedOut

        case .nonHTTPResponse, .transport:
            .transport
        }
    }

    /// `response`'s value for the header `name`, matched case-insensitively
    /// (``HTTPResponse/headers``: HTTP/2 names arrive lowercase).
    private func headerValue(named name: String, in response: HTTPResponse) -> String? {
        response.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
