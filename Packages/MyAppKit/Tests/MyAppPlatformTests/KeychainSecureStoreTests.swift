import MyAppCore
@testable import MyAppPlatform
import Security
import Testing

/// What a test can hold `KeychainSecureStore` to: its status mapping, which needs no
/// Keychain.
///
/// Nothing here stores an item, and `SecureStoringContract` is not run against the
/// adapter: every `SecItem` call answers `errSecMissingEntitlement` to a test runner with
/// no app around it — `swift test` on the host and `just test-ios` on the Simulator
/// alike. The adapter's round trip is verified in the running app (the `persisting-data`
/// skill's `references/secure-storage.md`).
@Suite("KeychainSecureStore")
struct KeychainSecureStoreTests {
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
}
