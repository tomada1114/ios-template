# The SwiftData adapter

`SwiftDataTodoRepository` is an `actor` annotated `@ModelActor`: SwiftData gives it a
`ModelContext` bound to its own serial executor, so no model object leaves the actor and
the main actor never waits on a write it did not ask for. Everything below lives in
`Sources/MyAppPlatform/Persistence/`.

## One store, one container, for the whole app

`PersistenceStore.makeContainer(storage:)` opens the one `ModelContainer`, from the
app-wide `AppSchemaV1` and `AppMigrationPlan`, and every repository takes it through the
`init(modelContainer:)` `@ModelActor` generates (`.claude/rules/platform.md` ›
Persistence). The reason there is only one: a second container with a different schema
over the same default store file risks failing to open or damaging the store. Each
repository is its own actor with its own `ModelContext` over the shared container, so
two of them see each other's saved writes (`PersistenceStoreTests`).

- **`Storage`** picks the file: `.onDisk` (SwiftData's default store, for the app),
  `.inMemory` (UI tests under `-uiTesting`, and host tests), or `.file(URL)` (a test that
  must close a store and reopen the same file, as a migration test does).
- **A failed open is logged, then rethrown.** `makeContainer` logs SwiftData's error as a
  fault (`.private`: it can quote a path) and throws it unchanged; `App/` answers with
  `UnavailableTodoRepository` for every port the store would have served (`SKILL.md`'s
  "A repository is a port").
- **A failed save rolls the context back** (`.claude/rules/platform.md` › Mapping
  framework errors).

## The schema is versioned from day one

The schema (`AppSchemaV1`, `AppMigrationPlan`) is the whole app's, not one entity's. The
stored shape is contract: every store already on a user's device depends on it, which is
why a shipped schema version is never edited (`.claude/rules/platform.md` ›
Persistence) and the next change to `TodoRecord` is an `AppSchemaV2` with its stage.

- A second entity is the same move: a `@Model` in `AppSchemaV2` plus a stage in
  `AppMigrationPlan`, and a repository over the shared container.
- The store records the model's entities, attributes, and version identifier — never
  the Swift names of the schema or the plan — so a store written before both were
  renamed to their `App` names opens unchanged (`PersistenceStoreTests` reopens one
  written by a frozen copy of the old schema, `PreRenameSchemaV1`).

## Uniqueness and CloudKit sync

`@Attribute(.unique)` on the identifier makes a save with a known id an update. CloudKit
sync does not allow unique constraints; an app that turns sync on replaces it with a
fetch-before-insert in a new schema version. Turning sync on is a design change and an
entitlement (iCloud), so it needs the owner's sign-off (`AGENTS.md`'s "Security and human
approval") and rewrites this section.
