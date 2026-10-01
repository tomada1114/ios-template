---
name: designing-ui
description: >
  Covers how this iOS app looks - craft rules grounded in Apple's Human Interface
  Guidelines (semantic and accent colors, text styles and Dynamic Type, light and dark
  appearance, Increase Contrast, SF Symbols, safe areas, size classes, 44-point targets,
  toolbars, haptics, swipe actions, Liquid Glass with an iOS 27 floor), the
  DesignTokens scale in MyAppUI/DesignSystem, and the per-app design lock, an ADR under
  docs/architecture/ researched with /refero-design. Use when choosing a color, font,
  spacing, radius, symbol, material, or animation, adding or changing a DesignTokens
  value, touching AccentColor.colorset or AppIcon.appiconset, adding glassEffect or
  sensoryFeedback, reviewing how a screen looks in light, dark, the largest text size,
  or Increase Contrast, or writing or amending the app's design-lock ADR.
---

# Designing UI

**Owns:** what a screen in this app looks like — the craft rules below, `DesignTokens`
(`MyAppUI/DesignSystem/DesignTokens.swift` in the local package), and the app's
design lock: the short set of visual decisions every screen obeys, and where they are
recorded. **Does not own:** how a view is written in SwiftUI, its previews, and its
accessibility wiring (`building-swiftui-screens`); the device family and scene model
(`starting-an-app`); an ADR's shape, numbering, and statuses
(`recording-architecture-decisions`); launching the app and taking screenshots
(`running-the-app`).

Apple's Human Interface Guidelines (HIG) are the baseline and are not restated: this
skill keeps only what this repository decides on top of them and links the page for the
rest. The template's own research — every reference, the reference lock, and why each
token has its value — is `docs/design-system.md`.

## System first, custom by exception

An iOS app earns trust by behaving like the other apps on the phone. The default answer
to every visual question is the system's; a departure is a design-lock decision, never a
per-screen one.

- **Type:** text styles only (`.largeTitle` … `.caption2`) in the system font, which
  gives Dynamic Type for free. `@ScaledMetric` for any dimension tied to text size. No
  fixed point sizes; a custom font is a lock decision that must scale with Dynamic Type.
- **Color:** semantic only — `.primary`, `.secondary`, `.tint`, `Color.accentColor`,
  `.background`, and the hierarchical `.fill` and `.quaternary` styles — used for their
  stated role. A custom color is a Color Set in `App/Assets.xcassets` with Any, Dark,
  and increased-contrast variants, added only by the lock; a literal RGB in a view is a
  review finding.
- **Accent:** `App/Assets.xcassets/AccentColor.colorset` is the one place it is set, and
  `project.yml`'s `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` makes it
  the tint of every control app-wide. The template ships it with no value (system blue).
- **Symbols:** SF Symbols through `Image(systemName:)` or `Label`, in the default
  rendering mode until the lock picks one per context.
- **Controls and containers:** standard SwiftUI components with their default styles.
  They carry the platform's look, including Liquid Glass (below), and their accessibility.

## Tokens

`DesignTokens` is a scale, not a style: `Spacing` (2, 4, 8, 12, 16, 24, 32 pt), `Radius`
(8, 12, 20 pt), `Size.minimumHitTarget` (44 pt), and `Motion.animation(reduceMotion:)`.

- A spacing, radius, or hit-target number in a view comes from it; a number only one
  view needs and the scale does not cover goes in that view's `private enum Layout`.
- The inset from the screen edge is not a token: `List` and `Form` insets and
  `.padding()` give the system's, which follows the device and size class.
- A radius is always `RoundedRectangle(cornerRadius:style: .continuous)`. A standard
  component keeps its own radius; the tokens are for containers the system does not draw.
- The tokens never move into `MyAppCore`: they are presentation, and Core does not
  import SwiftUI. Changing a value is a lock decision, and every screen inherits it.

## Appearance and contrast

- Every screen works in light and dark, and with Increase Contrast on
  (`@Environment(\.colorSchemeContrast)` reads `.increased`). System colors adapt on
  their own; a custom color owes all three variants.
- Text contrast is at least 4.5:1; 7:1 is the target for small text on a custom color.
- Never convey state by color alone: pair it with a shape, a symbol, or text —
  `TodoRow` strikes through a done item and swaps its glyph as well as dimming it.
- Check it rather than trust it — `xcrun simctl ui <udid> appearance dark`,
  `xcrun simctl ui <udid> increase_contrast enabled` (`xcrun simctl help ui` lists the
  spelling), and `content_size accessibility-extra-extra-extra-large`; each without an
  argument prints the current value, so put back what you found.

## Layout on iOS

- Respect the safe area; a bar pinned to an edge is a `.safeAreaInset(edge:)`.
- Size classes choose a layout, never a behavior. On a regular-width iPad, cap a text
  column at a readable width instead of stretching it edge to edge; whether iPad ships is
  `starting-an-app`'s decision, and its layout is the lock's.
- Every tappable element is at least `DesignTokens.Size.minimumHitTarget` in both
  dimensions. A small glyph gets a framed `contentShape`, not a bigger glyph; a control
  whose system style stays under 44 pt gets a larger control size or a plain style on a
  token-sized container (`TodoListView`'s field and Add button).
- Align to the spacing scale, and let alignment and grouping carry hierarchy before
  color or weight does.

## Navigation, toolbars, and haptics

- One `NavigationStack` per root; tabs versus a stack is the lock's navigation field.
- Toolbar items go in the system's placements (`.primaryAction`, `.confirmationAction`,
  `.cancellationAction`, `.bottomBar`) rather than a hand-built bar, so the OS can style
  and relocate them.
