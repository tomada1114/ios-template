import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// What a broken store keeps, by key name.
private typealias Slots = [String: Data]

/// Answers a value for a key nobody wrote — breaks "a key never written reads `nil`".
private actor PhantomValueStore: SecureStoring {
    private var slots: Slots = [:]

    func data(for key: SecureKey) -> Data? {
        slots[key.name] ?? Data()
    }

    func set(_ data: Data, for key: SecureKey) {
        slots[key.name] = data
    }

    func delete(_ key: SecureKey) {
        slots[key.name] = nil
    }
}

/// Drops every write — breaks "a written value reads back equal".
private struct WriteIgnoringStore: SecureStoring {
    func data(for _: SecureKey) -> Data? {
        nil
    }

    func set(_: Data, for _: SecureKey) {
        // Deliberately dropped.
    }

    func delete(_: SecureKey) {
        // Nothing is ever stored.
    }
}

/// Keeps the first value written under a key, as an add-only Keychain call would —
/// breaks "a second write replaces the first".
private actor FirstWriteWinsStore: SecureStoring {
    private var slots: Slots = [:]

    func data(for key: SecureKey) -> Data? {
        slots[key.name]
    }

    func set(_ data: Data, for key: SecureKey) {
        if slots[key.name] == nil {
            slots[key.name] = data
        }
    }

    func delete(_ key: SecureKey) {
        slots[key.name] = nil
    }
}

/// Stores every key in one slot, whatever its name — breaks "keys with different names
/// are independent".
private actor SingleSlotStore: SecureStoring {
    private var slot: Data?

    func data(for _: SecureKey) -> Data? {
        slot
    }

    func set(_ data: Data, for _: SecureKey) {
        slot = data
    }

    func delete(_: SecureKey) {
        slot = nil
    }
}

/// Reports a delete as done and keeps the value — breaks "a deleted key reads `nil`".
private actor DeleteIgnoringStore: SecureStoring {
    private var slots: Slots = [:]

    func data(for key: SecureKey) -> Data? {
        slots[key.name]
    }

    func set(_ data: Data, for key: SecureKey) {
        slots[key.name] = data
    }

    func delete(_: SecureKey) {
        // Deliberately kept.
    }
}

/// Reports a delete of an absent key as a failure, as a raw `errSecItemNotFound` would —
/// breaks "deleting an absent key succeeds".
private actor StrictDeleteStore: SecureStoring {
    static let absentStatus = -25_300

    private var slots: Slots = [:]

    func data(for key: SecureKey) -> Data? {
        slots[key.name]
    }

    func set(_ data: Data, for key: SecureKey) {
        slots[key.name] = data
    }

    func delete(_ key: SecureKey) throws(SecureStoringError) {
        guard slots.removeValue(forKey: key.name) != nil else {
            throw .storageFailure(status: Self.absentStatus)
        }
    }
}

/// The one run of ``SecureStoringContract``: against ``InMemorySecureStore``, so the fake
/// cannot drift from the port, and against deliberately broken stores, so the contract
/// cannot pass anything. No test runs it against `KeychainSecureStore` — the Keychain
/// refuses every test runner — so the adapter is held to the same promises in the running
/// app (the `persisting-data` skill's `references/secure-storage.md`).
@Suite("SecureStoring contract, against the fake")
struct SecureStoringContractTests {
    @Test
    func `the fake keeps the contract`() async {
        await SecureStoringContract.check(InMemorySecureStore())
    }

    @Test
    func `the contract leaves nothing behind`() async {
        let store = InMemorySecureStore()
        _ = await SecureStoringContract.violations(of: store)
        #expect(await store.snapshot.isEmpty)
    }

    @Test
    func `the contract clears its keys before it starts`() async {
        // What a run interrupted between a write and its cleanup leaves in a store that
        // outlives the process.
        let store = InMemorySecureStore(values: [
            SecureKey(name: "contract.first"): Data([0x01]),
            SecureKey(name: "contract.second"): Data([0x02]),
        ])
        #expect(await SecureStoringContract.violations(of: store).isEmpty)
        #expect(await store.snapshot.isEmpty)
    }

    // The contract's own oracle: an implementation that breaks a promise must be
    // reported, or `check(_:)` would pass anything, the real adapter included.

    @Test
    func `a store that answers for a key never written is reported`() async {
        let violations = await SecureStoringContract.violations(of: PhantomValueStore())
        #expect(violations.contains("a key never written read back a value"))
    }

    @Test
    func `a store that ignores a write is reported`() async {
        let violations = await SecureStoringContract.violations(of: WriteIgnoringStore())
        #expect(violations.contains("a written value did not read back equal"))
    }

    @Test
    func `a store that keeps the first write is reported`() async {
        let violations = await SecureStoringContract.violations(of: FirstWriteWinsStore())
        #expect(violations == ["a second write did not replace the first"])
    }

    @Test
    func `a store that keeps every key under one name is reported`() async {
        let violations = await SecureStoringContract.violations(of: SingleSlotStore())
        #expect(violations.contains("writing contract.first changed contract.second"))
        #expect(violations.contains("writing contract.second changed contract.first"))
    }

    @Test
    func `a store that ignores a delete is reported`() async {
        let violations = await SecureStoringContract.violations(of: DeleteIgnoringStore())
        #expect(violations == ["a deleted key still read back a value"])
    }

    @Test
    func `a store that fails a delete of an absent key is reported`() async {
        let violations = await SecureStoringContract.violations(of: StrictDeleteStore())
        #expect(violations == ["deleting an absent key threw storageFailure(status: -25300)"])
    }

    @Test
    func `a store that cannot be written is reported`() async {
        let store = InMemorySecureStore()
        await store.fail(.write, with: .deviceLocked)
        let violations = await SecureStoringContract.violations(of: store)
        #expect(violations == ["writing a value threw deviceLocked"])
    }

    @Test
    func `a clause that throws stops the run, so one failure is one violation`() async {
        let store = InMemorySecureStore()
        await store.fail(.read, with: .storageFailure(status: -34_018))
        let violations = await SecureStoringContract.violations(of: store)
        #expect(violations == ["reading a key never written threw storageFailure(status: -34018)"])
    }
}
