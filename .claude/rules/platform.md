---
paths:
  - "Packages/**/Sources/MyAppPlatform/**"
  - "Packages/**/Tests/MyAppTestSupport/**"
  - "Packages/**/Tests/MyAppPlatformTests/**"
---

# MyAppPlatform

An adapter translates and never decides. It sits outside the coverage floor, so any
branch on domain values belongs in Core, where a test sees it. Fakes and contracts are
`testing.md`; reaching a new iOS framework, a permission, or an `Info.plist` key is the
`integrating-system-apis` skill.

## Adapters

- An adapter implements a `Sendable` port Core declares. Core value types go in and come
  out; nothing framework-typed crosses the port.
- Its shape follows `swift.md` › Concurrency: an actor, or a `Sendable` struct holding
  only `Sendable` values.
- An iOS-only call sits inside `#if os(iOS)` around the smallest translation that needs
  it, never around a decision, and so does its test.

## Persistence

- `@Model` types, `ModelContainer`, and `ModelContext` appear only in
  `Sources/MyAppPlatform/Persistence/`, never in Core, a view, or `App/`. `App/` opens
  the app's one container through `PersistenceStore.makeContainer(storage:)` and hands
  it to each repository's `init(modelContainer:)` without importing SwiftData; no
  repository opens a container of its own.
- A SwiftData adapter is a `@ModelActor` actor that maps a record to a Core value inside
  the actor, so no `@Model` object crosses the port
  (`docs/architecture.md` › The SwiftData adapter).
- A shipped `VersionedSchema` (`AppSchemaV1`) is never edited: a changed or new stored
  model is a new schema version plus an `AppMigrationPlan` stage, with a test that opens
  a store the previous version wrote (`docs/architecture.md` › What is contract).

## Mapping framework errors

Mapping a framework error to the Core enum the port declares is translation; what the
app does about it is Core's (`core.md` › Errors). Convert at the call site.

- **SwiftData:** `SwiftDataTodoRepository` catches `save()` and `fetch(_:)` failures and
  throws `.storageFailure`, or `.notFound` / `.corruptedRecord` where the adapter itself
  decides the case (no record found, a stored record `TodoItem` rejects). A failed save
  calls `modelContext.rollback()` first, or the pending change would be written by the
  next successful save. `storageFailure(_:during:)` logs the framework error `.private`
  under `AppLog.persistence`, since SwiftData's messages can quote stored values.
- **Foundation (`NSError`, `CocoaError`):** map by `code` for the codes the adapter
  knows and send every other code to the domain's general failure case. Log `domain` and
  `code` with `privacy: .public`; `localizedDescription` and `userInfo` never enter a
  payload, since they can carry paths and user content.
- **`URLError`:** `URLSessionHTTPClient.clientError(for:)` maps `.cancelled` to
  `cancelled`, no usable connection (`.notConnectedToInternet`, `.cannotFindHost`, …)
  to `notConnected`, `.timedOut` to `timedOut`, and every other code to
  `transport(code:)`. A `CancellationError` also maps to `cancelled`, the one failure the
  adapter does not log.
- An SDK-owned enum (an `NSError` code, an imported C enum) is the one place a `switch`
  takes `default:` or `@unknown default:`; the unknown case is logged and never answers
  the permissive case.

## Verifying

`just test` runs every Platform test whose framework runs on the host (SwiftData with an
in-memory store does; `SwiftDataTodoRepositoryTests` asserts `.corruptedRecord` for a
record that breaks the title invariant) and the contracts against both the fake and the
adapter. `just test-ios` runs what sits behind `#if os(iOS)`; `just build` when `App/`
wires the adapter.
