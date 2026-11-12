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
/// what needs no Keychain — the status mapping, the write's update-add-update sequence,
/// and the query and attribute dictionaries; the round trip is verified in the running
/// app (the `persisting-data` skill's `references/secure-storage.md`).
///
/// Each `SecItem` call is a blocking round trip to the system's keychain service, which
/// must run neither on the main thread nor on Swift's cooperative thread pool, whose
/// threads a blocked call would starve — an actor alone would run it on that pool. So
/// every call runs on one dedicated serial dispatch queue, shared by every instance, and
/// the `async` method suspends on a checked continuation until the queue answers. Being
/// serial, the queue also keeps a write — up to three calls (update, add, update) — from
/// interleaving with another write in this process. A write from another process can
/// still land between them; the sequence absorbs that (``writeStatus(update:add:)``).
/// Holding only its service name, the adapter is a `Sendable` struct.
///
/// It logs the operation, the key's name, and the status — never a value.
public struct KeychainSecureStore: SecureStoring {
    /// A port method, as named in a log line.
    private enum Operation: String {
        case delete
        case read
        case write
    }

    /// Where every instance's `SecItem` calls run, off the cooperative pool.
    private static let queue = DispatchQueue(label: "\(AppLog.subsystem).keychain")

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

    /// The status a write ends with. `SecItemAdd` refuses a key that already holds a
    /// value, so the write updates first and adds only when nothing was there. When the
    /// add answers `errSecDuplicateItem`, another instance or process wrote the item
    /// between the two calls, and one more update replaces that value; a failure after
    /// it is reported as it is.
    static func writeStatus(update: () -> OSStatus, add: () -> OSStatus) -> OSStatus {
        let status = update()
        guard status == errSecItemNotFound else {
            return status
        }
        let added = add()
        guard added == errSecDuplicateItem else {
            return added
        }
        return update()
    }

    /// What identifies the item stored under `account` in `service`, and nothing about
    /// its value — the query an update or a delete matches.
    static func itemQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// ``itemQuery(service:account:)``, asking for the one matching item's data.
    static func readQuery(service: String, account: String) -> [String: Any] {
        var query = itemQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    /// What a write sets on the item: the value, and when it may be read.
    static func writeAttributes(for data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    /// The whole item an add creates: ``itemQuery(service:account:)`` with
    /// ``writeAttributes(for:)``.
    static func newItem(service: String, account: String, data: Data) -> [String: Any] {
        itemQuery(service: service, account: account)
            .merging(writeAttributes(for: data)) { _, new in new }
    }

    /// Runs `work` on ``queue`` and suspends the caller, rather than blocking its thread,
    /// until it answers. Every dictionary `SecItem` takes is built inside `work`: none is
    /// `Sendable`, so none crosses onto the queue.
    private static func onQueue<Value: Sendable>(
        _ work: @escaping @Sendable () throws(SecureStoringError) -> Value,
    ) async throws(SecureStoringError) -> Value {
        let result: Result<Value, SecureStoringError> =
            await withCheckedContinuation { continuation in
                queue.async {
                    let outcome: Result<Value, SecureStoringError>
                    do throws(SecureStoringError) {
                        outcome = try .success(work())
                    } catch {
                        outcome = .failure(error)
                    }
                    continuation.resume(returning: outcome)
                }
            }
        return try result.get()
    }

    private static func read(service: String, key: SecureKey) throws(SecureStoringError) -> Data? {
        let query = readQuery(service: service, account: key.name)
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

    private static func write(
        _ data: Data,
        service: String,
        key: SecureKey,
    ) throws(SecureStoringError) {
        let query = itemQuery(service: service, account: key.name) as CFDictionary
        let attributes = writeAttributes(for: data) as CFDictionary
        let item = newItem(service: service, account: key.name, data: data) as CFDictionary
        let status = writeStatus(
            update: { SecItemUpdate(query, attributes) },
            add: { SecItemAdd(item, nil) },
        )
        guard status == errSecSuccess else {
            throw failure(status, during: .write, of: key)
        }
    }

    private static func remove(service: String, key: SecureKey) throws(SecureStoringError) {
        let query = itemQuery(service: service, account: key.name)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status, during: .delete, of: key)
        }
    }

    /// Maps `status` and logs it. A key's name is a constant in the source, so it is
    /// `.public` like the operation and the status; the value is never interpolated.
    private static func failure(
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
        return storeError(for: status)
    }

    public func data(for key: SecureKey) async throws(SecureStoringError) -> Data? {
        try await Self.onQueue { [service] () throws(SecureStoringError) in
            try Self.read(service: service, key: key)
        }
    }

    public func set(_ data: Data, for key: SecureKey) async throws(SecureStoringError) {
        try await Self.onQueue { [service] () throws(SecureStoringError) in
            try Self.write(data, service: service, key: key)
        }
    }

    public func delete(_ key: SecureKey) async throws(SecureStoringError) {
        try await Self.onQueue { [service] () throws(SecureStoringError) in
            try Self.remove(service: service, key: key)
        }
    }
}
