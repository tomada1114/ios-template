import Foundation
import MyAppCore
import MyAppTestSupport

/// A generator that draws the same bits every time: the two ends of a jitter range, by
/// hand, where a seeded generator's draw would need the formula to predict.
struct ConstantGenerator: RandomNumberGenerator, Sendable {
    /// Every bit clear: the lowest unit draw, exactly 0.
    static let lowest = Self(bits: .min)
    /// Every bit set: the highest unit draw, a hair below 1.
    static let highest = Self(bits: .max)

    var bits: UInt64

    func next() -> UInt64 {
        bits
    }
}

/// What one retried call did: how it ended, what reached the server, and how long
/// it waited between attempts.
struct RetriedCall<Response: Decodable & Sendable>: Sendable {
    var result: Result<Response, APIError>
    var requests: [HTTPRequest]
    var sleeps: [Duration]

    /// The error the call ended in, or `nil` when it returned a response.
    var error: APIError? {
        switch result {
        case .success:
            nil

        case let .failure(error):
            error
        }
    }
}

/// Shared values and builders for the `RetryPolicy` suites.
enum RetryPolicyFixture {
    /// Four attempts waiting 1 s, 2 s, then 4 s, with no jitter and a 5 s cap: every
    /// wait is a whole number a test writes down by hand.
    static let policy = RetryPolicy(
        maxAttempts: maxAttempts,
        baseDelay: .seconds(1),
        multiplier: multiplier,
        jitter: 0,
        maxDelay: .seconds(maxDelaySeconds),
    )

    private static let maxAttempts = 4
    private static let multiplier = 2.0
    private static let maxDelaySeconds = 5
    private static let okStatus = 200

    /// An idempotent call, so only its outcome decides whether it is retried.
    static let getItem = Endpoint<RemoteItem>(method: .get, path: "items/1")

    /// The item ``itemResponse`` carries.
    static let item = RemoteItem(id: 1, title: "Milk", createdAt: APIClientFixture.now)

    /// A 200 whose body decodes as ``item``.
    static let itemResponse = APIClientFixture.response(
        okStatus,
        headers: [:],
        body: #"{"id":1,"title":"Milk","createdAt":"\#(APIClientFixture.nowISO8601)"}"#,
    )

    /// A response with `statusCode`, no headers, and no body.
    static func status(_ statusCode: Int) -> HTTPStubOutcome {
        status(statusCode, headers: [:])
    }

    /// A response with `statusCode`, `headers`, and no body.
    static func status(_ statusCode: Int, headers: [String: String]) -> HTTPStubOutcome {
        .respond(APIClientFixture.response(statusCode, headers: headers, body: ""))
    }

    /// A retrying client over `fake` that waits on `clock`, with ``policy`` and a seeded
    /// generator.
    static func client(over fake: FakeHTTPClient, clock: ManualClock) -> RetryingAPIClient {
        client(over: fake, clock: clock, policy: policy)
    }

    /// A retrying client over `fake` that waits on `clock`, with `policy` and a seeded
    /// generator.
    static func client(
        over fake: FakeHTTPClient,
        clock: ManualClock,
        policy: RetryPolicy,
    ) -> RetryingAPIClient {
        RetryingAPIClient(
            client: APIClientFixture.client(over: fake),
            tuning: Tuning(retry: policy),
            clock: clock,
            generator: SplitMix64(seed: 0),
        )
    }

    /// Queues `outcomes` on a new fake, sends `endpoint` through a retrying client over
    /// it, and carries `clock` through `waits` backoff waits — each as soon as the
    /// client is parked in it, with no real time passing.
    static func run<Response>(
        _ endpoint: Endpoint<Response>,
        answering outcomes: [HTTPStubOutcome],
        waits: Int,
    ) async -> RetriedCall<Response> {
        await run(endpoint, answering: outcomes, waits: waits, policy: policy)
    }

    /// ``run(_:answering:waits:)`` under `policy` rather than the fixture's own.
    static func run<Response>(
        _ endpoint: Endpoint<Response>,
        answering outcomes: [HTTPStubOutcome],
        waits: Int,
        policy: RetryPolicy,
    ) async -> RetriedCall<Response> {
        let fake = FakeHTTPClient()
        for outcome in outcomes {
            await fake.enqueue(outcome)
        }
        let clock = ManualClock()
        let client = client(over: fake, clock: clock, policy: policy)
        let sending = Task {
            await result(of: endpoint, sentThrough: client)
        }
        for _ in 0 ..< waits {
            await clock.advance(by: clock.nextSleep())
        }
        return await RetriedCall(
            result: sending.value,
            requests: fake.requests,
            sleeps: clock.sleeps,
        )
    }

    /// How sending `endpoint` ended, as a value. A function rather than a closure: only
    /// here does a `catch` see the typed `APIError`.
    private static func result<Response>(
        of endpoint: Endpoint<Response>,
        sentThrough client: RetryingAPIClient,
    ) async -> Result<Response, APIError> {
        do {
            return try await .success(client.send(endpoint))
        } catch {
            return .failure(error)
        }
    }
}
