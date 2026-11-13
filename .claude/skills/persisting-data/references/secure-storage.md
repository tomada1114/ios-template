# Secure storage

`SecureStoring` is the seam for secrets — a credential that must survive a relaunch and
must not sit where a preference does. `UserDefaults` is a plain property list, unencrypted
and included in backups, so without this port the first app that signs a user in would
put the token there because it was the only seam. The port, `SecureKey`, and every key
are in `MyAppCore/SecureStorage`, the `KeychainSecureStore` adapter in
`MyAppPlatform/SecureStorage`, and `InMemorySecureStore` plus `SecureStoringContract` in
`Tests/MyAppTestSupport`. The template stores no secret itself, so nothing in `App/`
builds the adapter yet: the first feature that needs one hands a `KeychainSecureStore()`
to `AppModel` as `any SecureStoring`, the way `makePreferences()` does.

```swift
public protocol SecureStoring: Sendable {
    func data(for key: SecureKey) async throws(SecureStoringError) -> Data?
    func set(_ data: Data, for key: SecureKey) async throws(SecureStoringError)
    func delete(_ key: SecureKey) async throws(SecureStoringError)
}
```

- **`async` and throwing, unlike `PreferencesStoring`.** Every Keychain call is a blocking
  round trip to a system service and can fail in ways a caller acts on, so the port is
  `async throws(SecureStoringError)`. An actor would still run a blocking call on Swift's
  cooperative thread pool, so the adapter is a `Sendable` struct that runs every `SecItem`
  call on one dedicated serial dispatch queue all instances share, and suspends on a
  checked continuation until it answers: the calls block that queue's thread, never the
  pool's or the main thread, and a write — an update, then an add when nothing was
  there — never interleaves with another write in the process. Another process can
  still write between the update and the add; the add's `errSecDuplicateItem` is then
  answered by one more update, not reported.
- **Opaque `Data` across the port.** What a secret encodes (a token's text, a key's
  bytes) is converted in Core, where a test sees it. The adapter never interprets a
  value, and never logs one: `AppLog.secureStorage` gets the operation, the key's name,
  and the status code.
- **Absence is an answer.** A key never written, or deleted, reads `nil`; deleting an
  absent key succeeds, so signing out twice is not an error. An empty value is a value
  and reads back empty, not `nil`.
- **A closed error enum with two cases.** `.deviceLocked` is `errSecInteractionNotAllowed`:
  the device has not been unlocked since it started, the secret is intact, and the caller
  asks again later rather than treating the user as signed out. Every other status is
  `.storageFailure(status:)`, carrying only the number. There is no "not found" case and
  no cancellation case (`.claude/rules/core.md` › Errors).
