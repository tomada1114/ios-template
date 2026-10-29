---
name: persisting-data
description: >
  Covers how this iOS app keeps state between launches - a repository port in MyAppCore
  (TodoRepository, value types across it, typed throws, Core-defined ordering), the
  SwiftData adapter in MyAppPlatform/Persistence (@ModelActor, PersistenceStore and the
  one ModelContainer, Storage .onDisk/.inMemory/.file, AppSchemaV1 and AppMigrationPlan,
  @Attribute(.unique)), the UnavailableTodoRepository null object when the store will
  not open, and small settings through the synchronous PreferencesStoring port
  (PreferenceKey, PreferenceKeys, UserDefaultsPreferences, scratch suites). Use when
  adding or changing a @Model, a stored property, a schema version or migration stage, a
  second repository or entity, a preference key or its default, when a store fails to
  open or a save fails, when PreferenceKeysTests or a migration test fails, or when
  deciding between SwiftData, UserDefaults, a file, or CloudKit sync.
---

# Persisting Data

**Owns:** how state survives a relaunch here — the repository port's shape, the SwiftData
adapter and the one store it opens, the versioned schema and its migrations, what the app
does when the store will not open, and the preferences port and its keys. **Does not
own:** the view model that calls a repository (`designing-core-logic`); the Core error
enum an adapter maps a SwiftData error into (`designing-errors`); an OS service or the
HTTP client behind a port (`integrating-system-apis`); the fake-and-contract test pattern
itself (`.claude/rules/testing.md`); a new package such as a database library (the
Dependency Policy in `.claude/rules/project.md`).

## Why SwiftData behind a port

SwiftData is first-party, so persistence costs no dependency, and it ships a versioned
schema and a migration plan from day one, so the first model change is a migration
rather than a data loss. Core Data is not used: SwiftData is its successor on this OS
floor. Core never sees either: the repository is a port in Core's vocabulary, so every
Core test runs without SwiftData, and the store stays replaceable.

Where the state is kept, and in what format — the schema and its migration plan, CloudKit
sync, `UserDefaults` keys, files — is a design change (`AGENTS.md`'s "Before changing the
architecture"), and the stored shape is contract (`AGENTS.md`'s "What is contract and
what is private"). A pull request that changes either rewrites this skill in place.

## Where each piece lives

| Piece | Home |
|---|---|
| The port, its error enum, and the domain value | `Sources/MyAppCore/TodoRepository.swift`, `TodoItem.swift` |
| The null object for "no store" | `Sources/MyAppCore/UnavailableTodoRepository.swift` |
| The one container, the schema, the migration plan, the adapter | `Sources/MyAppPlatform/Persistence/` |
| The preferences port, `PreferenceKey`, and every key | `Sources/MyAppCore/Preferences/` |
| The `UserDefaults` adapter | `Sources/MyAppPlatform/Preferences/UserDefaultsPreferences.swift` |
| Fakes and contracts | `Tests/MyAppTestSupport/` (`InMemoryTodoRepository`, `TodoRepositoryContract`, `InMemoryPreferences`, `PreferencesContract`) |
| Store, migration, and adapter tests | `Tests/MyAppPlatformTests/` |

`@Model` types, `ModelContainer`, and `ModelContext` appear only in
`Sources/MyAppPlatform/Persistence/` (`.claude/rules/swift.md`'s Persistence). Enforced
by: `.swiftlint.yml`'s `no_ui_import_in_core` and `ArchitectureBoundaryTests` (Core never
imports SwiftData or names `UserDefaults`).

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
  the adapter maps every SwiftData error into one of them and logs the detail
  (`.private`), so Core handles a closed set and never learns which store failed. Error
  payloads carry identifiers, never titles — an error can reach a log or a crash report
  (`designing-errors`).
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

## Before you call it done

- [ ] No `@Model`, `ModelContainer`, or `UserDefaults` outside `MyAppPlatform`;
      `just lint` and `just test` pass.
- [ ] A changed stored shape is a new schema version plus a migration stage, with a test
      that opens a store the previous version wrote — never an edit to a shipped version.
- [ ] A changed preference key or default reads the old one and migrates it in Core, with
      a test that starts from the old value.
- [ ] The contract runs against the fake and the adapter, and both pass.
- [ ] The pull request rewrites this skill where the persistence design changed.
