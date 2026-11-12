# View models, reentrancy, and the composition root

Why the template's view models are owned the way they are, how they survive a re-entered
`await`, and how `App/` and `AppModel` wire them. The shape every view model takes —
action-shaped, derived state computed, injected time and identity, no side effects in
`init`, built by `AppModel` — is `.claude/rules/core.md` › View models; how a view holds
one is `.claude/rules/ui.md` › Views and their models. The worked example is the to-do
list: `TodoListViewModel`, `TodoDetailViewModel`, `AppModel`, and `App/MyAppApp.swift`.

## Why this shape

- Derived state (`canAdd`, `showsEmptyState`, `showsLoadFailure`, `showsProgress`) and
  wording are computed in Core so the view has no `if` of its own worth testing, and the
  coverage floor sees every decision a screen makes.
- A shared view model is built once by `AppModel`, which `App/` creates in `@State`, so
  it outlives any one view tree. A pushed screen's model is built when its route is
  pushed and kept in the screen's `@State` while it is shown ("The composition root",
  below); construction having no side effects is what lets a re-render build a spare one
  and discard it.

## Reentrancy

A `@MainActor` method that `await`s can be re-entered by the next tap before it resumes.
The view model is written for that:

- An in-flight add sets `isAdding`, which disables Add, so a double tap stores one item.
- After an `await`, a row is found again by identifier rather than by a remembered index —
  the list may have changed in between (`toggle(_:)`).
- The draft is cleared only if it still holds what was submitted, so text typed while a
  save was in flight survives (`addDraft()`).
- Loads overlap — the list's `.task`, pull-to-refresh, Retry, and the detail screen's
  `.task` all call `load()` — and the newest one wins. Each load takes a generation
  number; one that returns after a newer load started drops its result, success or
  failure, so a slow, stale fetch never overwrites a newer one.
- A load replaces `items` wholesale, so a write that finished while it was in flight
  could vanish: the fetch may have read the store before the write landed. Every add,
  toggle, and delete the repository acknowledges during the newest load is recorded and
  replayed over the loaded items — a save replaces or adds by identifier, a delete
  removes — which changes nothing when the fetch already saw the write. Replaying, rather
  than loading again after the edit, costs no second fetch and cannot loop.
- A cancelled load leaves `items` untouched and `phase` back to what it was before the
  load, so a first load cancelled when its screen left leaves the list `idle` and the
  next appearance asks again. It reads `Task.isCancelled` after the fetch because
  `TodoRepositoryError` has no cancellation case (`.claude/rules/core.md` ›
  Cancellation).

Each of these has a test in `TodoListViewModelTests` that drives the interleaving through
the fake's `onSave` hook, or its `onFetch` hook, which runs after a fetch has read the
store and before it returns — the window in which a fetch's answer goes stale.

## The composition root

`App/MyAppApp.swift` is the one place that knows both halves of every port. It picks the
storage and the preferences suite from the launch arguments, opens the one SwiftData
container (`PersistenceStore`) and builds every SwiftData repository over it, falls back
to the null object when the container will not open (`persisting-data`), and builds one
`AppModel` in `@State`, handing it the adapters as ports through its initializer. Each
scene's root (`SceneRoot`) owns that scene's `NavigationModel`, forwards opened URLs to
it (`.onOpenURL`), and renders `MyAppUI`'s `RootView` over the app model and the
navigation model. It also parses `Bundle.main.infoDictionary` once into Core's
`AppConfiguration` and builds the `APIClient` at its base URL (the
`integrating-system-apis` skill's `references/http-client.md`): the parsing is Core's,
so `App/` hands over a dictionary and decides nothing about it. `App/` chooses adapters
and nothing else.

`AppModel` (`Sources/MyAppCore/AppModel.swift`) does the rest of the wiring — the shared
models as stored properties, one factory per route that needs a model of its own. Why it
is shaped that way:

- **It is not a service locator.** There is no registry, no lookup by type, and no
  global: every dependency is a named initializer parameter `App/` passes, and every
  model is built by a named method. A second port is a new initializer parameter, which
  a factory needing it keeps as a named stored property.
- **It is in Core, not `App/`,** so `AppModelTests` builds a route's view model over the
  fakes in `MyAppTestSupport` and the coverage floor sees the wiring. Factory closures
  assembled in `App/` were the alternative: they would leave the wiring where no
  coverage-gated test reaches it.
- **It is app-level, never per scene.** Per-window state — the navigation path — stays
  in the scene's own `NavigationModel` (the `designing-ui` skill's
  `references/navigation.md`).
