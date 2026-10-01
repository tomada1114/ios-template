---
name: designing-errors
description: >
  Covers how errors are designed in this Swift 6 repository: error enums declared in
  MyAppCore, typed throws(SomeError) versus plain throws, what an error payload and an
  AppLog (os.Logger) message may carry, propagating CancellationError instead of
  swallowing it, and how a MyAppPlatform adapter maps a SwiftData or Foundation error
  (NSError, CocoaError) into a Core error. Use when adding or changing an Error type, a
  throwing function or port, a do/catch, a Task that can be cancelled, or an adapter
  that calls a failing framework API.
---

# Designing Errors

**Owns:** the shape of an error type, the choice between typed and untyped `throws`,
what an error and its log line may contain, cancellation, and the framework-to-Core
error mapping at the adapter boundary. **Does not own:** writing the failing test first
(`tdd`); how Core logic is shaped around time and state (`designing-core-logic`); the
`os.Logger` basics (`.claude/rules/swift.md` › Logging); the error-path test rule
(`.claude/rules/testing.md` › What to Test).

## Where an error type lives

- Declare every error a caller can observe in `MyAppCore`, next to the port or model
  that throws it — `TodoRepository.swift` holds `TodoRepositoryError`. A Core view model
  switches on it, and the fake in `Tests/MyAppTestSupport` throws it, so it cannot live
  in `MyAppPlatform` (Core never imports Platform).
- One `enum` per failure domain, `Error, Equatable, Sendable`. Cases name what went
  wrong for the caller (`.notFound`, `.storageFailure`), not which API failed.
- Payloads carry only what a caller needs to decide, and are `Sendable` values:
  identifiers (`TodoItem.ID`), small enums, durations. Never an `NSError` or an
  underlying `any Error` — those are not `Equatable`, often not `Sendable`, and leak the
  adapter's mechanism into Core.

The worked example, as `TodoRepository.swift` declares it (doc comments trimmed):

```swift
public enum TodoRepositoryError: Error, Equatable, Sendable {
    case corruptedRecord(TodoItem.ID)
    case notFound(TodoItem.ID)
    case storageFailure
}
```

## Typed throws or plain throws

Typed throws (`throws(TodoRepositoryError)`, SE-0413) needs Swift 6.0
(<https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md>,
"Implemented (Swift 6.0)", checked 2026-09-30); this package is
`swift-tools-version: 6.4` in Swift 6 language mode, so it is available everywhere.

- **Use `throws(E)`** when the caller decides by `E`'s cases: a port method, a
  view-model action whose UI shows per-case recovery. The `catch` then binds `error` as
  `E`, a `switch` over it is exhaustive, and adding a case breaks every caller that must
  handle it — which is the point.
- **Use plain `throws`** when the caller only propagates or reports failure, or when
  the body calls several throwing APIs of unrelated types. Forcing a typed throw there
  means wrapping every inner error for no decision anyone makes.
- Never `throws(any Error)` (it is plain `throws`) and never a catch-all case such as
  `.unknown(any Error)` to make a typed throw compile — map to a real case instead.

`TodoRepository` throws `TodoRepositoryError` from every method, and
`TodoListViewModel.delete(_:)` decides on one case by pattern:

```swift
do {
    try await repository.delete(id: id)
} catch .notFound {
    // Already gone: what the user asked for is true, so the row goes too.
} catch {
    report(.deleteFailed, error)  // error is a TodoRepositoryError here
    return
}
```

An empty result is not a failure: `fetchAll()` on an empty store returns `[]`, and an
error is for "could not find out". Absence becomes a throw only where the port promises
the caller must hear about it — `delete(id:)` reports `.notFound` so a caller whose list
is stale finds out, and the caller then decides it is harmless.

## No user data in errors or logs

- An error payload never holds user content: no to-do titles, typed text, file paths,
  URLs, or identifiers of the user's documents outside the app. Errors travel — into
  logs, crash reports, test output, and `String(describing:)`. `TodoRepositoryError`
  carries an item's identifier, never its title.
