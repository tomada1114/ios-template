import Synchronization

/// A `Clock` whose time moves only when a test says so: the test double for every Core
/// type that waits on an injected `any Clock<Duration>` (`.claude/rules/core.md` ›
/// Inject what Core would read from the world).
///
/// A sleeping task stays suspended until ``advance(by:)`` carries ``now`` to its
/// deadline, so a test of a backoff, a debounce, or a timeout takes no real time:
/// ``nextSleep()`` waits — on a continuation, never by polling — until the code under
/// test is parked in a sleep, which is the moment to advance past it or to cancel it.
/// The standard library ships no such clock, and it lives under `Tests/` because no
/// shipped code may wait on anything but a real one.
///
/// A final class over a `Mutex`, like ``InMemoryPreferences``: `Clock.now` is
/// synchronous, which an actor could not answer.
package final class ManualClock: Clock, Sendable {
    /// A point on this clock's timeline: how far ``advance(by:)`` has moved it from zero.
    package struct Instant: InstantProtocol {
        /// The time advanced since the clock was made.
        package var offset: Duration

        package static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }

        package func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        package func duration(to other: Self) -> Duration {
            other.offset - offset
        }
    }

    /// What a `sleep` call does once it holds its continuation.
    private enum Parking {
        /// The task was cancelled before it could park: the sleep throws.
        case cancelled
        /// The deadline is not in the future: the sleep returns at once.
        case due
        /// The task is parked; these callers of ``nextSleep()`` were waiting for that.
        case parked(watchers: [CheckedContinuation<Duration, Never>], remaining: Duration)
    }

    private struct Sleeper {
        var deadline: Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var lastSleepID = 0
        var sleepers: [Int: Sleeper] = [:]
        /// Sleeps that have an identifier but have not reached `park` yet. Every one
        /// leaves when it parks, so the set is empty whenever nothing is mid-call.
        var notYetParked: Set<Int> = []
        /// The members of `notYetParked` whose task was cancelled meanwhile. `park`
        /// removes each one it finds, so this set drains too.
        var cancelledBeforeParking: Set<Int> = []
        var watchers: [CheckedContinuation<Duration, Never>] = []
        var sleeps: [Duration] = []
    }

    private let state = Mutex(State())

    /// The current instant: zero until ``advance(by:)`` moves it.
    package var now: Instant {
        state.withLock(\.now)
    }

    /// Exact: an instant is whatever the test advanced to.
    package var minimumResolution: Duration {
        .zero
    }

    /// How long each sleep so far asked to wait, in the order they were asked — the
    /// record a test compares with the waits it expects. A sleep made from an
    /// already-cancelled task is not recorded: it never waited.
    package var sleeps: [Duration] {
        state.withLock(\.sleeps)
    }

    /// Starts at instant zero with nobody asleep.
    package init() {
        // Nothing asleep and no time passed: the stored defaults are the whole state.
    }

    /// Suspends until ``advance(by:)`` reaches `deadline`, or throws `CancellationError`
    /// as soon as the calling task is cancelled — promptly, as a real clock's sleep does.
    /// A deadline that is not in the future returns at once and parks nothing.
    package func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        let id = state.withLock { state in
            state.lastSleepID += 1
            state.notYetParked.insert(state.lastSleepID)
            return state.lastSleepID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                switch park(Sleeper(deadline: deadline, continuation: continuation), id: id) {
                case .cancelled:
                    continuation.resume(throwing: CancellationError())

                case .due:
                    continuation.resume()

                case let .parked(watchers, remaining):
                    for watcher in watchers {
                        watcher.resume(returning: remaining)
                    }
                }
            }
        } onCancel: {
            let parked = state.withLock { state in
                if let sleeper = state.sleepers.removeValue(forKey: id) {
                    return sleeper.continuation as CheckedContinuation<Void, any Error>?
                }
                if state.notYetParked.contains(id) {
                    // Cancelled before the sleep parked: `park` finds this and throws.
                    state.cancelledBeforeParking.insert(id)
                }
                // Otherwise the sleep already ended — woken by `advance(by:)`, or due
                // when it parked — and there is nothing left to cancel or to remember.
                return nil
            }
            parked?.resume(throwing: CancellationError())
        }
    }

    /// Moves ``now`` forward by `duration` and wakes every sleep whose deadline that
    /// reaches.
    package func advance(by duration: Duration) {
        let woken = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys {
                state.sleepers[id] = nil
            }
            return due.values.map(\.continuation)
        }
        for continuation in woken {
            continuation.resume()
        }
    }

    /// Waits until a task is parked in a sleep, then returns how long that sleep still
    /// has to wait — the earliest one, when several are parked. Returns at once when one
    /// already is. It never returns when nothing ever sleeps, so a suite that calls it
    /// carries a `.timeLimit`.
    package func nextSleep() async -> Duration {
        await withCheckedContinuation { continuation in
            let remaining = state.withLock { state in
                guard let earliest = state.sleepers.values.map(\.deadline).min() else {
                    state.watchers.append(continuation)
                    return nil as Duration?
                }
                return state.now.duration(to: earliest)
            }
            if let remaining {
                continuation.resume(returning: remaining)
            }
        }
    }

    private func park(_ sleeper: Sleeper, id: Int) -> Parking {
        state.withLock { state in
            state.notYetParked.remove(id)
            if state.cancelledBeforeParking.remove(id) != nil {
                return .cancelled
            }
            let remaining = state.now.duration(to: sleeper.deadline)
            state.sleeps.append(remaining)
            guard remaining > .zero else {
                return .due
            }
            state.sleepers[id] = sleeper
            let watchers = state.watchers
            state.watchers = []
            return .parked(watchers: watchers, remaining: remaining)
        }
    }
}
