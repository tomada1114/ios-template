import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct RetryPolicyIdempotencyTests {
    @Test(arguments: [
        (HTTPRequest.Method.get, true),
        (.put, true),
        (.delete, true),
        (.post, false),
        (.patch, false),
    ])
    func `GET, PUT, and DELETE are idempotent; POST and PATCH are not`(
        method: HTTPRequest.Method,
        expected: Bool,
    ) {
        #expect(method.isIdempotent == expected)
    }

    @Test(arguments: [HTTPRequest.Method.post, .patch])
    func `a POST or a PATCH is not retried by default`(method: HTTPRequest.Method) async {
        let endpoint = Endpoint<RemoteItem>(method: method, path: "items")
        let run = await RetryPolicyFixture.run(
            endpoint,
            answering: [RetryPolicyFixture.status(503), .respond(RetryPolicyFixture.itemResponse)],
            waits: 0,
        )
        #expect(run.error == .server(status: 503))
        #expect(run.requests.count == 1)
        #expect(run.sleeps.isEmpty)
    }

    @Test(arguments: [HTTPRequest.Method.post, .patch])
    func `a POST or a PATCH whose endpoint opts in is retried`(
        method: HTTPRequest.Method,
    ) async throws {
        let endpoint = Endpoint<RemoteItem>(
            method: method,
            path: "items",
            headers: ["Idempotency-Key": "7d1f"],
            isSafeToRepeat: true,
        )
        let run = await RetryPolicyFixture.run(
            endpoint,
            answering: [RetryPolicyFixture.status(503), .respond(RetryPolicyFixture.itemResponse)],
            waits: 1,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.requests.map(\.method) == [method, method])
        #expect(run.sleeps == [.seconds(1)])
    }

    @Test(arguments: [HTTPRequest.Method.get, .put, .delete])
    func `an idempotent method is retried without opting in`(
        method: HTTPRequest.Method,
    ) async throws {
        let endpoint = Endpoint<RemoteItem>(method: method, path: "items/1")
        let run = await RetryPolicyFixture.run(
            endpoint,
            answering: [RetryPolicyFixture.status(503), .respond(RetryPolicyFixture.itemResponse)],
            waits: 1,
        )
        #expect(try run.result.get() == RetryPolicyFixture.item)
        #expect(run.requests.count == 2)
    }

    @Test
    func `a DELETE declared with no body is retried and then returns the empty response`(
    ) async throws {
        let endpoint = Endpoint<EmptyResponse>(method: .delete, path: "items/1")
        let run = await RetryPolicyFixture.run(
            endpoint,
            answering: [RetryPolicyFixture.status(503), RetryPolicyFixture.status(204)],
            waits: 1,
        )
        #expect(try run.result.get() == EmptyResponse())
        #expect(run.requests.map(\.method) == [.delete, .delete])
    }

    @Test
    func `an endpoint does not opt in unless it says so`() {
        #expect(!Endpoint<RemoteItem>(method: .post, path: "items").isSafeToRepeat)
    }
}
