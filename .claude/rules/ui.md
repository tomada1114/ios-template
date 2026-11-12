---
paths:
  - "Packages/**/Sources/MyAppUI/**"
  - "App/**"
  - "LaunchUITests/**"
---

# MyAppUI, App/, and LaunchUITests

A view renders Core state and forwards user intent to a Core action; it decides nothing.
`MyAppUI` is outside the coverage floor, so a branch in a view is a branch no gate tests.
`TodoListView` over `TodoListViewModel` is the worked example; copy its shape. What a
screen looks like — the design lock, a token's value, custom glass — is the
`designing-ui` skill; the view model itself is `core.md`.

## Views and their models

- A view is a `struct` importing `SwiftUI` and `MyAppCore`, never `MyAppPlatform`. It is
  `public` only when `App/` constructs it; a subview (`TodoRow`) stays `private` or
  internal.
- `App/` is the composition root and nothing else: it picks adapters and hands them to
  `AppModel` as ports. `MyAppApp` keeps the `AppModel` in `@State`; its `SceneRoot` keeps
  a `NavigationModel` in `@State` per scene, so each window navigates on its own.
- `SceneRoot` keeps a `SceneLifecycleModel` (`app.makeSceneLifecycleModel()`) in
  `@State` too, and forwards that window's `@Environment(\.scenePhase)`, mapped to Core's
  `LifecyclePhase`: `sceneDidEnter(_:)` synchronously in `onChange`, then
  `refreshIfNeeded()` in a `Task`. It decides nothing about the phase: whether one
  refreshes anything is Core's (the `designing-core-logic` skill's
  `references/view-models.md` › Lifecycle). It passes all three to
  `RootView(app:navigation:lifecycle:)`; the lifecycle model is also the window's
  identity there (`lifecycle.id`, a `SceneID`).
- A model every scene shares comes from `AppModel`
  (`TodoListView(model: app.todoList, scene: lifecycle.id)`); a pushed screen's model
  from its route's factory in `RootView`'s destination switch
  (`TodoDetailView(model: app.makeTodoDetailViewModel(id:scene:))`), held in
  `@State private var model` set with `_model = State(initialValue: model)`, so it keeps
  the first model while pushed and ignores the one a parent re-render builds.
