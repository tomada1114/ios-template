---
name: persisting-data
description: >
  Covers how this iOS app keeps state between launches - a repository port in Core
  (TodoRepository, value types across it, typed throws, Core-defined ordering), the
  SwiftData adapter in the Platform module (@ModelActor, PersistenceStore and the
  one ModelContainer, Storage .onDisk/.inMemory/.file, AppSchemaV1 and AppMigrationPlan,
  @Attribute(.unique)), the UnavailableTodoRepository null object when the store will
  not open, small settings through the synchronous PreferencesStoring port
  (PreferenceKey, PreferenceKeys, UserDefaultsPreferences, scratch suites), and secrets
  through the SecureStoring port (SecureKeys, KeychainSecureStore). Use when adding or
  changing a @Model, a stored property, a schema version or migration stage, a second
  repository or entity, a preference key or its default, a token or other secret, when
  a store fails to open or a save fails, when PreferenceKeysTests or a migration test
  fails, or when deciding between SwiftData, UserDefaults, the Keychain, a file, or
  CloudKit sync.
---

# Persisting Data

**Owns:** how state survives a relaunch here — the repository port's shape, the SwiftData
adapter and the one store it opens, the versioned schema and its migrations, what the app
does when the store will not open, the preferences port and its keys, and the
secure-storage port, its keys, and the Keychain item behind it. **Does not
own:** the conventions an adapter and its schema follow (`.claude/rules/platform.md` ›
Persistence, loaded with any file under `MyAppPlatform/`); the view model that calls a
repository (`.claude/rules/core.md` › View models); the Core error enum an adapter maps a
SwiftData error into, and the mapping (`.claude/rules/core.md` › Errors,
`.claude/rules/platform.md` › Mapping framework errors); an OS service or the HTTP client
behind a port (`integrating-system-apis`); the fake-and-contract test pattern itself
(`.claude/rules/testing.md`); a new package such as a database library (the Dependency
Policy in `.claude/rules/project.md`).

## Why SwiftData behind a port

SwiftData is first-party, so persistence costs no dependency, and it ships a versioned
schema and a migration plan from day one, so the first model change is a migration
rather than a data loss. Core Data is not used: SwiftData is its successor on this OS
floor. Core never sees either: the repository is a port in Core's vocabulary, so every
Core test runs without SwiftData, and the store stays replaceable.

