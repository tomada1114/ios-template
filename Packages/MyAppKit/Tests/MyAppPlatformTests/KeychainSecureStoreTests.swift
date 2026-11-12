import Foundation
import MyAppCore
@testable import MyAppPlatform
import Security
import Testing

/// What a test can hold `KeychainSecureStore` to without a Keychain: its status mapping,
/// the order of a write's calls, and the dictionaries it hands `SecItem`.
///
/// Nothing here stores an item, and `SecureStoringContract` is not run against the
/// adapter: every `SecItem` call answers `errSecMissingEntitlement` to a test runner with
/// no app around it — `swift test` on the host and `just test-ios` on the Simulator
/// alike. The adapter's round trip is verified in the running app (the `persisting-data`
/// skill's `references/secure-storage.md`).
@Suite("KeychainSecureStore")
struct KeychainSecureStoreTests {
    /// One scripted write: what each update and the add answer, in call order, and what
    /// the write must end with and call.
    struct WriteCase: Sendable, CustomTestStringConvertible {
        let name: String
        let updates: [OSStatus]
        let adds: [OSStatus]
        let expected: OSStatus
        let calls: [String]

        var testDescription: String {
            name
        }
    }

    static let service = "test.service"
    static let account = "test.account"
    static let value = Data([0x00, 0xFF])

    @Test(arguments: [
        (errSecInteractionNotAllowed, SecureStoringError.deviceLocked),
        (errSecMissingEntitlement, .storageFailure(status: -34_018)),
        (errSecDuplicateItem, .storageFailure(status: -25_299)),
        (errSecItemNotFound, .storageFailure(status: -25_300)),
        (errSecDecode, .storageFailure(status: -26_275)),
    ])
    func `a Keychain status maps to Core's error`(
        status: OSStatus,
        expected: SecureStoringError,
    ) {
        #expect(KeychainSecureStore.storeError(for: status) == expected)
    }

    // MARK: - The write's sequence

    @Test(arguments: [
        WriteCase(
            name: "an existing item is updated, with no add",
            updates: [errSecSuccess],
            adds: [],
            expected: errSecSuccess,
            calls: ["update"],
        ),
        WriteCase(
            name: "an absent item is added",
            updates: [errSecItemNotFound],
            adds: [errSecSuccess],
            expected: errSecSuccess,
            calls: ["update", "add"],
        ),
        WriteCase(
            name: "an item written between the update and the add is updated again",
            updates: [errSecItemNotFound, errSecSuccess],
            adds: [errSecDuplicateItem],
            expected: errSecSuccess,
            calls: ["update", "add", "update"],
        ),
        WriteCase(
            name: "the retried update is the last call, and its failure is the answer",
            updates: [errSecItemNotFound, errSecItemNotFound],
            adds: [errSecDuplicateItem],
            expected: errSecItemNotFound,
            calls: ["update", "add", "update"],
        ),
        WriteCase(
            name: "a failed update is the answer, with no add",
            updates: [errSecInteractionNotAllowed],
            adds: [],
            expected: errSecInteractionNotAllowed,
            calls: ["update"],
        ),
        WriteCase(
            name: "a failed add other than a duplicate is the answer, with no retry",
            updates: [errSecItemNotFound],
            adds: [errSecMissingEntitlement],
            expected: errSecMissingEntitlement,
            calls: ["update", "add"],
        ),
    ])
    func `a write updates, adds when absent, and updates once more on a duplicate`(
        script: WriteCase,
    ) {
        var calls: [String] = []
        var updates = script.updates[...]
        var adds = script.adds[...]
        let status = KeychainSecureStore.writeStatus(
            update: {
                calls.append("update")
                return updates.popFirst() ?? errSecParam
            },
            add: {
                calls.append("add")
                return adds.popFirst() ?? errSecParam
            },
        )
        #expect(status == script.expected)
        #expect(calls == script.calls)
    }

    // MARK: - The dictionaries

    @Test
    func `the item query names one generic password in the data protection keychain`() {
        let query = KeychainSecureStore.itemQuery(service: Self.service, account: Self.account)
        #expect(Set(query.keys) == [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String,
        ])
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == Self.service)
        #expect(query[kSecAttrAccount as String] as? String == Self.account)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test
    func `the read query asks for one item's data`() {
        let query = KeychainSecureStore.readQuery(service: Self.service, account: Self.account)
        #expect(Set(query.keys) == [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String,
            kSecReturnData as String,
            kSecMatchLimit as String,
        ])
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == Self.service)
        #expect(query[kSecAttrAccount as String] as? String == Self.account)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
    }

    @Test
    func `a write sets the value, readable after first unlock on this device only`() {
        let attributes = KeychainSecureStore.writeAttributes(for: Self.value)
        #expect(Set(attributes.keys) == [kSecValueData as String, kSecAttrAccessible as String])
        #expect(attributes[kSecValueData as String] as? Data == Self.value)
        #expect(
            attributes[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
        )
    }

    @Test
    func `a new item is the item query with the write's attributes`() {
        let item = KeychainSecureStore.newItem(
            service: Self.service,
            account: Self.account,
            data: Self.value,
        )
        #expect(Set(item.keys) == [
            kSecClass as String,
            kSecAttrService as String,
            kSecAttrAccount as String,
            kSecUseDataProtectionKeychain as String,
            kSecValueData as String,
            kSecAttrAccessible as String,
        ])
        #expect(item[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(item[kSecAttrService as String] as? String == Self.service)
        #expect(item[kSecAttrAccount as String] as? String == Self.account)
        #expect(item[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(item[kSecValueData as String] as? Data == Self.value)
        #expect(
            item[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
        )
    }
}