- `.sensoryFeedback` only where the lock allows haptics, with the system pattern whose
  meaning matches (`.success`, `.selection`), and consistently for the same action.
- A swipe action always has a non-gesture alternative — an Edit mode, a context menu, or
  a button in the detail — because a swipe is invisible until discovered.
- Motion is optional: a state change animates with
  `DesignTokens.Motion.animation(reduceMotion:)`, which is none under Reduce Motion, and
  nothing a person needs to know is shown only by animation.

## Materials and Liquid Glass

Built with the Xcode 27 SDK, standard components — `NavigationStack`, `List`, toolbars,
sheets, `TabView` — take Liquid Glass. That is the template's whole adoption.

- Never set `UIDesignRequiresCompatibility`: the system ignores it once the app builds
  for iOS 27, which this template always does.
- The floor is iOS 27 and `MyAppUI` builds for macOS 27, so `glassEffect(_:in:)` and
  every other API the SDK ships needs no `#available` branch.
- An app whose lock asks for custom glass puts it in one `ViewModifier` in `MyAppUI`
  (`content.glassEffect(.regular, in: shape)`), so the surface is defined once. Glass
  belongs to controls and navigation that float above content, never to the content
  itself.

## Copy

- Pick one capitalization per element type — title case or sentence case — record it in
  the lock, and apply it everywhere.
- Button labels start with a verb naming what happens ("Add", "Retry"); an action that
  needs more input before it completes ends in an ellipsis (…).

## The design lock

The lock is the app's answer to "what does every screen here look like?" — a handful of
decisions made once, each a value or an explicit "system default".

- **It is an ADR.** Write it as `recording-architecture-decisions` says, with the next
  free number in `docs/architecture/adr/`, status Proposed, and a row in
  `docs/architecture/README.md`. Only the owner accepts it; until then screens may be
  built against it only as an experiment.
- **When:** after the device family is decided and before the second screen.
- **What it holds, and where each value lands:**
  [references/design-lock.md](references/design-lock.md).
- **How to research it:** **REQUIRED:**
  [references/refero-workflow.md](references/refero-workflow.md) — `/refero-design`
  with iOS screens and flows when the Refero tools are available, the HIG rules above
  when they are not.
- **Changing it:** a corrected value in an Accepted lock is an amendment; a new
  direction (a new accent, custom type, denser layout) is a new ADR that supersedes it.
- **In the template itself** there is no lock: the template ships no ADRs, and its
  defaults are system-first. A change to them updates `docs/design-system.md`.

| Template default | Each app decides in its design-lock ADR |
|---|---|
| Spacing, radius, hit-target, motion tokens above | Adjusted spacing or radii, density |
| Semantic system colors; system accent | Accent color (Any/Dark/Increased-contrast variants), brand colors |
| System font, text styles, Dynamic Type | A custom font (with license and Dynamic Type scaling), type roles per screen |
| SF Symbols, default rendering | Rendering mode per context, custom symbols/images |
| Standard components; automatic Liquid Glass | Custom glass or materials, where and on which OS |
| — | Navigation structure (tabs vs. stack), iPad layout, haptics, motion personality, copy voice, app icon |

## Reviewing a screen's design

Before calling a screen done, `just build`, then `just run` and screenshot it per
`running-the-app` on the smallest iPhone the Simulator offers — light, dark,
`accessibility-extra-extra-extra-large`, and Increase Contrast, plus a regular-width iPad
while iPad ships — and compare each against the lock (or, in the template, the reference
lock in `docs/design-system.md`). Fix drift, or name it in the pull request as accepted.
No gate sees any of this: the screenshots in the pull request are the evidence.

## Sources

All checked 2026-09-30.

- <https://developer.apple.com/design/human-interface-guidelines/color> — system colors
  and their dark and increased-contrast variants; the accent on prominent buttons.
- <https://developer.apple.com/design/human-interface-guidelines/dark-mode> — 4.5:1
  minimum, 7:1 for custom colors in small text.
- <https://developer.apple.com/design/human-interface-guidelines/accessibility> — 44x44 pt
  controls on iOS, Increase Contrast, more than color alone.
- <https://developer.apple.com/design/human-interface-guidelines/typography> — text
  styles with the system font support Dynamic Type; custom fonts must too.
- <https://developer.apple.com/design/human-interface-guidelines/layout> — safe areas,
  margins, readable text width, size classes.
- <https://developer.apple.com/design/human-interface-guidelines/buttons> — a 44x44 pt
  hit region; labels that start with a verb.
- <https://developer.apple.com/design/human-interface-guidelines/toolbars> — consistent
  placement of grouped actions.
- <https://developer.apple.com/design/human-interface-guidelines/playing-haptics> —
  system patterns for their documented meaning, used consistently.
- <https://developer.apple.com/design/human-interface-guidelines/motion> — make motion
  optional.
- <https://developer.apple.com/design/human-interface-guidelines/sf-symbols> — rendering
  modes.
- <https://developer.apple.com/design/human-interface-guidelines/materials> — Liquid
  Glass for controls and navigation; standard materials within content.
- <https://developer.apple.com/design/human-interface-guidelines/writing> — one
  capitalization style per element type.
- <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass> —
  standard components adopt Liquid Glass when built with the latest SDKs.
- <https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility>
  — compatibility mode, iOS 26.0; ignored when building for iOS 27.
- <https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)> — iOS 26.0,
  macOS 26.0.
- <https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)> —
  iOS 17.0.
- <https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast>
  — iOS 13.0.
- <https://developer.apple.com/documentation/xcode/build-settings-reference> —
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, the default tint color on iOS.