Where the state is kept, and in what format — the schema and its migration plan, CloudKit
sync, `UserDefaults` keys, Keychain items, files — is a design change (`AGENTS.md`'s "Before changing the
architecture"), and the stored shape is contract (`AGENTS.md`'s "What is contract and
what is private"). A pull request that changes either rewrites this skill in place.

## Where each piece lives

| Piece | Home |
|---|---|
| The port, its error enum, and the domain value | `TodoRepository.swift` and `TodoItem.swift` in the feature's folder, `MyAppCore/Todos/` |
| The null object for "no store" | `UnavailableTodoRepository.swift`, beside the port in `MyAppCore/Todos/` |
| The one container, the schema, the migration plan, the adapter | `Sources/MyAppPlatform/Persistence/` |
| The preferences port, `PreferenceKey`, and every key | `Sources/MyAppCore/Preferences/` |
| The `UserDefaults` adapter | `Sources/MyAppPlatform/Preferences/UserDefaultsPreferences.swift` |
| The secure-storage port, `SecureKey`, its error enum, and every key | `Sources/MyAppCore/SecureStorage/` |
| The Keychain adapter | `Sources/MyAppPlatform/SecureStorage/KeychainSecureStore.swift` |
| Fakes and contracts | `Tests/MyAppTestSupport/`, in the folder named for the port's Core folder (`Todos/`: `InMemoryTodoRepository`, `TodoRepositoryContract`; `Preferences/`: `InMemoryPreferences`, `PreferencesContract`; `SecureStorage/`: `InMemorySecureStore`, `SecureStoringContract`) |
| Store, migration, and adapter tests | `Tests/MyAppPlatformTests/` |

Where SwiftData may appear, the `@ModelActor` adapter, and never editing a shipped schema
version are `.claude/rules/platform.md` › Persistence. Enforced by: `.swiftlint.yml`'s
`no_ui_import_in_core` and `ArchitectureBoundaryTests` (Core never imports SwiftData or
Security, names `UserDefaults`, or calls `SecItemAdd`, `SecItemCopyMatching`,
`SecItemUpdate`, or `SecItemDelete` — the scan covers those four calls and no other
Security name).

## A repository is a port

A repository is a `Sendable` protocol Core declares, in Core's vocabulary.
`TodoRepository` is the worked example:

```swift
public protocol TodoRepository: Sendable {
    func fetchAll() async throws(TodoRepositoryError) -> [TodoItem]
    func save(_ item: TodoItem) async throws(TodoRepositoryError)
    func delete(id: TodoItem.ID) async throws(TodoRepositoryError)
}
```

- **Value types only across the port.** `TodoItem` is a Core struct; the SwiftData
  `@Model` (`TodoRecord`) is internal to `MyAppPlatform` and never crosses. That keeps
  SwiftData's non-`Sendable` model objects on the adapter's actor and lets every Core
  test run without SwiftData.
- **`async` everywhere**, because an implementation is an actor with its own executor
  (SwiftData's `@ModelActor`, or the fake), and crossing into it is a suspension point.
- **Typed throws with a closed Core error enum.** `TodoRepositoryError` has three cases;
  the adapter maps every SwiftData error into one of them, so Core handles a closed set
  and never learns which store failed (`.claude/rules/core.md` › Errors).
- **The ordering is Core's.** `TodoItem.isOrderedBefore(_:_:)` defines display order and
  every implementation sorts by it, so a store's query language never decides behavior.
- **A null object for "no store".** When the on-disk store cannot be opened, `App/` hands
  the view model `UnavailableTodoRepository`, which fails every call. The app launches,
  shows its load failure with a retry, and never pretends an edit was saved. The
  alternatives — crashing, or silently falling back to an in-memory store whose edits
  vanish on relaunch — are both worse for the user.

Every port has exactly one fake and one contract function in `Tests/MyAppTestSupport`;
the contract runs against the fake in `MyAppCoreTests` and against the SwiftData adapter
with an in-memory store in `MyAppPlatformTests`, both under `just test`
(`.claude/rules/testing.md`'s "One Contract Suite per Port").

## The SwiftData adapter

One container for the whole app, an actor per repository, a schema versioned from day
one, and a failed open answered by the null object. The details — `PersistenceStore`,
`Storage`, rollback on a failed save, adding a schema version or a second entity, and
`@Attribute(.unique)` versus CloudKit sync — are **REQUIRED:**
[references/swiftdata.md](references/swiftdata.md) before touching anything under
`Persistence/`.

## Preferences

Small user settings that must survive a relaunch but are not the user's data go through
`PreferencesStoring`, a synchronous port over `UserDefaults`, never through SwiftData.
Every key is a `PreferenceKeys` constant whose name and default `PreferenceKeysTests`
pins: a renamed key reads as unset, so a rename is a migration in Core, not an edit to
that test. The port's shape, the value types it admits, and how UI tests start clean are
**REQUIRED:** [references/preferences.md](references/preferences.md) before adding or
changing a key.

## Secrets

A token, a key, or any other credential goes through `SecureStoring`, an `async`
throwing port over the Keychain — never through a preference, which `UserDefaults` keeps
unencrypted and includes in backups, and never through SwiftData. Every key is a
`SecureKeys` constant whose name `SecureKeysTests` pins, and a Keychain item survives
the app's deletion, so a rename is a migration in Core that also deletes the old item.
The adapter writes one generic-password item per key, readable after first unlock, on
this device only, in the app's default access group — no entitlement. No gate can store
a Keychain item, so the adapter is verified in the running app. The port's promises, the
item's attributes and why, and what is tested where are **REQUIRED:**
[references/secure-storage.md](references/secure-storage.md) before adding a key, or
changing the port or the adapter.

## Before you call it done

- [ ] The change follows `.claude/rules/platform.md` › Persistence (a changed stored
      shape is a new schema version with its pinned fingerprint and its migration test,
      `references/swiftdata.md`); `just lint` and `just test` pass.
- [ ] A changed preference key or default reads the old one and migrates it in Core, with
      a test that starts from the old value.
- [ ] A changed secure key reads the old one, writes the new one, and deletes the old, in
      Core, with a test that starts from the old key.
- [ ] The contract runs against the fake and the adapter, and both pass — except the
      Keychain adapter, whose pull request carries the running app's log instead.
- [ ] The pull request rewrites this skill where the persistence design changed.
