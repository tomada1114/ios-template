---
name: building-swiftui-screens
description: >
  Covers writing an iOS SwiftUI view in MyAppUI as a thin renderer over a MyAppCore
  @Observable view model - how the view receives and holds its model (@State, a plain
  property, @Bindable, a Binding built from an action), what may sit in body,
  NavigationStack and navigationDestination, sheets and alerts driven by view-model
  state, horizontalSizeClass layouts for iPhone and iPad, Dynamic Type with text styles,
  ScaledMetric and ViewThatFits, safe areas and safeAreaInset, the keyboard with
  FocusState, submitLabel and onSubmit, 44-point touch targets, iOS-only modifiers
  behind #if os(iOS), #Preview per state, accessibility identifiers for LaunchUITests,
  accessibility labels, Reduce Motion, and how a screen is verified. Use when adding or
  changing a view, a subview, or a preview under the local package's Sources/MyAppUI,
  wiring a view to a view model in App/, adding an accessibilityIdentifier, or fixing an
  accessibility_label_for_image or no_magic_numbers violation in a view.
---

# Building SwiftUI Screens

**Owns:** how a view in `MyAppUI` is written — how it gets its view model, what it may
contain, how it navigates and presents, how it adapts to size class, text size, and the
keyboard, its previews, and its accessibility wiring. **Does not own:** the view model's
shape, state, and actions (`designing-core-logic`); what the screen looks like — color,
type, spacing, the design lock (`designing-ui`); a system API behind a port
(`integrating-system-apis`); which device families the app ships (`starting-an-app`);
launching the app and the evidence a pull request carries (`running-the-app`).

## The rule, and why

A view renders Core state and forwards user intent to a Core action; it decides nothing.
`MyAppUI` is outside the coverage floor — `scripts/coverage.sh` measures `MyAppCore`
only — so any branch that lives in a view is a branch no gate tests. `TodoListView` over
`TodoListViewModel` is the worked example; copy its shape.

- A view is a `struct` in `MyAppUI` importing `SwiftUI` and `MyAppCore`, never
  `MyAppPlatform`. Enforced by: `ArchitectureBoundaryTests`' sibling-import tests.
- It is `public` only when `App/` constructs it; a subview (`TodoRow`) stays `private`
  or internal.

## Getting the view model

- **A model with a port is built in `App/`**, the composition root, because its adapter
  lives in `MyAppPlatform`, which this module must not import. `MyAppApp` keeps
  `TodoListViewModel` in `@State` and passes it to `TodoListView(model:)`.
- **A view handed its model** holds it as a plain `let`; `@Observable` re-renders the
  view when a property its `body` read changes. `TodoListView` uses `@Bindable` instead
  only because its text field binds to `draftTitle`, the one settable property.
- **A view that owns a portless model** holds it in `@State private var model`, set with
  `_model = State(initialValue: model)` from an initializer parameter, so a preview can
  inject a state.
- **A binding to state the view may not set** is built from an action: `TodoListView`'s
  `isFailurePresented` reads `model.failure != nil` and calls `model.dismissFailure()`.
  Never widen a `private(set)` to let `@Bindable` reach it.
- Not used here: `ObservableObject`, `@StateObject`, `@ObservedObject`,
  `@EnvironmentObject`. Initializer parameters carry a model (`designing-core-logic`).

## What `body` may contain

| Belongs in the view | Belongs in the Core view model |
|---|---|
| Layout, modifiers, the order things appear in | Whether an action is allowed now (`canAdd`) |
| Choosing a layout from the size class or text size | Any rule, threshold, or comparison on domain values |
| Calling an action from a `Button`, `.onSubmit`, `.refreshable`, `.onDelete` | What the action does and the state it leaves |
| *When* to ask — `.task`, as `TodoListView` loads on first appearance | *What* asking means (`load()`), and which empty state shows (`showsEmptyState`) |
| `Text(verbatim:)` for the user's own text (`item.title`) | Every word a person reads, as a `LocalizedStringResource` (`TodoListStrings`) |

- An action that waits is `async`; call it from `.task` (cancelled with the view) or a
  `Task { }` in a button's closure.
- Spacing, radius, and hit-target numbers come from `DesignTokens` in `MyAppUI`
  (`DesignTokens.Spacing.medium`), whose values the design lock sets (`designing-ui`); a
  number only one view needs goes in a `private enum Layout` in that view's file.
  Enforced by: `opt_in_rules: all`, which turns on `no_magic_numbers`.
- When `body` nears `function_body_length`, extract a subview `struct` taking exactly the
  slice it renders, as `TodoRow` does.

## Navigation

- One `NavigationStack` per navigation root, with value-based
  `navigationDestination(for:)`: a link pushes a Core value, the destination builds its
  screen from it. Once a screen needs deep links or state restoration, the path is Core
  state owned by a view model — the navigation model is a later decision, not this
  skill's.
- `NavigationSplitView` only for a regular-width iPad layout the design lock asks for;
  on iPhone it collapses to a stack anyway.

## Sheets and alerts

- Whether something is presented is view-model state: a `Bool` such as
  `isPresentingAddItem`, or an optional value (`failure`) whose presence presents it.
  Bind through an action-built `Binding`, so every dismissal route — a button, a swipe,
  the system — goes through the action. `TodoListView`'s `.alert(_:isPresented:presenting:)`
  is the example.
- `.presentationDetents` and other sheet sizing only as the design lock says.

## Size classes, Dynamic Type, safe areas

