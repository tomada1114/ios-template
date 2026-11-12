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
- **Wired, not yet called.** `App/` builds one `APIClient` over `URLSessionHTTPClient`
  at launch, at the base URL this build's `AppConfiguration` names (below). No feature
  calls an API yet, so nothing reads it; the first feature that needs one follows "A
  worked API service", below.

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
  `server(status:retryAfter:)`, any other status `unexpectedStatus(_:)`. A 2xx body that does not
  decode as the declared type, an empty one included, is `decoding` — logged under `AppLog.network` by the response type's name, never the
  body — and one that cannot be encoded is `encoding`, sent nowhere. `HTTPClientError`
  maps across: `notConnected` to `offline`, `timedOut`, `cancelled`, and the rest to
  `transport`. A 429's or a 503's `Retry-After` is read as delta-seconds or an
  HTTP-date, the date measured from the `now` the client is handed so a test pins it;
  another 5xx's is not read, since only a 503 says the server will be back after a wait.
- **A 2xx with no body is `Endpoint<EmptyResponse>`.** A call that succeeds with nothing
  to read — a `204 No Content`, the bodiless `200` of many `DELETE` and `PUT`
  endpoints — declares `EmptyResponse` as its response type. The client decides by that
  type and never decodes: any 2xx returns `EmptyResponse()`, whatever the body —
  empty, whitespace, JSON, or text — so a server that later adds a body does not break
  the call. For any other type, `decoding` means the 2xx body, an empty one included,
  did not decode as the declared type, so a feature never catches it as success.
- **Cancellation is a no-op.** A cancelled task ends the call with `cancelled`, which the
  caller drops quietly, as it would the port's own `cancelled`.
- **Wiring.** The composition root makes the client once —
  `APIClient(httpClient: URLSessionHTTPClient(), baseURL: configuration.apiBaseURL)`,
  `MyAppApp.makeAPIClient()` — and the first networked feature hands it to `AppModel` as
  a new initializer parameter, which builds the feature's Core service over it; a test
  makes one over `FakeHTTPClient` (`APIClientTests`).
- **The base URL is per build.** `API_BASE_URL` in `Config/Debug.xcconfig` (staging) and
  `Config/Release.xcconfig` (production) reaches `Info.plist` under
  `AppConfiguration.apiBaseURLKey`; `AppConfiguration(infoDictionary:)` parses it and
  throws `missing` or `malformed`, and `App/` stops the launch on either, since only a
  broken build produces one. How to write the value — the `//` escape, `.invalid`
  placeholders, no secrets — is `.claude/rules/project.md` › Per-configuration values.
  Retries are `RetryingAPIClient`, below; auth, caching, and pagination are services or
  decisions over this one, not options inside it.

## Retrying a call

`RetryingAPIClient` in `MyAppCore/Networking` sends an `Endpoint` through an `APIClient`
and tries a failed call again. A feature that wants retries is handed one instead of the
bare client — `RetryingAPIClient(client: apiClient)` — and calls the same `send(_:)`.

- **A wrapper over `APIClient`, not a decorator over the port.** Every fact a retry is
  decided on already exists one level up: `APIError` has sorted the failure, it carries
  the `Retry-After` wait already parsed, and the `Endpoint` says whether the call may be
  repeated. A retrying `HTTPClient` would re-read statuses and headers the client reads
  anyway, and need a retry flag on `HTTPRequest`, which describes only what the server
  receives. The port stays one request in, one response out.
- **What is retried.** `timedOut`, `offline`, `rateLimited(retryAfter:)`, and
  `server(status:retryAfter:)` for a 500, 502, 503, or 504: failures that describe the
  moment, not the request. Every other case is thrown at once — a 501, a 505, and any other 5xx
  included, since they say the server will not do this at all. The switch over
  `APIError` is exhaustive, so a new case must be sorted before it compiles.
- **How long it waits.** A 429's or a 503's `Retry-After` exactly; otherwise
  `baseDelay` multiplied once per earlier retry, held to `maxDelay`, then shortened by a
  random share of `jitter`. Jitter only shortens, so the cap always holds. A `Retry-After`
  longer than `maxDelay` is never shortened to fit — coming back early would only be
  refused again — so that 429 or 503 is thrown at once and the feature shows it. A
  policy with a negative delay, or a multiplier that is not a finite number of at least 1,
  still waits within zero through `maxDelay`.
- **A non-idempotent call is sent once.** `POST` and `PATCH`
  (`HTTPRequest.Method.isIdempotent`) are not repeated — a timed-out `POST` may have
  arrived — unless the endpoint is declared with `isSafeToRepeat: true`, which only the
  feature that knows the server deduplicates it (an idempotency key) can say.
- **A repeat can get a different answer.** Idempotent means the server ends in the same
  state, not that it answers the same way. When a `DELETE` or a `PUT` arrived and only
  its response was lost, the retry meets what the first attempt left: a repeated
  `DELETE` can answer 404 (`notFound`), a repeated conditional or create-style `PUT` a
  409 or 412 (`unexpectedStatus`). Neither is retried, so the feature sees it. A
  feature that deletes through this client treats `notFound` as done, not as a failure,
  and one that sends such a `PUT` re-reads the resource before reporting a conflict.
- **Cancellation ends it.** `cancelled` is never retried, and a task cancelled during a
  backoff wait gets `cancelled` at once rather than after the wait.
- **What it logs.** One `.debug` line per retry under `AppLog.network`: the attempt, the
  `APIError` case, and the wait, all `.public` — never a URL or a body.
- **Tunables and tests.** The numbers are `Tuning.default.retry`, a `RetryPolicy`: three
  attempts, from half a second, doubling, half jitter, a 30-second cap. The client takes
  a `Tuning`, an `any Clock<Duration>`, and a generator, so the `RetryPolicy…Tests`
  suites hand it `ManualClock` and `SplitMix64` (`Tests/MyAppTestSupport`) and assert
  every wait without one passing (`.claude/rules/core.md` › Inject what Core would read
  from the world).
