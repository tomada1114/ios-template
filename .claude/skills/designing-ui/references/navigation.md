# Navigation: routes, the path, sheets, deep links, and restoration

Why navigation is shaped the way it is. The rules a view follows — one
`NavigationStack(path:)` and one `navigationDestination(for: AppRoute.self)` in
`RootView`, `NavigationLink(value:)` in a screen, a new screen as a new `AppRoute` case —
are `.claude/rules/ui.md` › Navigation, sheets, and alerts; this file holds the reasoning
and the parts no rule states.

Which screen shows, and which sheet is presented over it, is Core state, not `@State`
inside a view, so a deep link and state restoration have something to hold on to and a
test can drive navigation without a view.
The template binds its one stack to a Core `NavigationModel` and parses a custom URL
scheme (`my-app`, `project.yml`'s `info:` block) with Core's `DeepLink`. A custom scheme
is an `Info.plist` entry, not an entitlement; universal links (Associated Domains) are an
app's decision, and an entitlement (`starting-an-app`).

## Routes are a Core enum

`AppRoute` (`Sources/MyAppCore/Navigation/`) has one case per pushable screen, carrying
an identifier rather than the value it shows: `.todoDetail(TodoItem.ID)`. The
destination's view model looks the item up when the screen renders
(`TodoDetailViewModel.content`, through `TodoListViewModel.item(withID:)`, which searches
every item, not only the visible ones), so a pushed screen shows the current state, and
an identifier nothing holds shows a not-found state.

## The path is a Core view model, owned per scene

`NavigationModel` is a `@MainActor @Observable` class holding `path: [AppRoute]` and
`sheet: AppSheet?`, with one action per intent: `show(_:)` pushes, `popToRoot()` returns,
`present(_:)` presents a sheet, `dismissSheet(_:)` dismisses the named sheet if it is
still up (`dismissSheet()` whatever is up), `open(_:)` handles a deep link, and
`restore(from:)` puts back a stored path ("The path is restored per scene", below).
`App/`'s scene root holds it in `@State` and hands it to the root view, while
the shared view models it routes between stay app-level, in `AppModel`. It never moves
into `AppModel`: the app supports multiple scenes (two windows on iPad), so an app-level
path would move every window in lockstep and a deep link would move them all.

## Why the stack and its destinations live in `RootView`

The back button writes the path back, which is why `path` is the one settable property;
`sheet` is `private(set)`, and the sheet binding writes back through `dismissSheet(_:)`.
Declaring every destination in one switch means a new screen adds an `AppRoute` case and
a branch of that switch, and edits no other screen.

The switch cannot build a pushed screen's view model over a port itself — `MyAppUI` may
not import `MyAppPlatform` — so it calls the route's `AppModel` factory. A later
re-render builds a fresh model that the screen discards unused (which is why
construction has no side effects), and each destination is identified by its route, so a
deep link that swaps one pushed item for another gets a fresh screen and model.

## Sheets are a Core enum too

`AppSheet` (`Sources/MyAppCore/Navigation/`) has one case per sheet, carrying at most an
identifier, like a route, and is its own `Identifiable` id, so `.sheet(item:)` presents
a new sheet when the case changes. `RootView` holds the one `.sheet(item:)`, outside the
stack so it presents over whichever screen is pushed, bound through a `Binding` whose
getter reads `sheet` and whose setter, on a write of `nil` (a swipe down), calls
`dismissSheet(_:)` with the sheet that was up when the binding was built; any other write
is ignored. The sheet's close button calls the same action with the sheet it closes. A
dismissal therefore names its sheet, and one that arrives after another sheet was
presented leaves the new one up. Its `sheet(for:)` switch builds each sheet, as `destination(for:)` builds each
pushed screen; a sheet that edits something takes its view model from an `AppModel`
factory there. The template's sheet is `.about` (`AboutView`): static Core wording and
the system's close button, the smallest sheet that has a dismiss action. Its button sits
in `TodoListView`'s one `.primaryAction` toolbar group, after Hide Completed, and calls
the closure `RootView` passes, which presents it.

One sheet presents at a time: `present(_:)` replaces a sheet already up rather than
stacking one on it. The sheet sits over the stack, so everything that moves the stack
dismisses the sheet: a write to `path` that changes it (its `didSet`), and the actions
`show(_:)`, `popToRoot()`, and a link `open(_:)` accepts; otherwise the screen it asked for would change out of sight under the sheet, and the
person would close the sheet onto a stack they did not see move. A link `open(_:)`
rejects leaves both the path and the sheet alone.

A failure presents over a sheet that is on screen. SwiftUI presents nothing from a view
that is already presenting a sheet, so an alert outside the stack cannot show while a
sheet is up. `RootView` therefore attaches every failure alert to each presentation
layer — the stack, and the `sheet(for:)` content — through one function,
`failureAlerts(on:isTopmost:)`, and hands the failures only to the topmost layer, so a
feature adds its alert once and one failure is never bound to two alerts in a window
(which window gets it at all is "A failure presents in one window", below). The topmost
layer is the sheet from the moment one is asked for until its `onDismiss` — after it has
finished sliding away, not when `NavigationModel.sheet` turns `nil` — because an alert
handed to the stack while the sheet is still leaving is dropped by UIKit and never comes
back. An alert's binding ignores SwiftUI's write-back and only its button clears the
failure: a sheet closed by code under its alert (a deep link) tears the alert down
without the person seeing it go, and the failure then presents again over the stack.

So a failure shows at once over the sheet, wherever the action that failed began — a
save still in flight from the list when the sheet opened, or the first sheet whose own
action can fail — and dismissing it leaves the sheet up. It is not deferred until the
sheet closes: a sheet that edits something has to show its own failure while the person
is still looking at it, and a failure held back would show over a screen that no longer
explains it. `LaunchTests` pins both halves: under `-failUpdates -delayFailedUpdates
<seconds>` (Debug-only, `App/MyAppApp.swift`) a toggle's failure arrives that long after
the tap, so the test opens the About sheet over the save still in flight; the alert
presents over the sheet, OK leaves the sheet up, and a deep link that closes the sheet
under the alert brings the alert back over the screen it pushed.

Full-screen covers, popovers, and a sheet presented from inside a sheet are not modeled.

## A failure presents in one window

The list is app-wide and every window renders it, so a failure presented wherever it is
set would show in every window at once, and OK in one would pull the alert out from under
the person in another. Core therefore hands one failure to exactly one window. A shared
model holds its failure as a `ReportedFailure` — the failure and the scene whose action
caused it, one value so the two cannot disagree — and each `RootView` reads it through
its own scene's `SceneLifecycleModel`: `lifecycle.presented(app.todoList.reportedFailure)`
is that value in the presenting window and `nil` in every other. The alert's button
hands the value it was shown back (`dismissFailure(_:)`), so it dismisses that failure
and no other.

The presenter is chosen once, when the failure is reported:

1. **The window whose action caused it, if that window is in the foreground.** The alert
   shows beside the row whose change failed. A view passes its window with every action
   that can fail — `toggle(_:from:)`, `addDraft(from:)`, `delete(atOffsets:from:)`,
   `load(from:)` — as a `SceneID`, which is `SceneLifecycleModel.id`; a pushed screen's
   model gets it from its factory (`makeTodoDetailViewModel(id:scene:)`). `from:` has no
   default, so a call site says which window asked, or `nil` when none did (work Core
   starts on its own).
2. **Otherwise, the window that has been in the foreground longest.**
3. **Otherwise — no window is in the foreground — the first open window.** With no
   window open at all, the failure waits for the first one to open.

**The presenter is sticky.** It keeps the failure until its window closes, or goes to the
background while another window is in the foreground; the failure then goes to a window
chosen by the same three steps. Nothing else moves the alert:

- A window coming back to the foreground takes nothing, even when its own action caused
  the failure: the person may be reading the alert in the window that took it.
- While every window is in the background the presenter does not change, and a window
  that comes back before the presenter does not take the failure. An app-wide trip
  through the background therefore leaves a single window's alert up, and two windows'
  alert where it was — provided the presenter is not reported in the background while
  the other window is still recorded in the foreground. Windows report one at a time,
  and Core cannot tell that case from one window being put away, so the failure then
  moves to the other window, and stays there.
- An `inactive` window — Control Center, the app switcher — is still in the foreground.
- One failure is held at a time, as in one window: a second failure replaces the first,
  and its presenter is chosen afresh by the three steps, wherever the first ended up.

Stickiness is why the presenter is stored and not computed from the phases on every
render: a computed answer follows the phases, so the alert would return to the window
that caused it, or hop to whichever window came back first, under a person who had
started reading it elsewhere.

The windows are known to Core through what they already report. `AppModel` keeps one
internal list of open windows (`OpenScenes`), in the order each last came to the
foreground, and hands it to every `SceneLifecycleModel` and every shared view model it
builds. A scene joins on the first phase it reports — every phase but `background`
counts as the foreground, and `App/` maps a phase a later SDK adds to `background` so an
unknown phase never makes a window a candidate — never when it is built, because
`SceneRoot` builds a spare model on every re-render. It leaves when `SceneRoot`'s
`onDisappear` calls `sceneDidClose()`: an observed change, so the next window re-renders
and presents at once. A phase reported after a close opens the window again, so a close
delivered for a window that is still there costs nothing lasting. The list holds each
scene weakly, only so a window that went without closing is not kept alive; it is
dropped at the next change any window reports.

A shared model reports a failure through a `FailureSlot`, which claims the presenter
from `OpenScenes` and gives the claim up when the failure is dismissed or replaced. A
second shared model keeps a slot of its own over the same `OpenScenes`, exposes its
`ReportedFailure`, and adds one `.failureAlert` line to `RootView`; nothing in
`SceneLifecycleModel` or `OpenScenes` names a feature.

An app-wide coordinator that owns every failure was the alternative: it would put a
second owner beside each view model's failure, to decide what a claim on the list of
open windows already decides. Presenting in the key window only was the other: windows
side by side are all active at once, and Core has no way to tell which one the person
last touched, so it could not say which window a failed toggle belongs to. No UI test
opens a second window; `FailurePresentationTests` pins every rule above, and the failure
launch test pins that a single window still presents its own.

## Deep links are parsed in Core

`DeepLink.route(for:)` accepts exactly `my-app://todo/<uuid>` — the scheme in any case,
the host `todo`, one `UUID` path component — and rejects every other shape rather than
guessing; `DeepLink.url(for:)` is its inverse. The scene root forwards `.onOpenURL` to
its `NavigationModel.open(_:)`, which replaces the path with the parsed route (dismissing
any sheet) or logs the rejected link's scheme and host in the `navigation` category.

No link presents a sheet: About is not worth a URL that becomes contract the day a build
ships. A sheet that is worth one gets a new link shape in `DeepLink` (for example
`my-app://about`), parsed to a value that names either a route or a sheet — `DeepLink`
then returns that value instead of an `AppRoute` — and `open(_:)` switches on it, calling
`present(_:)` for a sheet over the path it leaves as it is. The new shape gets its
`DeepLinkTests` cases and `NavigationModelTests` for what it leaves behind, and every
old shape keeps parsing.

The scheme is registered under `project.yml`'s `info:` block (XcodeGen writes the
gitignored `App/Info.plist` from it on every `just generate`, and the build merges it
with the `INFOPLIST_KEY_*` settings). `DeepLinkTests` fails when the scheme Core parses
and the one `project.yml` registers differ, and `scripts/bootstrap.sh` rewrites both
together. The scheme is contract once a build has left your machine (`AGENTS.md`'s "What
is contract and what is private").

## The path is restored per scene

The system ends a backgrounded app whenever it wants the memory, and a person coming
back expects the screen they left. So each window's path outlives its process:
`SceneRoot`'s `PathRestoration` modifier keeps `NavigationModel.encodedPath` in
`@SceneStorage` — the system's per-scene store, so two iPad windows restore two different
paths — writing it whenever `path` changes, and hands the stored bytes to
`NavigationModel.restore(from:)` when the scene appears, in a transaction with
animations disabled, so the window opens on the restored screen instead of pushing it
over the list. Right after the restore it stores `encodedPath` again: bytes that
restored nothing, or only in part, are replaced by the path the person now sees, so
they are logged once rather than at every launch, and a later build that could read
them never brings back a screen this launch did not show. `App/` only carries the bytes; what they mean is Core's, and
`NavigationModelRestorationTests` covers every branch.

- **Once, and only onto an untouched path.** `restore(from:)` applies the first time it
  is called and only while nothing has changed the path. A deep link that launched the
  window, or a push, is newer than what was stored and wins, whether it reaches the
  model before or after the scene appears — the order SwiftUI delivers `.onOpenURL` and
  `.onAppear` in is not something the result depends on. Every later call does nothing.
- **Never a crash, and never a stack that did not exist.** The path restores up to the
  first route this build cannot read (a screen a later build stored, a damaged
  identifier) and stops there. The screens above an unreadable one were pushed from it,
  so joining what lies either side of it would show a stack the person never saw, with
  a back button leading somewhere they never were. Bytes that are not a stored path, or
  are of a version this build does not know, restore nothing: the window opens at the
  root. Both are logged in the `navigation` category, and apart: an unknown version is
  what a downgrade leaves behind, so it is a notice carrying the version number, while
  bytes that are not a stored path are an error, by size only.
- **A route to an item that no longer exists is restored.** `NavigationModel` holds
  routes, not items, and the list has not loaded when a scene is rebuilt, so restore
  cannot ask whether the item is still there, and it does not wait to find out. The
  detail screen already answers the question: it shows progress while the list loads
  (`TodoDetailViewModel` starts that load itself) and its not-found state if the item is
  gone, exactly as a stale deep link does. Dropping the route instead would need the
  navigation model to know about every feature's data.
- **A presented sheet is not restored.** Only the path is stored, so a restored window
  has no sheet up. A sheet is a short detour over a screen, and the screen is what the
  person returns to; About restored over the list would be noise, and a sheet holding a
  half-typed draft would come back empty, since no view-model state is stored either.
  An app whose sheet must survive stores it beside the path, as a second field of the
  stored form, and restores it in the same action.
- **Nothing but the path.** Drafts, scroll position, and Edit mode start fresh.
- **Not under UI testing.** With `-uiTesting`, `SceneRoot` leaves the `PathRestoration`
  modifier off — the one place the opt-out is read — so nothing is stored, read, or
  encoded, and the launch walk starts at the root whatever an earlier launch left
  pushed.

How long a scene's storage lives is the system's rule, not this app's: it is kept
while the system may bring the scene back, and goes with the scene when the scene is
discarded.

### The stored form is contract

A stored path is read by whichever build launches next, so its format is contract once
a build has left your machine (`AGENTS.md`'s "What is contract and what is private").
It is UTF-8 JSON with sorted keys:

```json
{"routes":[{"id":"00000000-0000-0000-0000-000000000001","screen":"todoDetail"}],"version":1}
```

`StoredNavigationPath` (`Sources/MyAppCore/Navigation/`) owns the envelope and
`AppRoute`'s hand-written `Codable` conformance owns one route. Neither is synthesized:
synthesized enum coding takes its keys from the Swift case and label names, so renaming
`todoDetail` would silently stop every stored path from restoring. Here the Swift name
is free to change and the stored name (`"todoDetail"`, the `screen` and `id` keys) is
not. `NavigationModelRestorationTests` pins the bytes in both directions, from a literal
typed by hand: a change that alters what is written, or stops reading what was, fails
it.

- A new screen adds its stored name and a branch in `AppRoute`'s `init(from:)` and
  `encode(to:)`, with a test for its literal. An older build's path ends before it.
- A removed screen's routes stop decoding, and a stored path ends at the first of them;
  nothing else is needed.
- A case that gains a value must keep decoding the form stored without it: read the new
  value with `decodeIfPresent` and a default, and keep the old form's literal test beside
  the new one. No gate enforces this; the literal tests are what fail when it is broken,
  so they are never edited to pass.
- A change old builds' payloads cannot survive — a different envelope, a route that is
  no longer an object — takes `version` 2, written from then on, while
  `StoredNavigationPath.routes(from:)` keeps reading version 1. The version is read
  before the routes, so a build never guesses at a newer shape: it opens at the root.

The `@SceneStorage` key (`navigation.path`, in `SceneRoot`) is not contract in the same
way: under a new key each window opens at the root once, and nothing is misread.

## Tabs and split views are an app's

A tab-based app keeps one `NavigationModel` per tab, one stack each — and one stored
path per tab, each under its own `@SceneStorage` key; tabs versus a single stack is the
design lock's navigation field ([design-lock.md](design-lock.md)). `NavigationSplitView`
is likewise an app's to add.