- Log lines follow `.claude/rules/swift.md` › Logging: `AppLog`'s `os.Logger` only.
  Interpolate an error code or an enum case with `privacy: .public`; anything that came
  from the user with `privacy: .private` — or leave it out. `os.Logger` redacts dynamic
  strings by default; do not mark one `.public` to make a log easier to read.
- Log once, where the error is handled, not at every layer it passes through.

## Cancellation propagates

`CancellationError` means the caller no longer wants the result. It is not a failure
to report.

- Do not catch it into a Core error case, a log line, or an error state. A plain
  `catch` in an `async throws` function must rethrow it:

```swift
do {
    try await clock.sleep(for: .seconds(1))
    try await refresh()
} catch let error as CancellationError {
    throw error  // cancellation is not a failure: never log or map it
} catch {
    AppLog.todos.error("refresh failed")
}
```

- A long loop calls `try Task.checkCancellation()` rather than polling
  `Task.isCancelled` and returning a half result silently.
- Typed throws and cancellation: a function that awaits cancellable work and declares
  `throws(E)` cannot throw `CancellationError`. Keep such functions on plain `throws`,
  or give `E` an explicit `.cancelled` case the caller treats as a no-op — never drop
  the cancellation on the floor.
- A test asserts cancellation with `#expect(throws: CancellationError.self)`.

## Mapping framework errors in an adapter

The adapter translates, never decides (`AGENTS.md` › Architecture). Mapping a framework
error to a Core case is translation; choosing what the app does about it is Core's.

- Convert at the call site, inside `MyAppPlatform`, into the Core enum the port
  declares. Nothing framework-typed crosses the port.
- **SwiftData.** `ModelContext.save()` and `fetch(_:)` throw. `SwiftDataTodoRepository`
  catches at the call site and maps to `TodoRepositoryError.storageFailure`, or to
  `.notFound`/`.corruptedRecord` where the adapter itself decides the case (a fetch that
  found no record, a stored record `TodoItem`'s initializer rejects). Its `save(_:)`:

```swift
do {
    if let existing = try record(id: item.id) {
        existing.update(from: item)
    } else {
        modelContext.insert(TodoRecord(item))
    }
    try modelContext.save()
} catch {
    // A failed save leaves the change pending in the context; drop it, or the
    // next successful save would write it after all.
    modelContext.rollback()
    throw Self.storageFailure(error, during: "save")
}
```

  `storageFailure(_:during:)` logs the framework error `.private` (SwiftData's messages
  can quote stored values) under `AppLog.persistence` and returns `.storageFailure`.
- **Foundation.** An `NSError` or `CocoaError` is mapped by its `code` to a Core case
  for the codes the adapter knows; every other code goes to the domain's general
  failure case. The `domain` and `code` go to the log with `privacy: .public`; the
  `localizedDescription` and `userInfo` never go into an error payload, since they can
  carry paths and user content.

```swift
let nsError = error as NSError
AppLog.persistence.error(
    "read failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)",
)
```

- **`URLError`.** `URLSessionHTTPClient.clientError(for:)` maps by `code` into
  `HTTPClientError`: `.cancelled` to `cancelled`; no usable connection
  (`.notConnectedToInternet`, `.cannotFindHost`, …) to `notConnected`; `.timedOut` to
  `timedOut`; every other code to `transport(code:)`. A `CancellationError` also maps to
  `cancelled` — the port throws typed, so cancellation is a case the caller treats as a
  no-op — and it is the one failure the adapter does not log.

A Platform test checks the mapping under plain `swift test` (`just test`) when the
framework runs on the host — SwiftData with an in-memory store does
(`SwiftDataTodoRepositoryTests` asserts `.corruptedRecord` for a record that breaks the
title invariant). A Core test checks the decision with the fake, which throws each Core
case on demand (`fail(_:with:)`).

## Checklist

- The error enum is in `MyAppCore`, `Error, Equatable, Sendable`, with value payloads.
- `throws(E)` only where a caller decides on `E`; plain `throws` otherwise.
- No user content in a payload; logs use `AppLog` with explicit privacy.
- `CancellationError` is rethrown, never logged or mapped to a failure.
- The adapter maps every framework error to a Core case; nothing framework-typed
  crosses the port.
- Each case has an error-path test asserting the case and payload.
