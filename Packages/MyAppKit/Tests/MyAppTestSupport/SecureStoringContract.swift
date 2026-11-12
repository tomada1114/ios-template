import Foundation
import MyAppCore
import Testing

/// The promises ``MyAppCore/SecureStoring`` makes, checked against any implementation.
///
/// A fake stands in for the adapter only while both keep the port's promises, so they are
/// written once, here, over the protocol. `MyAppCoreTests` runs ``check(_:)`` against
/// ``InMemorySecureStore`` under `just test` and in CI. Nothing runs it against
/// `KeychainSecureStore`: the Keychain refuses a test runner, on the host and on the
/// Simulator, so the adapter is held to the same clauses in the running app (the
/// `persisting-data` skill's `references/secure-storage.md`). Every clause is one the
/// port's `///` states; a new clause is stated there first.
///
/// The keys are the contract's own, never ``MyAppCore/SecureKeys``, so a contract run
/// never touches a real secret — and it deletes every one of them before it starts and
/// before it returns, so a run against a store that outlives the process neither trips
/// over nor leaves behind a value.
package enum SecureStoringContract {
    /// Contract-local keys.
    enum Keys {
        static let first = SecureKey(name: "contract.first")
        static let second = SecureKey(name: "contract.second")
        static let absent = SecureKey(name: "contract.absent")
        static let empty = SecureKey(name: "contract.empty")
        static let all = [first, second, absent, empty]
    }

    /// Fixed values the contract stores. None is valid UTF-8, so an implementation that
    /// round-trips a secret through a string is caught.
    enum Fixture {
        private static let zero: UInt8 = 0x00
        private static let allBits: UInt8 = 0xFF
        /// A UTF-8 continuation byte with no lead byte before it.
        private static let strayContinuation: UInt8 = 0x80
        /// A UTF-8 lead byte with nothing after it.
        private static let truncatedLead: UInt8 = 0xC3

        static let firstValue = Data([zero, allBits, strayContinuation])
        static let replacement = Data([truncatedLead])
        static let secondValue = Data([allBits, zero, strayContinuation])
    }

    /// One promise, named by the step a failure report quotes.
    private enum Clause: String {
        case deletedKeysReadNil = "deleting a key"
        case deletingAnAbsentKeySucceeds = "deleting an absent key"
        case keysAreIndependent = "writing a second key"
        case secondWriteReplacesTheFirst = "replacing a value"
        case unwrittenKeysReadNil = "reading a key never written"
        case writtenValuesReadBackEqual = "writing a value"

        /// The order the clauses run in: each after the first builds on the state the
        /// ones before it left.
        static let inOrder: [Self] = [
            .unwrittenKeysReadNil,
            .writtenValuesReadBackEqual,
            .secondWriteReplacesTheFirst,
            .keysAreIndependent,
            .deletedKeysReadNil,
            .deletingAnAbsentKeySucceeds,
        ]

        /// What this clause finds broken in `store`.
        func violations(of store: some SecureStoring) async throws(SecureStoringError) -> [String] {
            switch self {
            case .unwrittenKeysReadNil:
                try await SecureStoringContract.unwrittenKeysReadNil(store)

            case .writtenValuesReadBackEqual:
                try await SecureStoringContract.writtenValuesReadBackEqual(store)

            case .secondWriteReplacesTheFirst:
                try await SecureStoringContract.secondWriteReplacesTheFirst(store)

            case .keysAreIndependent:
                try await SecureStoringContract.keysAreIndependent(store)

            case .deletedKeysReadNil:
                try await SecureStoringContract.deletedKeysReadNil(store)

            case .deletingAnAbsentKeySucceeds:
                try await SecureStoringContract.deletingAnAbsentKeySucceeds(store)
            }
        }
    }

    /// A description of every broken promise, empty when `store` keeps them all.
    ///
    /// It first deletes whatever `store` holds under the contract's keys, so a run that was
    /// interrupted against a store that outlives the process — and left a value behind —
    /// does not fail the next run on a correct implementation. No clause expects an
    /// operation to fail, and every clause after the first builds on the state the ones
    /// before it left, so the first clause that throws is reported under its name and the
    /// rest do not run: one root failure is one violation, not several unrelated ones.
    ///
    /// Separate from ``check(_:)`` so a test can hand it an implementation that breaks a
    /// promise and see the contract notice — the proof it is not vacuous.
    package static func violations(of store: some SecureStoring) async -> [String] {
        await removeEverything(from: store)
        var broken: [String] = []
        for clause in Clause.inOrder {
            do {
                broken += try await clause.violations(of: store)
            } catch {
                broken.append("\(clause.rawValue) threw \(error)")
                break
            }
        }
        await removeEverything(from: store)
        return broken
    }

    /// Records an issue for every promise `store` breaks.
    package static func check(_ store: some SecureStoring) async {
        let broken = await violations(of: store)
        #expect(
            broken.isEmpty,
            "\(type(of: store)) breaks the SecureStoring contract: \(broken)",
        )
    }

    /// Best effort, before the clauses and after them: a store that cannot delete is
    /// reported by the clauses themselves.
    private static func removeEverything(from store: some SecureStoring) async {
        for key in Keys.all {
            try? await store.delete(key)
        }
    }

    // MARK: - Clauses

    /// Promise 1: a key never written reads `nil`.
    private static func unwrittenKeysReadNil(
        _ store: some SecureStoring,
    ) async throws(SecureStoringError) -> [String] {
        let first = try await store.data(for: Keys.first)
        let second = try await store.data(for: Keys.second)
        return first == nil && second == nil ? [] : ["a key never written read back a value"]
    }

    /// Promise 2: a written value reads back equal — an empty one included, which must
    /// not read as absent.
    private static func writtenValuesReadBackEqual(
        _ store: some SecureStoring,
    ) async throws(SecureStoringError) -> [String] {
        var broken: [String] = []
        try await store.set(Fixture.firstValue, for: Keys.first)
        if try await store.data(for: Keys.first) != Fixture.firstValue {
            broken.append("a written value did not read back equal")
        }
        try await store.set(Data(), for: Keys.empty)
        if try await store.data(for: Keys.empty) != Data() {
            broken.append("an empty value did not read back empty")
        }
        return broken
    }

    /// Promise 3: a second write under a key replaces the first.
    private static func secondWriteReplacesTheFirst(
        _ store: some SecureStoring,
    ) async throws(SecureStoringError) -> [String] {
        try await store.set(Fixture.replacement, for: Keys.first)
        let replaced = try await store.data(for: Keys.first) == Fixture.replacement
        return replaced ? [] : ["a second write did not replace the first"]
    }

    /// Promise 4: keys with different names are independent. Runs after promise 3, so
    /// `contract.first` already holds a value `contract.second` must not see.
    private static func keysAreIndependent(
        _ store: some SecureStoring,
    ) async throws(SecureStoringError) -> [String] {
        var broken: [String] = []
        if try await store.data(for: Keys.second) != nil {
            broken.append("writing contract.first changed contract.second")
        }
        let before = try await store.data(for: Keys.first)
        try await store.set(Fixture.secondValue, for: Keys.second)
        if try await store.data(for: Keys.first) != before {
            broken.append("writing contract.second changed contract.first")
        }
        return broken
    }

    /// Promise 5: a deleted key reads `nil` — and only that key is deleted.
    private static func deletedKeysReadNil(
        _ store: some SecureStoring,
    ) async throws(SecureStoringError) -> [String] {
        var broken: [String] = []
        try await store.delete(Keys.first)
        if try await store.data(for: Keys.first) != nil {
            broken.append("a deleted key still read back a value")
        }
        if try await store.data(for: Keys.second) != Fixture.secondValue {
            broken.append("deleting contract.first changed contract.second")
        }
        return broken
    }

    /// Promise 6: deleting an absent key succeeds; a throw is reported by
    /// ``violations(of:)`` under this clause's name.
    private static func deletingAnAbsentKeySucceeds(
        _ store: some SecureStoring,
    ) async throws(SecureStoringError) -> [String] {
        try await store.delete(Keys.absent)
        return []
    }
}
