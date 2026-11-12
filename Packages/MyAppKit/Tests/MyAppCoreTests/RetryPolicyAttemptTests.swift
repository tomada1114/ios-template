import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct RetryPolicyAttemptTests {
    // MARK: - The attempt count

    @Test
    func `a call that keeps failing is sent max attempts times, then throws the last error`() async {
        let outcomes = [503, 502, 500, 504].map { RetryPolicyFixture.status($0) }
            // Never reached: the fourth attempt is the last.
            + [.respond(RetryPolicyFixture.itemResponse)]
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: outcomes,
            waits: 3,
        )
        #expect(run.error == .server(status: 504))
        #expect(run.requests.count == 4)
        #expect(run.sleeps == [.seconds(1), .seconds(2), .seconds(4)])
    }

    @Test
    func `a retry that succeeds returns the response and stops`() async throws {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                .fail(.timedOut),
                .respond(RetryPolicyFixture.itemResponse),
                RetryPolicyFixture.status(503),
            ],
            waits: 1,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.sleeps == [.seconds(1)])
        let first = try #require(run.requests.first)
        #expect(run.requests == [first, first])
    }

    @Test
    func `a first attempt that succeeds waits for nothing`() async throws {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [.respond(RetryPolicyFixture.itemResponse)],
            waits: 0,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.requests.count == 1)
        #expect(run.sleeps.isEmpty)
    }

    @Test(arguments: [1, 0, -3])
    func `a policy of one attempt or fewer sends once and never retries`(maxAttempts: Int) async {
        var policy = RetryPolicyFixture.policy
        policy.maxAttempts = maxAttempts
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [RetryPolicyFixture.status(503), .respond(RetryPolicyFixture.itemResponse)],
            waits: 0,
            policy: policy,
        )
        #expect(run.error == .server(status: 503))
        #expect(run.requests.count == 1)
        #expect(run.sleeps.isEmpty)
    }

    // MARK: - What is retried

    @Test(arguments: [
        (HTTPStubOutcome.fail(.timedOut), APIError.timedOut),
        (.fail(.notConnected), .offline),
        (RetryPolicyFixture.status(500), .server(status: 500)),
        (RetryPolicyFixture.status(503), .server(status: 503)),
        (RetryPolicyFixture.status(599), .server(status: 599)),
        (RetryPolicyFixture.status(429), .rateLimited(retryAfter: nil)),
    ])
    func `a timeout, no connection, a 5xx, and a 429 are retried`(
        outcome: HTTPStubOutcome,
        expected: APIError,
    ) async {
        var policy = RetryPolicyFixture.policy
        policy.maxAttempts = 2
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [outcome, outcome],
            waits: 1,
            policy: policy,
        )
        #expect(run.error == expected)
        #expect(run.requests.count == 2)
        #expect(run.sleeps == [.seconds(1)])
    }

    @Test(arguments: [
        (HTTPStubOutcome.fail(.transport(code: -1_200)), APIError.transport),
        (.fail(.nonHTTPResponse), .transport),
        (RetryPolicyFixture.status(400), .unexpectedStatus(400)),
        (RetryPolicyFixture.status(401), .unauthorized),
        (RetryPolicyFixture.status(403), .forbidden),
        (RetryPolicyFixture.status(404), .notFound),
        // A 2xx whose (empty) body is not an item.
        (RetryPolicyFixture.status(200), .decoding),
    ])
    func `any other failure is thrown at once, without a retry`(
        outcome: HTTPStubOutcome,
        expected: APIError,
    ) async {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [outcome, .respond(RetryPolicyFixture.itemResponse)],
            waits: 0,
        )
        #expect(run.error == expected)
        #expect(run.requests.count == 1)
        #expect(run.sleeps.isEmpty)
    }

    @Test
    func `a body that cannot be encoded is thrown at once and nothing is sent`() async {
        let endpoint = Endpoint<RemoteItem>(method: .put, path: "items/1", body: UnencodableBody())
        let run = await RetryPolicyFixture.run(
            endpoint,
            answering: [.respond(RetryPolicyFixture.itemResponse)],
            waits: 0,
        )
        #expect(run.error == .encoding)
        #expect(run.requests.isEmpty)
        #expect(run.sleeps.isEmpty)
    }

    // MARK: - Retry-After

    @Test(arguments: [
        // Longer than the 1 s backoff, and honored.
        (["Retry-After": "3"], Duration.seconds(3)),
        // 2 minutes, in either form the header allows: capped at the policy's 5 s.
        (["retry-after": "120"], .seconds(5)),
        (["Retry-After": "Sun, 06 Nov 1994 08:51:37 GMT"], .seconds(5)),
        // 2 s after the pinned now.
        (["Retry-After": "Sun, 06 Nov 1994 08:49:39 GMT"], .seconds(2)),
        // Missing or unreadable: the policy's own backoff.
        ([:], .seconds(1)),
        (["Retry-After": "soon"], .seconds(1)),
    ])
    func `a 429 waits as long as its Retry-After asks, up to the cap`(
        headers: [String: String],
        expected: Duration,
    ) async throws {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                RetryPolicyFixture.status(429, headers: headers),
                .respond(RetryPolicyFixture.itemResponse),
            ],
            waits: 1,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.sleeps == [expected])
    }

    @Test
    func `a Retry-After of zero retries without waiting`() async throws {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                RetryPolicyFixture.status(429, headers: ["Retry-After": "0"]),
                .respond(RetryPolicyFixture.itemResponse),
            ],
            waits: 0,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.requests.count == 2)
        #expect(run.sleeps == [.zero])
    }
}
