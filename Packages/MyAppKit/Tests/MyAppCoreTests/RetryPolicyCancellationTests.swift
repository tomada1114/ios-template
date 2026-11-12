import MyAppCore
import MyAppTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct RetryPolicyCancellationTests {
    @Test
    func `cancelling during a backoff wait throws cancelled promptly, without another attempt`(
    ) async {
        let fake = FakeHTTPClient()
        await fake.enqueue(RetryPolicyFixture.status(503))
        await fake.enqueue(.respond(RetryPolicyFixture.itemResponse))
        let clock = ManualClock()
        let client = RetryPolicyFixture.client(over: fake, clock: clock)
        let sending = Task {
            try await client.send(RetryPolicyFixture.getItem)
        }

        // Parked in the 1 s wait. The clock is never advanced: only the cancellation
        // can end the call.
        #expect(await clock.nextSleep() == .seconds(1))
        sending.cancel()

        await #expect(throws: APIError.cancelled) {
            try await sending.value
        }
        #expect(await fake.requests.count == 1)
        #expect(clock.now.offset == .zero)
    }

    @Test
    func `cancelling while a request is in flight throws cancelled and waits for nothing`() async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.hang)
        await fake.enqueue(.respond(RetryPolicyFixture.itemResponse))
        let clock = ManualClock()
        let client = RetryPolicyFixture.client(over: fake, clock: clock)
        let sending = Task {
            try await client.send(RetryPolicyFixture.getItem)
        }
        // Until the request has reached the server: yielding, not sleeping, so the
        // cancellation below always lands on a request in flight.
        while await fake.requests.isEmpty {
            await Task.yield()
        }
        sending.cancel()

        await #expect(throws: APIError.cancelled) {
            try await sending.value
        }
        #expect(clock.sleeps.isEmpty)
        #expect(await fake.requests.count == 1)
    }

    @Test
    func `a task already cancelled sends nothing`() async {
        let fake = FakeHTTPClient()
        await fake.enqueue(.respond(RetryPolicyFixture.itemResponse))
        let clock = ManualClock()
        let client = RetryPolicyFixture.client(over: fake, clock: clock)
        let sending = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.send(RetryPolicyFixture.getItem)
        }

        await #expect(throws: APIError.cancelled) {
            try await sending.value
        }
        #expect(await fake.requests.isEmpty)
        #expect(clock.sleeps.isEmpty)
    }

    @Test
    func `a cancelled wait is not recorded as a failure the next call inherits`() async throws {
        let fake = FakeHTTPClient()
        await fake.enqueue(RetryPolicyFixture.status(503))
        await fake.enqueue(.respond(RetryPolicyFixture.itemResponse))
        let clock = ManualClock()
        let client = RetryPolicyFixture.client(over: fake, clock: clock)
        let cancelled = Task {
            try await client.send(RetryPolicyFixture.getItem)
        }
        _ = await clock.nextSleep()
        cancelled.cancel()
        _ = await cancelled.result

        // The same client, afterwards: a first attempt, not the cancelled call's second.
        #expect(try await client.send(RetryPolicyFixture.getItem) == RetryPolicyFixture.item)
        #expect(clock.sleeps == [.seconds(1)])
    }
}
