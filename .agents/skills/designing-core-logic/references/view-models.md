# View models, reentrancy, and the composition root

How the template's view models are owned, how they survive a re-entered `await`, and how
`App/` and `AppModel` wire them. The worked example is the to-do list:
`TodoListViewModel`, `TodoDetailViewModel`, `AppModel`, and `App/MyAppApp.swift`. The
shape every view model takes — action-shaped, injected time and identity, no side effects
in `init` — is `SKILL.md`'s "Action-shaped view models"; this file is the rest.

## View models

A view model is a `@MainActor @Observable final class` in Core. The template's is
`TodoListViewModel`.

- **Action-shaped.** The view calls one method per user intent — `addDraft()`,
  `toggle(_:)`, `delete(atOffsets:)` — and never mutates published state itself. State is
  `public private(set)`; the only settable property is what a control binds to
  (`draftTitle`).
- **Derived state lives here.** `canAdd`, `showsEmptyState`, `showsLoadFailure`,
  `showsProgress` are computed in Core so the view has no `if` of its own worth testing.
- **Wording lives here.** Core returns `LocalizedStringResource` from its String Catalog
  (`TodoListStrings`, `TodoListFailure.message`); a view renders it with `Text(_:)` and
  shows user data with `Text(verbatim:)` (`localizing-the-app`).
- **Time and identity are injected** (`now: () -> Date`, `makeID: () -> UUID`) so a test
  pins both. The same goes for anything nondeterministic an app adds: a `Clock`, a
  `Locale`, a random number generator.
- **Construction has no side effects.** Nothing is read until `load()`; the view calls it
  from `.task` on first appearance.
- **Ownership.** A view model every scene shares (`TodoListViewModel`) is built once by
  Core's `AppModel`, which `App/` creates in `@State` (so it outlives any one view tree);
  the view holds it with `@Bindable` only to bind controls. A pushed screen's own view
  model (`TodoDetailViewModel`) is built by an `AppModel` factory when the route is
  pushed, and the screen keeps it in `@State` for as long as it is shown ("The
  composition root", below).

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
- A cancelled load is a no-op: no failure, `items` untouched, and `phase` back to what it
  was before the load, so a first load cancelled when its screen left leaves the list
  `idle` and the next appearance asks again. The view model reads `Task.isCancelled`
  after the fetch rather than a port case: `TodoRepositoryError` has no cancellation
  case, so a store that sees its caller cancel can only report a failure, which the
  cancelled caller no longer wants (`designing-errors`, Cancellation propagates).

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
navigation model. `App/` chooses adapters and nothing else.

`AppModel` (`Sources/MyAppCore/AppModel.swift`) is a `@MainActor @Observable final
class` in Core that does the rest of the wiring:

- **It holds the view models every scene shares** — today `todoList`, the one
  `TodoListViewModel` every window shows — built once over the ports it was handed.
- **It has one `make…ViewModel(…)` factory per route whose screen needs a view model of
  its own** — today `makeTodoDetailViewModel(id:)`, which builds a
  `TodoDetailViewModel` over the shared list. A factory whose model needs a port builds
  it over a port `AppModel`'s initializer was handed and keeps as a named stored
  property.
- **It is not a service locator.** There is no registry, no lookup by type, and no
  global: every dependency is a named initializer parameter `App/` passes, and every
  model is built by a named method. A second port is a new initializer parameter.
- **It is in Core, not `App/`,** so `AppModelTests` builds a route's view model over the
  fakes in `MyAppTestSupport` and the coverage floor sees the wiring. Factory closures
  assembled in `App/` were the alternative: they would leave the wiring where no
  coverage-gated test reaches it.
- **It is app-level, never per scene.** Per-window state — the navigation path — stays
  in the scene's own `NavigationModel` (`building-swiftui-screens`'
  `references/navigation.md`).