- **Size class** chooses a layout, never a behavior: read
  `@Environment(\.horizontalSizeClass)` in the view, and keep every decision in Core
  identical for both. Preview both: `.environment(\.horizontalSizeClass, .regular)`.
  Whether iPad ships at all is `starting-an-app`'s decision.
- **Dynamic Type:** text styles only (`.font(.body)`), never a fixed point size.
  `@ScaledMetric` for a dimension that must grow with text (an icon beside a label). A
  layout that cannot fit at accessibility sizes switches with `ViewThatFits`, or on
  `dynamicTypeSize.isAccessibilitySize` (for example, an `HStack` becoming a `VStack`).
  Preview at `.dynamicTypeSize(.accessibility3)`.
- **Safe areas:** never hard-code an inset or a device height. A bar pinned to an edge
  is `.safeAreaInset(edge:)`, as `TodoListView`'s add bar is, so the list's content
  is inset by the bar's height and its last row is never hidden behind it.

## The keyboard

- `@FocusState` for which field has focus; set it from an action's result, not a timer.
- `.submitLabel` names the return key and `.onSubmit` calls the Core action —
  `TodoListView` submits the draft with `.submitLabel(.done)` and
  `.onSubmit { Task { await model.addDraft() } }`.
- `.scrollDismissesKeyboard(.interactively)` on a scrolling form.

## Touch targets and iOS-only modifiers

- Every tappable element is at least 44×44 pt (HIG). An icon-only button reaches it with
  `.contentShape(Rectangle())` over a frame of `DesignTokens.Size.minimumHitTarget`, as
  `TodoRow`'s toggle does.
- `MyAppUI` also compiles for macOS under `swift build`, so an iOS-only modifier —
  `.navigationBarTitleDisplayMode`, `.keyboardType`, `.textInputAutocapitalization` —
  sits inside `#if os(iOS)`. `TodoListView` needs none today: `.submitLabel`,
  `.refreshable`, and `.safeAreaInset` exist on both platforms. `swift build` fails when
  one is missed, so `just test` catches it.

## Previews

- One `#Preview("Name")` per state worth seeing, built by injecting a view model already
  in it — `TodoListView`'s "Items", "Empty", and "Load failed", over the Debug-only
  `PreviewTodoRepository` or Core's `UnavailableTodoRepository`. Previews sit under
  `#if DEBUG` and never construct a `MyAppPlatform` adapter.
- Add a dark preview (`.preferredColorScheme(.dark)`), a regular-width one for an iPad
  layout, and an accessibility-size one for a screen that shows text.
- No `try!` or force unwrap in a preview (`.claude/rules/swift.md`).
- Previews compile with the module but nothing checks what they render. Look.

## Accessibility

- **Identifiers are a test contract.** Every control a UI test touches carries a stable,
  unlocalized `.accessibilityIdentifier` — `newItemField`, `addButton`, `retryButton`,
  `toggle-<uuid>`. `LaunchTests` types into `newItemField` and taps `addButton`, so a
  rename changes the test in the same commit.
- **Labels are what VoiceOver says.** A glyph-only control gets
  `.accessibilityLabel` from a Core `LocalizedStringResource`, as `TodoRow`'s toggle
  does with `toggleLabel`. A decorative image is `Image(decorative:)` or
  `.accessibilityHidden(true)`. Enforced by: `accessibility_label_for_image` and
  `accessibility_trait_for_button`; neither sees a glyph-only text button — review does.
- **Group** a value and its caption with `.accessibilityElement(children: .combine)`.
- **Motion:** an animation checks `@Environment(\.accessibilityReduceMotion)` and falls
  back to none or a cross-fade.
- **Check by hand**: Accessibility Inspector against the Simulator, and a VoiceOver
  pass. Say in the pull request what was checked.

## Verifying a screen

1. `just test` — the view model's behavior, and `swift build` of the view for macOS.
2. `just build` — the view and its previews compile for iOS; `just lint` for the view rules.
3. `just uitest` — when an identifier the launch test reads, or the first screen, changed.
4. `just run`, then screenshots per `running-the-app` in light, dark, and the largest
   Dynamic Type size, on the smallest iPhone the simulator list offers
   (`SIMULATOR_DEVICE="<name>" just run`) — and a regular-width iPad while iPad ships.

## Sources

All checked 2026-09-30.

- [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack), [navigationDestination(for:destination:)](https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)), [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [presentationDetents(_:)](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)), [horizontalSizeClass](https://developer.apple.com/documentation/swiftui/environmentvalues/horizontalsizeclass)
- [ScaledMetric](https://developer.apple.com/documentation/swiftui/scaledmetric), [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits), [isAccessibilitySize](https://developer.apple.com/documentation/swiftui/dynamictypesize/isaccessibilitysize), [dynamicTypeSize(_:)](https://developer.apple.com/documentation/swiftui/view/dynamictypesize(_:))
- [safeAreaInset(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)), [FocusState](https://developer.apple.com/documentation/swiftui/focusstate), [submitLabel(_:)](https://developer.apple.com/documentation/swiftui/view/submitlabel(_:)), [scrollDismissesKeyboard(_:)](https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:))
- [HIG › Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) — "a hit region of at least 44x44 pt"; [HIG › Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [navigationBarTitleDisplayMode(_:)](https://developer.apple.com/documentation/swiftui/view/navigationbartitledisplaymode(_:)), [keyboardType(_:)](https://developer.apple.com/documentation/swiftui/view/keyboardtype(_:)), [textInputAutocapitalization(_:)](https://developer.apple.com/documentation/swiftui/view/textinputautocapitalization(_:))
- [Migrating to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro), [accessibilityIdentifier(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier(_:)), [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion), [Previews in Xcode](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
