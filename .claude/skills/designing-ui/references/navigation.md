# Navigation: routes, the path, sheets, and deep links

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
still up (`dismissSheet()` whatever is up), `open(_:)` handles a deep link. `App/`'s scene root holds it in `@State` and hands it to the root view, while
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

A failure presents over a sheet that is up. SwiftUI presents nothing from a view that is
already presenting a sheet, so `RootView`'s `.failureAlert` outside the stack cannot show
while a sheet is up; the `sheet(for:)` content therefore carries the same
`.failureAlert`, over the same view model's failure and its `dismissFailure()`, and the
root's alert is handed no failure while a sheet is up, so one failure is never bound to
two alerts at once. While a
sheet is up the failure shows over it, at once, wherever the action that failed began —
a save still in flight from the list when the sheet opened, or the first sheet whose own
action can fail — and dismissing it leaves the sheet up; with no sheet up, the root's
alert shows it. The failure is not deferred until the sheet closes: a sheet that edits
something has to show its own failure while the person is still looking at it, and a
failure held back would show over a screen that no longer explains it. Every sheet gets
this from the one `sheet(for:)` call site, so a new sheet adds nothing for it.
`LaunchTests` pins it: under `-failUpdates -delayFailedUpdates` (Debug-only,
`App/MyAppApp.swift`) a toggle's failure arrives seconds after the tap, the test opens
the About sheet over the save still in flight, and the alert presents over the sheet.

Full-screen covers, popovers, and a sheet presented from inside a sheet are not modeled.

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

## Tabs, split views, and restoration are an app's

A tab-based app keeps one `NavigationModel` per tab, one stack each; tabs versus a single
stack is the design lock's navigation field ([design-lock.md](design-lock.md)).
`NavigationSplitView` and state restoration (`@SceneStorage` over `path`) are likewise an
app's to add.
