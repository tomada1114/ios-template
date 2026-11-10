# Navigation: routes, the path, and deep links

Why navigation is shaped the way it is. The rules a view follows — one
`NavigationStack(path:)` and one `navigationDestination(for: AppRoute.self)` in
`RootView`, `NavigationLink(value:)` in a screen, a new screen as a new `AppRoute` case —
are `.claude/rules/ui.md` › Navigation, sheets, and alerts; this file holds the reasoning
and the parts no rule states.

Which screen shows is Core state, not `@State` inside a view, so a deep link and state
restoration have something to hold on to and a test can drive navigation without a view.
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

`NavigationModel` is a `@MainActor @Observable` class holding `path: [AppRoute]`, with
one action per intent: `show(_:)` pushes, `popToRoot()` returns, `open(_:)` handles a
deep link. `App/`'s scene root holds it in `@State` and hands it to the root view, while
the shared view models it routes between stay app-level, in `AppModel`. It never moves
into `AppModel`: the app supports multiple scenes (two windows on iPad), so an app-level
path would move every window in lockstep and a deep link would move them all.

## Why the stack and its destinations live in `RootView`

The back button writes the path back, which is why `path` is the one settable property.
Declaring every destination in one switch means a new screen adds an `AppRoute` case and
a branch of that switch, and edits no other screen.

The switch cannot build a pushed screen's view model over a port itself — `MyAppUI` may
not import `MyAppPlatform` — so it calls the route's `AppModel` factory. A later
re-render builds a fresh model that the screen discards unused (which is why
construction has no side effects), and each destination is identified by its route, so a
deep link that swaps one pushed item for another gets a fresh screen and model.

## Deep links are parsed in Core

`DeepLink.route(for:)` accepts exactly `my-app://todo/<uuid>` — the scheme in any case,
the host `todo`, one `UUID` path component — and rejects every other shape rather than
guessing; `DeepLink.url(for:)` is its inverse. The scene root forwards `.onOpenURL` to
its `NavigationModel.open(_:)`, which replaces the path with the parsed route or logs the
rejected link's scheme and host in the `navigation` category.

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
