import Foundation
import MyAppCore
import MyAppTestSupport
import Synchronization

/// A `URLProtocol` that plays the server for `URLSessionHTTPClient`'s tests, so they
/// exercise the real `URLSession` without touching the network.
///
/// The system instantiates the class per request, so its state is static: one route per
/// **host**, behind a `Mutex`. Every test registers a host of its own
/// (``uniqueHost()``), which is what keeps tests running in parallel apart — never a
/// single "current route".
final class StubURLProtocol: URLProtocol {
    /// How the stub answers a request for one host.
    enum Reply: Sendable {
        /// Answer as ``MyAppTestSupport/HTTPStubOutcome`` says, in `URLSession`'s terms.
        case outcome(HTTPStubOutcome)
        /// Fail with a `URLError` of this code — for the adapter's own mapping cases,
        /// which need codes no outcome names.
        case urlError(URLError.Code)
    }

    /// One host's reply, and every request that host has received, in order.
    struct Route: Sendable {
        var reply: Reply
        var received: [HTTPRequest] = []
    }

    /// The routes, keyed by host.
    static let routes = Mutex<[String: Route]>([:])

    /// A host no other test uses. `.invalid` is reserved (RFC 2606), so even a request
    /// that escaped the stub could not reach a real server.
    static func uniqueHost() -> String {
        "\(UUID().uuidString.lowercased()).contract.invalid"
    }

    /// Answers every later request for `host` with `reply`, and forgets what `host`
    /// received so far.
    static func register(host: String, reply: Reply) {
        routes.withLock { $0[host] = Route(reply: reply) }
    }

    /// What `host` has received, in order.
    static func received(host: String) -> [HTTPRequest] {
        routes.withLock { $0[host]?.received ?? [] }
    }

    /// A session that sends every request to this stub.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with _: URLRequest) -> Bool {
        // Only sessions built by `session()` list this class, so every request they make
        // is the stub's; a host with no route fails in `startLoading`.
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // MARK: - Recording

    /// `request` in Core's vocabulary, as the server received it.
    private static func recorded(_ request: URLRequest, url: URL) -> HTTPRequest {
        HTTPRequest(
            method: HTTPRequest.Method(rawValue: request.httpMethod ?? "GET") ?? .get,
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body(of: request),
            timeout: .seconds(request.timeoutInterval),
        )
    }

    /// The body `URLSession` sent. Inside a `URLProtocol` it arrives as
    /// `httpBodyStream`, not `httpBody`, so the stream is read to its end.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var body = Data()
        let chunkSize = 4_096
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: chunkSize)
            guard count > 0 else {
                break
            }
            body.append(buffer, count: count)
        }
        return body
    }

    // MARK: - Loading

    override func startLoading() {
        guard let url = request.url, let host = url.host() else {
            fail(with: .badURL)
            return
        }
        let recorded = Self.recorded(request, url: url)
        let reply = Self.routes.withLock { routes -> Reply? in
            routes[host]?.received.append(recorded)
            return routes[host]?.reply
        }
        switch reply {
        case .none:
            fail(with: .cannotFindHost)

        case let .urlError(code):
            fail(with: code)

        case let .outcome(.respond(response)):
            respond(with: response, to: url)

        case let .outcome(.fail(error)):
            fail(as: error, url: url)

        case .outcome(.hang):
            // Never answers: the request ends only when its task is cancelled and
            // `URLSession` calls `stopLoading()`.
            break
        }
    }

    override func stopLoading() {
        // Nothing is in flight to stop: every answer is delivered synchronously from
        // `startLoading()`, and a hang has nothing running.
    }

    // MARK: - Answering

    private func respond(with response: HTTPResponse, to url: URL) {
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers,
        ) else {
            fail(with: .cannotParseResponse)
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// Fails the way a real transport would for `error`.
    private func fail(as error: HTTPClientError, url: URL) {
        switch error {
        case .cancelled:
            fail(with: .cancelled)

        case .nonHTTPResponse:
            // A plain `URLResponse`, as a `file:` or `data:` URL would answer.
            let response = URLResponse(
                url: url,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil,
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)

        case .notConnected:
            fail(with: .notConnectedToInternet)

        case .timedOut:
            fail(with: .timedOut)

        case let .transport(code):
            fail(with: URLError.Code(rawValue: code))
        }
    }

    private func fail(with code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }
}
