#if DEBUG
    /// Where ``UpdateFailingTodoRepository`` holds each failing save until something
    /// outside the app says the failure may arrive: each ``release()`` lets one held
    /// failure through.
    ///
    /// Debug-only, for `LaunchUITests`: the test releases a failure once it has seen the
    /// screen it wants the failure to land on, such as the About sheet settled. A fixed
    /// delay instead held only while the test's taps took less than the delay, which a
    /// loaded simulator broke (#141). A release that comes before any failure waits is
    /// kept for the next one, so the test need not know whether the save reached the
    /// gate yet.
    public actor FailedUpdateGate {
        private var releases = 0
        private var lastHoldID = 0
        /// Each held failure's continuation resumes with `true` when a release lets it
        /// through, and `false` when its task's cancellation does.
        private var held: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
        private var holdWatchers: [CheckedContinuation<Void, Never>] = []

        /// Creates a gate holding nothing.
        public init() {
            // Every stored property starts empty: no release, nothing held.
        }

        /// Lets one failure through: the one held longest, or, when none is held, the next
        /// one to arrive.
        public func release() {
            if held.isEmpty {
                releases += 1
            } else {
                held.removeFirst().continuation.resume(returning: true)
            }
        }

        /// Returns once a release lets this failure through, or at once when the calling
        /// task is cancelled, now or while it waits; a cancelled failure uses no release.
        func hold() async {
            guard !Task.isCancelled else {
                return
            }
            if releases > 0 {
                releases -= 1
                return
            }
            lastHoldID += 1
            let id = lastHoldID
            let released = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(returning: false)
                        return
                    }
                    held.append((id, continuation))
                    let watchers = holdWatchers
                    holdWatchers = []
                    for watcher in watchers {
                        watcher.resume()
                    }
                }
            } onCancel: {
                Task { await self.stopHolding(id) }
            }
            // The cancellation reaches this actor in a task of its own, so a release can
            // get here first and let the cancelled failure through: hand it on.
            if released, Task.isCancelled {
                release()
            }
        }

        /// Waits until a failure is held; returns at once when one already is. It never
        /// returns when nothing is ever held, so a suite that calls it carries a
        /// `.timeLimit`.
        package func nextHold() async {
            guard held.isEmpty else {
                return
            }
            await withCheckedContinuation { holdWatchers.append($0) }
        }

        private func stopHolding(_ id: Int) {
            guard let index = held.firstIndex(where: { $0.id == id }) else {
                return
            }
            held.remove(at: index).continuation.resume(returning: false)
        }
    }
#endif
