import MyAppCore
import MyAppTestSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct RetryPolicyTests {
    /// How far a jittered wait may sit from its hand-worked value: `Duration` times a
    /// `Double` is not exact to the attosecond.
    private static let tolerance: Duration = .microseconds(1)

    private static func isClose(_ actual: Duration, to expected: Duration) -> Bool {
        (expected - tolerance ... expected + tolerance).contains(actual)
    }

    // MARK: - Tuning

    @Test
    func `the default tuning retries twice, from half a second, doubling, up to 30 seconds`() {
        let expected = RetryPolicy(
            maxAttempts: 3,
            baseDelay: .milliseconds(500),
            multiplier: 2,
            jitter: 0.5,
            maxDelay: .seconds(30),
        )
        #expect(Tuning.default == Tuning(retry: expected))
        #expect(Tuning.default.retry == expected)
    }

    @Test
    func `a retrying client made without a tuning follows the default policy`() async {
        let fake = FakeHTTPClient()
        for _ in 0 ..< 4 {
            await fake.enqueue(RetryPolicyFixture.status(503))
        }
        let clock = ManualClock()
        let client = RetryingAPIClient(
            client: APIClientFixture.client(over: fake),
            clock: clock,
            generator: ConstantGenerator.lowest,
        )
        let sending = Task {
            try await client.send(RetryPolicyFixture.getItem)
        }
        for _ in 0 ..< 2 {
            await clock.advance(by: clock.nextSleep())
        }
        await #expect(throws: APIError.server(status: 503)) {
            try await sending.value
        }
        #expect(await fake.requests.count == 3)
        #expect(clock.sleeps == [.milliseconds(500), .seconds(1)])
    }

    // MARK: - The backoff sequence

    @Test(arguments: [
        (1, Duration.seconds(1)),
        (2, .seconds(2)),
        (3, .seconds(4)),
        // 8 s, then 16 s, uncapped: both stop at the 5 s cap.
        (4, .seconds(5)),
        (5, .seconds(5)),
        (60, .seconds(5)),
        // Before the first attempt there is nothing to back off from.
        (0, .seconds(1)),
    ])
    func `without jitter the wait doubles from the base delay up to the cap`(
        attempt: Int,
        expected: Duration,
    ) {
        var generator = SplitMix64(seed: 0)
        let delay = RetryPolicyFixture.policy.delay(afterAttempt: attempt, using: &generator)
        #expect(delay == expected)
    }

    @Test
    func `without jitter nothing is drawn from the generator`() {
        var generator = SplitMix64(seed: 0)
        _ = RetryPolicyFixture.policy.delay(afterAttempt: 1, using: &generator)
        var untouched = SplitMix64(seed: 0)
        #expect(generator.next() == untouched.next())
    }

    @Test(arguments: [
        // Half jitter spreads a 2 s wait over 1 s...2 s.
        (0.5, ConstantGenerator.lowest, Duration.seconds(2)),
        (0.5, ConstantGenerator.highest, .seconds(1)),
        // Full jitter spreads it over 0 s...2 s.
        (1, ConstantGenerator.lowest, .seconds(2)),
        (1, ConstantGenerator.highest, .zero),
        // A jitter outside 0...1 is read as the nearest bound, never a negative wait
        // or one past the backoff.
        (3, ConstantGenerator.highest, .zero),
        (-1, ConstantGenerator.highest, .seconds(2)),
    ])
    func `jitter only shortens a wait, by at most its fraction`(
        jitter: Double,
        generator: ConstantGenerator,
        expected: Duration,
    ) {
        var policy = RetryPolicyFixture.policy
        policy.jitter = jitter
        var generator = generator
        let delay = policy.delay(afterAttempt: 2, using: &generator)
        #expect(Self.isClose(delay, to: expected), "\(delay) is not \(expected)")
    }

    @Test
    func `a seeded generator draws the same jittered backoff sequence every time`() {
        var policy = RetryPolicyFixture.policy
        policy.jitter = 0.5
        policy.maxDelay = .seconds(30)
        // SplitMix64 seeded with 0 draws the unit values 0.0205352…, 0.7693379…,
        // 0.1363642…, and 0.3662912…; each wait is its backoff (1, 2, 4, 8 s) less half
        // of that fraction of it.
        let expected: [Duration] = [
            .nanoseconds(989_732_389),
            .nanoseconds(1_230_662_045),
            .nanoseconds(3_727_271_557),
            .nanoseconds(6_534_834_964),
        ]
        var generator = SplitMix64(seed: 0)
        let delays = (1 ... 4).map { policy.delay(afterAttempt: $0, using: &generator) }
        for (delay, wanted) in zip(delays, expected) {
            #expect(Self.isClose(delay, to: wanted), "\(delay) is not \(wanted)")
        }
        #expect(delays.count == expected.count)

        var sameSeed = SplitMix64(seed: 0)
        #expect(delays == (1 ... 4).map { policy.delay(afterAttempt: $0, using: &sameSeed) })
        var otherSeed = SplitMix64(seed: 1)
        #expect(delays != (1 ... 4).map { policy.delay(afterAttempt: $0, using: &otherSeed) })
    }

    // MARK: - Retry-After

    @Test(arguments: [
        // Longer or shorter than the backoff (1 s): the server's wait wins either way.
        (Duration.seconds(3), Duration.seconds(3)),
        (.milliseconds(250), .milliseconds(250)),
        (.zero, .zero),
        // At the cap, and past it.
        (.seconds(5), .seconds(5)),
        (.seconds(120), .seconds(5)),
    ])
    func `a Retry-After is waited out exactly, up to the cap`(
        retryAfter: Duration,
        expected: Duration,
    ) {
        #expect(RetryPolicyFixture.policy.delay(honoring: retryAfter) == expected)
    }

    // MARK: - The generator

    @Test
    func `the seeded generator draws the published SplitMix64 sequence for seed 0`() {
        var generator = SplitMix64(seed: 0)
        let drawn = (0 ..< 3).map { _ in generator.next() }
        #expect(drawn == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F])
    }
}
