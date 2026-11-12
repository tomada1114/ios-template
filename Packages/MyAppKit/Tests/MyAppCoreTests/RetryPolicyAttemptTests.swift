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
        #expect(run.error == .server(status: 504, retryAfter: nil))
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
        #expect(run.error == .server(status: 503, retryAfter: nil))
        #expect(run.requests.count == 1)
        #expect(run.sleeps.isEmpty)
    }

    // MARK: - What is retried

    @Test(arguments: [
        (HTTPStubOutcome.fail(.timedOut), APIError.timedOut),
        (.fail(.notConnected), .offline),
        (RetryPolicyFixture.status(500), .server(status: 500, retryAfter: nil)),
        (RetryPolicyFixture.status(502), .server(status: 502, retryAfter: nil)),
        (RetryPolicyFixture.status(503), .server(status: 503, retryAfter: nil)),
        (RetryPolicyFixture.status(504), .server(status: 504, retryAfter: nil)),
        (RetryPolicyFixture.status(429), .rateLimited(retryAfter: nil)),
    ])
    func `a timeout, no connection, a 500, 502, 503, or 504, and a 429 are retried`(
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
        // A 5xx that says the server will never do this, not that it cannot right now.
        (RetryPolicyFixture.status(501), .server(status: 501, retryAfter: nil)),
        (RetryPolicyFixture.status(505), .server(status: 505, retryAfter: nil)),
        (RetryPolicyFixture.status(599), .server(status: 599, retryAfter: nil)),
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

    @Test(arguments: [429, 503], [
        // Longer than the 1 s backoff, and honored.
        (["Retry-After": "3"], Duration.seconds(3)),
        // Exactly the policy's 5 s cap.
        (["retry-after": "5"], .seconds(5)),
        // 2 s after the pinned now.
        (["Retry-After": "Sun, 06 Nov 1994 08:49:39 GMT"], .seconds(2)),
        // Missing or unreadable: the policy's own backoff.
        ([:], .seconds(1)),
        (["Retry-After": "soon"], .seconds(1)),
    ])
    func `a 429 or a 503 waits exactly as long as its Retry-After asks`(
        statusCode: Int,
        retryAfter: (headers: [String: String], expected: Duration),
    ) async throws {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                RetryPolicyFixture.status(statusCode, headers: retryAfter.headers),
                .respond(RetryPolicyFixture.itemResponse),
            ],
            waits: 1,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.sleeps == [retryAfter.expected])
    }

    @Test(arguments: [
        (429, APIError.rateLimited(retryAfter: .seconds(120))),
        (503, .server(status: 503, retryAfter: .seconds(120))),
    ], [
        // 2 minutes, in either form the header allows, against a 5 s cap.
        ["retry-after": "120"],
        ["Retry-After": "Sun, 06 Nov 1994 08:51:37 GMT"],
    ])
    func `a 429 or a 503 whose Retry-After is longer than the cap is thrown at once, not retried early`(
        refusal: (statusCode: Int, expected: APIError),
        headers: [String: String],
    ) async {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                RetryPolicyFixture.status(refusal.statusCode, headers: headers),
                .respond(RetryPolicyFixture.itemResponse),
            ],
            waits: 0,
        )
        #expect(run.error == refusal.expected)
        #expect(run.requests.count == 1)
        #expect(run.sleeps.isEmpty)
    }

    @Test(arguments: [500, 502, 504])
    func `another transient 5xx ignores its Retry-After and backs off`(
        statusCode: Int,
    ) async throws {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                RetryPolicyFixture.status(statusCode, headers: ["Retry-After": "3"]),
                .respond(RetryPolicyFixture.itemResponse),
            ],
            waits: 1,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.sleeps == [.seconds(1)])
    }

    @Test
    func `a 503 in maintenance whose Retry-After is past the cap is thrown at once, not backed off`(
    ) async {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                RetryPolicyFixture.status(503, headers: ["Retry-After": "3600"]),
                .respond(RetryPolicyFixture.itemResponse),
            ],
            waits: 0,
        )
        #expect(run.error == .server(status: 503, retryAfter: .seconds(3_600)))
        #expect(run.requests.count == 1)
        #expect(run.sleeps.isEmpty)
    }

    @Test(arguments: [429, 503], [
        ["Retry-After": "0"],
        // A day before the pinned now: a date already past is a wait of zero.
        ["Retry-After": "Sat, 05 Nov 1994 08:49:37 GMT"],
    ])
    func `a Retry-After of zero or a date already past retries without waiting`(
        statusCode: Int,
        headers: [String: String],
    ) async throws {
        let run = await RetryPolicyFixture.run(
            RetryPolicyFixture.getItem,
            answering: [
                RetryPolicyFixture.status(statusCode, headers: headers),
                .respond(RetryPolicyFixture.itemResponse),
            ],
            waits: 0,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.requests.count == 2)
        #expect(run.sleeps == [.zero])
    }
}
