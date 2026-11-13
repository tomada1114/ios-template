import Foundation
import MyAppCore
import MyAppTestSupport
import Testing

/// What the fake offers a test beyond the port: starting values, failures a test sets,
/// and a record of what it was asked. The port's promises are `SecureStoringContractTests`.
@Suite("InMemorySecureStore")
struct InMemorySecureStoreTests {
    static let key = SecureKey(name: "test.key")
    static let value = Data([0xCA, 0xFE])

    @Test
    func `it starts holding the values it is handed`() async throws {
        let store = InMemorySecureStore(values: [Self.key: Self.value])
        #expect(try await store.data(for: Self.key) == Self.value)
        #expect(await store.snapshot == [Self.key: Self.value])
    }

    @Test(arguments: [
        SecureStoringError.deviceLocked,
        .storageFailure(status: -34_018),
    ])
    func `a failing read throws the error it was given`(error: SecureStoringError) async {
        let store = InMemorySecureStore(values: [Self.key: Self.value])
        await store.fail(.read, with: error)
        await #expect(throws: error) {
            try await store.data(for: Self.key)
        }
    }

    @Test
    func `a failing write throws and stores nothing`() async {
        let store = InMemorySecureStore()
        await store.fail(.write, with: .deviceLocked)
        await #expect(throws: SecureStoringError.deviceLocked) {
            try await store.set(Self.value, for: Self.key)
        }
        #expect(await store.snapshot.isEmpty)
    }

    @Test
    func `a failing delete throws and keeps the value`() async {
        let store = InMemorySecureStore(values: [Self.key: Self.value])
        await store.fail(.delete, with: .storageFailure(status: -1))
        await #expect(throws: SecureStoringError.storageFailure(status: -1)) {
            try await store.delete(Self.key)
        }
        #expect(await store.snapshot == [Self.key: Self.value])
    }

    @Test
    func `an operation succeeds again once its failure is lifted`() async throws {
        let store = InMemorySecureStore()
        await store.fail(.write, with: .deviceLocked)
        await store.succeed(.write)
        try await store.set(Self.value, for: Self.key)
        #expect(await store.snapshot == [Self.key: Self.value])
    }

    @Test
    func `every call is recorded in order, the failed ones included`() async throws {
        let store = InMemorySecureStore()
        try await store.set(Self.value, for: Self.key)
        _ = try await store.data(for: Self.key)
        await store.fail(.delete, with: .deviceLocked)
        try? await store.delete(Self.key)
        #expect(await store.calls == [.write, .read, .delete])
    }
}
