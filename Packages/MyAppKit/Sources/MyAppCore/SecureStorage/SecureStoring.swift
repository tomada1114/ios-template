import Foundation

/// The port for secrets — a credential that must survive a relaunch and must not sit in
/// a preference, which is stored unencrypted and included in backups. `KeychainSecureStore`
/// in `MyAppPlatform` is the adapter; `InMemorySecureStore` in `MyAppTestSupport` is the
/// fake.
///
/// A secret crosses the port as opaque `Data`: what it encodes (a token's text, a key's
/// bytes) is the caller's to decide, in Core, where a test sees the conversion. It is
/// named by a ``SecureKey`` declared in ``SecureKeys``.
///
/// `async`, unlike ``PreferencesStoring``: every call is a round trip to the system's
/// keychain service, which blocks, so the adapter runs it on a dispatch queue of its own
/// and a `@MainActor` caller suspends rather than waiting on the main thread. Every method throws
/// ``SecureStoringError`` and
/// nothing else.
///
/// Every implementation promises:
/// 1. A key never written reads `nil`, without throwing.
/// 2. A written value reads back equal, byte for byte — an empty value included.
/// 3. A second write under a key replaces the first.
/// 4. Keys with different names are independent.
/// 5. A deleted key reads `nil`.
/// 6. Deleting an absent key succeeds: "gone" is what the caller asked for, so signing
///    out twice is not an error.
///
/// `SecureStoringContract` in `MyAppTestSupport` checks them against the fake under
/// `just test`. No test runner may store a Keychain item, so the adapter is held to them
/// in the running app instead (the `persisting-data` skill's
/// `references/secure-storage.md`); a new promise is stated here first, then added there.
public protocol SecureStoring: Sendable {
    /// The secret stored under `key`, or `nil` when none is.
    func data(for key: SecureKey) async throws(SecureStoringError) -> Data?

    /// Stores `data` under `key`, replacing whatever was there.
    func set(_ data: Data, for key: SecureKey) async throws(SecureStoringError)

    /// Removes the secret stored under `key`; succeeds when none is.
    func delete(_ key: SecureKey) async throws(SecureStoringError)
}
