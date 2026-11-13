import Foundation
import MyAppCore

/// The one fake of ``MyAppCore/SecureStoring``, shared by every test target.
///
/// A fake, not a mock: a real conforming implementation that keeps secrets in a
/// dictionary, whose failures and calls are data the test sets and reads — no
/// expectations are declared up front. `SecureStoringContract` holds it to the port's
/// promises, so a Core type tested against it is tested against the port.
///
/// An actor, so it is `Sendable` without a lock and a caller under test suspends on every
/// call, as it does on the adapter's queue in the app.
package actor InMemorySecureStore: SecureStoring {
    /// A port method, as recorded in ``calls`` and targeted by ``fail(_:with:)``.
    package enum Operation: Equatable, Sendable {
        case delete
        case read
        case write
    }

    /// Every call made so far, in order — including the ones that failed.
    package private(set) var calls: [Operation] = []

    private var stored: [SecureKey: Data]
    private var failures: [Operation: SecureStoringError] = [:]

    /// What the fake holds right now, by key — read without recording a call.
    package var snapshot: [SecureKey: Data] {
        stored
    }

    /// Starts empty: every key reads `nil`.
    package init() {
        self.init(values: [:])
    }

    /// Starts holding `values`, as a device a previous launch signed in on would.
    package init(values: [SecureKey: Data]) {
        stored = values
    }

    /// Makes every later call to `operation` throw `error`, until ``succeed(_:)``.
    package func fail(_ operation: Operation, with error: SecureStoringError) {
        failures[operation] = error
    }

    /// Undoes ``fail(_:with:)`` for `operation`.
    package func succeed(_ operation: Operation) {
        failures[operation] = nil
    }

    package func data(for key: SecureKey) throws(SecureStoringError) -> Data? {
        try record(.read)
        return stored[key]
    }

    package func set(_ data: Data, for key: SecureKey) throws(SecureStoringError) {
        try record(.write)
        stored[key] = data
    }

    package func delete(_ key: SecureKey) throws(SecureStoringError) {
        try record(.delete)
        stored[key] = nil
    }

    private func record(_ operation: Operation) throws(SecureStoringError) {
        calls.append(operation)
        if let error = failures[operation] {
            throw error
        }
    }
}
