# The HTTP client port and a worked API service

Networking is `URLSession` behind a Core `HTTPClient` port: first-party, so it costs no
dependency, and the port keeps decisions about status codes and failures in Core, where
tests see them. It is shaped like the repository port (`persisting-data`): a `Sendable`
port in `MyAppCore/Networking`, the `URLSessionHTTPClient` adapter in
`MyAppPlatform/Networking`, and `FakeHTTPClient` plus `HTTPClientContract` in
`Tests/MyAppTestSupport`.

```swift
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws(HTTPClientError) -> HTTPResponse
}
```

- **Status codes are data.** A 404 or a 503 comes back as an `HTTPResponse`, not an
  error, so the decision about it ("gone", "retry later", "show the server's message")
  stays in the Core service that made the request, where a test hands it the status and
  sees what it does. `isSuccess` answers the one question every caller asks first.
- **A closed error set.** `HTTPClientError` covers only the ways a request ends without a
  response: `cancelled`, `notConnected`, `timedOut`, `nonHTTPResponse`, and
  `transport(code:)` for the rest. The adapter maps each `URLError` code into one of
  them and logs the detail under `AppLog.network` — method and host `.public`, path and
  error text `.private` — because the framework's error text can quote a URL that
  carries user data. Cancellation is not a failure: it maps to `cancelled` and is not
  logged.
- **One contract, two runs, no network.** The contract takes a harness — something that
  makes a client whose server answers as told and reports what that server received —
  so it is written once over the port. `MyAppCoreTests` runs it against the fake, and
  against deliberately broken clients it must reject; `MyAppPlatformTests` runs it
  against `URLSessionHTTPClient` over a `URLProtocol` stub that answers on a `.invalid`
  host unique to each test. Both run under `just test` and in CI, and no test touches
  the real network.
- **Not wired yet.** No feature calls an API, so `App/` does not create a client. The
  first feature that needs one follows "A worked API service", below.

## A worked API service

`APIClient` in `MyAppCore/Networking` is the Core service every JSON API goes through —
not a port, since the transport is already behind one. A new remote API is therefore
never a new port: its calls are `Endpoint` values sent through an `APIClient`, and a Core
service over that client decides what each `APIError` case means for the feature, tested
against `FakeHTTPClient`.

A feature describes each call as an `Endpoint<Response>` value (method, path, query
items, an optional `Encodable` body, extra headers) and sends it; the client resolves the
path below its base URL, encodes, decodes, and answers with the 2xx body or a closed
`APIError`:

```swift
struct Item: Decodable, Sendable {
    var id: Int
    var title: String
    var createdAt: Date
}

enum ItemsAPI {
    static func item(id: Int) -> Endpoint<Item> {
        Endpoint(method: .get, path: "items/\(id)")
    }
}

func loadItem(using client: APIClient) async {
    do {
        let item = try await client.send(ItemsAPI.item(id: 42))
        // Show `item`.
    } catch .cancelled {
        // Not a failure: the caller no longer wants the answer.
    } catch {
        // `error` is an `APIError`: `.offline`, `.unauthorized`, `.rateLimited(retryAfter:)`…
    }
}
```

- **One set of coders.** The client configures its `JSONDecoder` and `JSONEncoder` once:
  ISO 8601 dates both ways, and keys as the type spells them (`useDefaultKeys`). A wire
  name that differs — `created_at` for `createdAt` — goes in that type's `CodingKeys`,
  where the mapping is visible and exact; `convertFromSnakeCase` would read `image_url`
  as `imageUrl`, never `imageURL`. Encoded keys are sorted, so a body is the same bytes
  every time and a test compares it with a literal.
- **Every outcome is a case.** 401, 403, 404, and 429 have cases of their own; a 5xx is
  `server(status:)`, any other status `unexpectedStatus(_:)`. A body that does not decode
  is `decoding` — logged under `AppLog.network` by the response type's name, never the
  body — and one that cannot be encoded is `encoding`, sent nowhere. `HTTPClientError`
  maps across: `notConnected` to `offline`, `timedOut`, `cancelled`, and the rest to
  `transport`. A 429's `Retry-After` is read as delta-seconds or an HTTP-date, the date
  measured from the `now` the client is handed so a test pins it.
- **Cancellation is a no-op.** A cancelled task ends the call with `cancelled`, which the
  caller drops quietly, as it would the port's own `cancelled`.
- **Wiring.** The composition root makes the client —
  `APIClient(httpClient: URLSessionHTTPClient(), baseURL: …)` — and hands it to the Core
  services it builds; a test makes one over `FakeHTTPClient` (`APIClientTests`).
  Auth, retries, caching, and pagination are services or decisions over this one, not
  options inside it.