- A view handed its model holds it as a plain `let`; `@Bindable` only when a control
  binds to the settable property (`TodoListView`'s field and `draftTitle`). A view that
  owns a portless model holds it in `@State`, set from an initializer parameter so a
  preview can inject a state.
- A binding to state the view may not set is built from an action, as
  `RootView`'s sheet binding (`presentedSheet`) does. Never widen a `private(set)`
  so `@Bindable` can reach it.
- Not used: `ObservableObject`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`.

## What `body` may contain

| In the view | In the Core view model |
|---|---|
| Layout, modifiers, the order things appear in | Whether an action is allowed now (`canAdd`) |
| Choosing a layout from size class or text size | Any rule, threshold, or comparison on domain values |
| Calling an action from a `Button`, `.onSubmit`, `.refreshable`, `.onDelete` | What the action does and the state it leaves |
| *When* to ask — `.task` | *What* asking means (`load()`) and which empty state shows |
| `Text(verbatim:)` for the user's own text | Every word a person reads, as a `LocalizedStringResource` |

- An action that waits is called from `.task` (cancelled with the view) or a `Task { }`
  in a button's closure.
- An action of a shared model that can fail is passed the window it was asked from
  (`model.toggle(item.id, from: scene)`), so its failure presents in that window and not
  in every window showing the model. The view only passes the `SceneID` it was handed;
  a preview, which has no window, passes `nil`.
- A view has no localizable literal: `Text("…")` looks up the app's main bundle, not
  Core's, so render a Core resource (`Text(TodoListStrings.emptyTitle)`). The user's
  text, a number, a glyph, or a preview's developer note is `Text(verbatim:)`.
- Spacing, radius, and hit-target numbers come from `DesignTokens`
  (`DesignSystem/DesignTokens.swift`); a number only one view needs goes in a
  `private enum Layout` in that file (`no_magic_numbers` rejects a bare one). Tokens
  stay in `MyAppUI`: they are presentation. The screen-edge inset is the system's
  (`List`, `Form`, `.padding()`), and a radius is always
  `RoundedRectangle(cornerRadius:style: .continuous)` on a container the system does not
  draw.
- When `body` nears `function_body_length`, extract a subview taking only the slice it
  renders (`TodoRow`).

## System first

The system's answer is the default for every visual question; a departure is a
design-lock decision, never a per-screen one.

- **Type:** text styles only (`.body`, `.footnote`), never a fixed point size;
  `@ScaledMetric` for a dimension that grows with text.
- **Color:** semantic only (`.primary`, `.secondary`, `.tint`, `.background`, the `.fill`
  styles), for their stated role. A custom color is a Color Set in `App/Assets.xcassets`
  with Any, Dark, and increased-contrast variants, added only by the lock; a literal RGB
  is a review finding. The accent is set once, in `AccentColor.colorset`.
- Every screen works in light, dark, and Increase Contrast
  (`@Environment(\.colorSchemeContrast)` reads `.increased`); system colors adapt on
  their own. Never convey state by color alone: `TodoRow` strikes through a done item
  and swaps its glyph as well as dimming it. Text contrast is at least 4.5:1, 7:1 for
  small text on a custom color (HIG › Dark Mode).
- Align to the spacing scale, and let alignment and grouping carry hierarchy before
  color or weight does.
- **Symbols and controls:** SF Symbols (`Image(systemName:)`, `Label`) and standard
  components in their default styles, which carry Liquid Glass and accessibility.
- **Toolbars:** the system placements (`.primaryAction`, `.confirmationAction`,
  `.cancellationAction`, `.bottomBar`), never a hand-built bar.
- **Haptics:** `.sensoryFeedback` only where the lock allows it, with the system pattern
  whose meaning matches, the same for the same action.
- **Swipe actions** always have a non-gesture alternative (Edit mode, a context menu, a
  button in the detail): a swipe is invisible until discovered.

## Navigation, sheets, and alerts

- One `NavigationStack(path:)` per root, bound to Core's `NavigationModel`, with one
  `navigationDestination(for: AppRoute.self)`; both live in `RootView`, never in a
  screen. A screen pushes with `NavigationLink(value:)`. A new screen is a new `AppRoute`
  case and a new branch of the destination switch, never navigation state in a view's
  `@State`. Tabs versus a stack is the lock's. Why, and how deep links and the per-scene
  path work: the `designing-ui` skill's `references/navigation.md`.
- A button inside a `NavigationLink` row takes a non-default style
  (`.buttonStyle(.borderless)`, as `TodoDoneToggle`), or a tap follows the link.
- `NavigationSplitView` only for a regular-width iPad layout the lock asks for.
- Whether something is presented is view-model state (a `Bool`, or an optional whose
  presence presents it), bound through an action-built `Binding` so every dismissal
  goes through the action. A failure alert is the exception that proves it: only its
  button is the person's dismissal, so its binding ignores SwiftUI's write-back, which
  also comes when the presentation is torn down by code (`FailureAlert.swift`).
- A sheet is an `AppSheet` case, presented by `NavigationModel.present(_:)` and
  dismissed by `dismissSheet(_:)`, which names the sheet that closed. `RootView` holds
  the app's only `.sheet(item:)`, outside the stack, bound through a `Binding` whose
  setter acts only on `nil` and calls `dismissSheet(_:)`, and builds each sheet in one
  switch (`sheet(for:)`). A new sheet is a new `AppSheet` case and a
  new branch of that switch, never a `.sheet` on a screen or a `Bool` in a view's
  `@State`. A sheet's own title bar and close button come from a plain
  `NavigationStack { … }` inside it (`AboutView`), which pushes nothing; its close
  button is the system's `Button(role: .close)`.
- A failure is presented from `RootView` only, by `failureAlerts(on:isTopmost:)`, which
  `RootView` applies to each presentation layer — outside the stack, since an alert on a
  screen inside the stack does not present while another screen is pushed over it
  (#78), and on the `sheet(for:)` content, since nothing presents from a view that is
  already presenting a sheet (#124) — and which hands the failure only to the topmost
  layer. A feature's failure type adopts Core's `PresentableFailure`, and the feature
  adds its `.failureAlert` once, inside `failureAlerts(on:isTopmost:)`.
- A shared model's failure is read and dismissed through the window's own
  `SceneLifecycleModel` (`lifecycle.todoListFailure`, `lifecycle.dismissTodoListFailure()`),
  never from the shared model directly: every window renders that model, and Core hands
  one failure to exactly one window — the one whose action caused it while it is in the
  foreground, otherwise the one that has been in the foreground longest (#133). A view
  never compares scenes or phases itself; the rule and its reasons are the `designing-ui`
  skill's `references/navigation.md` › A failure presents in one window.
- Sheet sizing (`.presentationDetents`) only as the lock says.

## Size classes, Dynamic Type, safe areas, keyboard

- Size class chooses a layout, never a behavior; every Core decision is the same for
  both. On a regular-width iPad, cap a text column at a readable width. Whether iPad
  ships is the `starting-an-app` skill's decision.
- A layout that cannot fit at accessibility sizes switches with `ViewThatFits` or on
  `dynamicTypeSize.isAccessibilitySize` (an `HStack` becoming a `VStack`).
- Never hard-code an inset or a device height; a bar pinned to an edge is
  `.safeAreaInset(edge:)` (`TodoListView`'s add bar), so the last row is never hidden.
- `@FocusState` for focus, set from an action's result, not a timer. `.submitLabel`
  names the return key and `.onSubmit` calls the Core action;
  `.scrollDismissesKeyboard(.interactively)` on a scrolling form.
- An iOS-only modifier (`.navigationBarTitleDisplayMode`, `.keyboardType`,
  `.textInputAutocapitalization`) sits inside `#if os(iOS)` (`swift.md`).

## Touch targets, motion, accessibility

- Every tappable element is at least 44×44 pt (`DesignTokens.Size.minimumHitTarget`). A
  small glyph gets `.contentShape(Rectangle())` over a token-sized frame, not a bigger
  glyph (`TodoRow`'s toggle); a control whose system style stays under 44 pt gets a
  larger control size or a plain style on a token-sized container.
- A text field padded out to that target is dead padding: a `TextField` takes focus
  only from a tap on its text line, and `.onTapGesture` on it fails
  `accessibility_trait_for_button`. Draw the fill with a `.plain` `Button` in
  `.background { … }` that sets the `@FocusState`, marked `.accessibilityHidden(true)`
  (`TodoListView`'s `addBar`).
- Motion is optional: animate with `DesignTokens.Motion.animation(reduceMotion:)`, which
  is none under Reduce Motion, and show nothing only through animation.
- Accessibility identifiers are a test contract: every control a UI test touches has a
  stable, unlocalized `.accessibilityIdentifier` (`newItemField`, `addButton`,
  `toggle-<uuid>`), and a rename changes `LaunchTests` in the same commit.
- A glyph-only control gets `.accessibilityLabel` from a Core resource (`TodoRow`'s
  `toggleLabel`); a decorative image is `Image(decorative:)` or
  `.accessibilityHidden(true)`. SwiftLint's accessibility rules miss a glyph-only text
  button, and so does the launch test's accessibility audit: a `+` is a description to
  it, so it reports an empty label but not a meaningless one. Review catches it. Group a
  value and its caption with
  `.accessibilityElement(children: .combine)`.

## Previews

- One `#Preview("Name")` per state worth seeing, injecting a view model already in it
  (`TodoListView`'s "Items", "Empty", "Load failed", over the Debug-only
  `PreviewTodoRepository` or Core's `UnavailableTodoRepository`). Previews sit under
  `#if DEBUG` and never construct a `MyAppPlatform` adapter.
- A pushed screen's preview wraps it in a plain `NavigationStack { … }`, the stack
  `RootView` would give it.
- Add a dark preview, an accessibility-size one (`.dynamicTypeSize(.accessibility3)`)
  for a screen that shows text, and a regular-width one
  (`.environment(\.horizontalSizeClass, .regular)`) for an iPad layout.
- No `try!` or force unwrap in a preview either. Previews compile with the module, but
  nothing checks what they render.

## Strings in App/

`Info.plist` strings (a usage description, `CFBundleDisplayName`) are read from the app
bundle, so a package catalog cannot hold them: when an app adds one, its wording lives
in `App/InfoPlist.xcstrings` (picked up by `project.yml`'s `sources: [App]`; the
template ships none). `LocalizationTests` scans Core only, so review checks that every
key has a `comment` and an `en` value.

## LaunchUITests

The one XCTest target proves only what the assembled app shows (`testing.md` › Where a
Test Goes). It waits on a predicate with a timeout (`waitForExistence(timeout:)`),
never `sleep`, and keeps its timeouts in `Support/Timeout.swift`'s `Timeout`. A wait or
helper more than one test file needs (`focus`, `waitForDisappearance`) goes in
`LaunchUITests/Support/`, never copied into a second file.

The launch walk runs Xcode's accessibility audit (`auditAccessibility(of:)`,
`Support/XCTestCase+AccessibilityAudit.swift`) on exactly these states: the empty list,
the list with an item (keyboard dismissed), the About sheet, the item's detail screen,
the detail screen's not-found state, and the All Done state. Edit mode, the load-failure
state, and the failure alert go unaudited; a new screen or state the walk reaches gets
the same call. The walk pins light appearance and the default text size, so dark mode and large
text are not audited. Its issue handler accepts only a named exception matched on the
audit type *and* the element, each with a comment saying why the issue is the system's
rather than the app's. A new exception is a gate change reviewed like a lint disable;
accepting a whole audit type is weakening a gate (`AGENTS.md` › Security and human
approval). Fix what the audit reports in the view instead.

## Verifying a screen

1. `just test` — the view model's behavior, and the view compiled for macOS.
2. `just build` — the view and its previews compile for iOS; `just lint` for the view
   rules.
3. `just uitest` — when an identifier the launch test reads, a screen the launch walk
   visits, or `App/`'s wiring changed. Its accessibility audit (missing labels, hit
   regions, clipped text, contrast, traits) covers only the states listed under
   LaunchUITests, in light appearance at the default text size.
4. `just run`, then screenshots per the `running-the-app` skill on the smallest iPhone
   the Simulator offers (`SIMULATOR_DEVICE="<name>" just run`): light, dark, the largest
   accessibility text size (`accessibility-extra-extra-extra-large`), and Increase
   Contrast — plus a regular-width iPad while iPad ships. Check VoiceOver and
   Accessibility Inspector by hand, and say in the pull request what was checked; no
   gate sees dark, a large text size, Increase Contrast, iPad, or a screen or state the
   launch walk does not audit.