- **Key names are contract, and outlive the app.** Every key is a constant in
  `SecureKeys`, and `SecureKeysTests` pins each name. A Keychain item survives the app's
  deletion: a reinstalled app finds the secret a previous install wrote, and a renamed
  key leaves the old secret on the device while reading as absent. A rename is therefore
  a migration in Core — read the old key, write the new one, delete the old — with a
  test that starts from the old key (`AGENTS.md`'s "What is contract and what is
  private"). Whether a fresh install should discard what it finds is a Core decision,
  made on a preference that does not survive deletion, never an adapter's.
  `SecureKeys.authToken` is the worked example; nothing reads it.

## The Keychain item

One generic-password item per key: `kSecAttrService` is the bundle identifier
(`AppLog.subsystem`, the literal `AppLogTests` holds to `project.yml`), `kSecAttrAccount`
is the key's name. The service is the adapter's one initializer parameter, so a test
works under a service of its own.

- **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.** After first unlock, so a
  background launch (a notification, a background task) can still read a token while the
  screen is locked; this device only, so a backup restored to another device, or iCloud
  Keychain, never carries the secret there. An app whose secret must be unreadable while
  locked chooses `WhenUnlocked…` and accepts that background work cannot authenticate —
  a design change that rewrites this entry.
- **The default access group, so no entitlement.** The item is visible to this app
  alone. Sharing it with an extension or another app needs the Keychain Sharing
  capability (`keychain-access-groups`), which is an entitlement and a signing change:
  it needs the owner's sign-off (`AGENTS.md` › Security and human approval) and is not
  something the adapter grows quietly. Biometric protection
  (`SecAccessControl`) is likewise an app's decision, not the template's.
- **The data protection keychain, named in every query.** It is the only keychain iOS
  has. On macOS, where the package also builds, naming it keeps a host run out of the
  user's login keychain — which would ignore the accessibility above and prompt for a
  password — at the price that an unsigned host process is refused
  (`errSecMissingEntitlement`).
- **Not a required-reason API.** The Keychain is not in a category
  `PrivacyInfo.xcprivacy` must declare a reason for, unlike `UserDefaults`, so the port
  brings no privacy manifest with it (`integrating-system-apis`'
  `references/permissions.md` › "The privacy manifest").

## What is tested where

| Under test | Test | Runs in |
|---|---|---|
| The port's promises, against the fake, and the contract's own oracle (six broken stores) | `MyAppCoreTests/SecureStorage/SecureStoringContractTests.swift` | `just test`, CI |
| The fake's failures and recorded calls | `MyAppCoreTests/SecureStorage/InMemorySecureStoreTests.swift` | `just test`, CI |
| Key names | `MyAppCoreTests/SecureStorage/SecureKeysTests.swift` | `just test`, CI |
| `OSStatus` to `SecureStoringError` | `MyAppPlatformTests/KeychainSecureStoreTests.swift` (`storeError(for:)`) | `just test`, CI |
| A write's update, add, and retried update on a duplicate | `MyAppPlatformTests/KeychainSecureStoreTests.swift` (`writeStatus(update:add:)`) | `just test`, CI |
| The query and attribute dictionaries (class, service, account, data protection keychain, accessibility, match limit) | `MyAppPlatformTests/KeychainSecureStoreTests.swift` (`itemQuery`, `readQuery`, `writeAttributes`, `newItem`) | `just test`, CI |
| The port's promises, against the Keychain | none — the adapter called from `App/`, in the running app | nowhere; the evidence is a log excerpt in the pull request (`running-the-app`) |

No gate stores a Keychain item, and this is the one place the template departs from "the
contract runs against the fake and the adapter". Every `SecItem` call answers
`errSecMissingEntitlement` (-34018) to a process with no app around it: `swift test` on
the host, and the bare runner `just test-ios` uses on the Simulator. An app process on
the Simulator is accepted, with no entitlement. So a change to the adapter is shown the
way `running-the-app` shows anything no gate asserts: call the adapter from `App/`
under a throwaway service name — write, read back, replace, a second key, delete, delete
again, an empty value — log each result at `.notice` (`log show` does not see `.debug`),
`just run`, read it with `xcrun simctl spawn booted log show`, and revert the call. A
device run, with real signing, is the owner's to make. The contract removes its own keys
before it returns, and such a probe deletes what it wrote, because a Keychain item
outlives the process that wrote it.

A hosted test target — the package's tests run inside the app — would put the contract
run against the Keychain in a gate. It is a new target, which is a design change
(`AGENTS.md`'s "Before changing the architecture") and the owner's decision.

Core never imports `Security` (`.swiftlint.yml`'s `no_ui_import_in_core`,
`ArchitectureBoundaryTests.forbiddenModules`) and never calls `SecItemAdd`,
`SecItemCopyMatching`, `SecItemUpdate`, or `SecItemDelete`, which Foundation re-exports
and an import ban therefore cannot see (`ArchitectureBoundaryTests.forbiddenKeychainCalls`).
That scan covers those four names and nothing else: no check looks for any other
Security function, type, or constant in Core.
