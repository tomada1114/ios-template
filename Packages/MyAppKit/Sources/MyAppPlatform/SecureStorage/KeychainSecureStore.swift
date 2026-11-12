import Foundation
import MyAppCore
import Security

/// The Keychain-backed adapter for ``MyAppCore/SecureStoring``.
///
/// Translation only: a secret is one generic-password item whose service is the app's
/// bundle identifier and whose account is the key's name, in the app's default access
/// group — so it needs no entitlement. Every item is written
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable by a background launch
/// once the user has unlocked the device after a restart, and never copied to another
/// device by a backup or iCloud Keychain.
///
/// Every query names the data protection keychain. That is the only keychain iOS has; on
/// macOS it keeps a host run away from the user's login keychain, where the accessibility
/// above would be ignored.
///
/// No test stores an item: the Keychain answers `errSecMissingEntitlement` to a test
/// runner with no app around it, on the host and on the Simulator. `just test` checks
/// the status mapping, which needs no Keychain; the rest is verified in the running app
/// (the `persisting-data` skill's `references/secure-storage.md`).
///
/// An actor: each call is a blocking round trip to the system's keychain service, which
/// must not run on the main thread, and a write is two calls (update, then add) that
/// must not interleave with another write of the same key.
///
/// It logs the operation, the key's name, and the status — never a value.
public actor KeychainSecureStore: SecureStoring {
    /// A port method, as named in a log line.
    private enum Operation: String {
        case delete
        case read
        case write
    }

    private let service: String

    /// An adapter over the items stored under `service` — the app's bundle identifier
    /// for the app (``MyAppCore/AppLog/subsystem``, the literal `AppLogTests` holds to
    /// `project.yml`); a name of its own for a test.
    public init(service: String = AppLog.subsystem) {
        self.service = service
    }

    /// Core's error for a failed `SecItem` call. `OSStatus` is the SDK's, not Core's: the
    /// one status Core decides on is named, and every other is identified only by its
    /// number.
    static func storeError(for status: OSStatus) -> SecureStoringError {
        switch status {
        case errSecInteractionNotAllowed:
            .deviceLocked

        default:
            .storageFailure(status: Int(status))
        }
    }

    public func data(for key: SecureKey) throws(SecureStoringError) -> Data? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw failure(status, during: .read, of: key)
        }
        guard let data = result as? Data else {
            // A generic password asked for its data answers `Data`; anything else is an
            // item this adapter cannot decode.
            throw failure(errSecDecode, during: .read, of: key)
        }
        return data
    }

    public func set(_ data: Data, for key: SecureKey) throws(SecureStoringError) {
        let query = query(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Update first: `SecItemAdd` refuses a key that already holds a value.
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw failure(status, during: .write, of: key)
        }
    }

    public func delete(_ key: SecureKey) throws(SecureStoringError) {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status, during: .delete, of: key)
        }
    }

    /// What identifies `key`'s item, and nothing about its value.
    private func query(for key: SecureKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.name,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Maps `status` and logs it. A key's name is a constant in the source, so it is
    /// `.public` like the operation and the status; the value is never interpolated.
    private func failure(
        _ status: OSStatus,
        during operation: Operation,
        of key: SecureKey,
    ) -> SecureStoringError {
        let name = key.name
        AppLog.secureStorage.error(
            """
            Keychain \(operation.rawValue, privacy: .public) of \(name, privacy: .public) \
            failed with status \(status, privacy: .public)
            """,
        )
        return Self.storeError(for: status)
    }
}
