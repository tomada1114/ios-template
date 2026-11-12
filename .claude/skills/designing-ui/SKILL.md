---
name: designing-ui
description: >
  Covers deciding how this iOS app looks: the design lock in references/design-lock.md
  (accent, custom colors, type, density, symbols, navigation structure, iPad layout,
  haptics, motion, copy style, app icon), the values of the DesignTokens scale,
  Liquid Glass and materials on the iOS 27 floor, researching the lock from
  the HIG and Apple's own apps, and why navigation is a Core AppRoute enum with a per-scene
  NavigationModel, AppSheet sheets, and Core-parsed deep links. Use when writing or
  amending the design lock, changing a DesignTokens value, touching AccentColor.colorset
  or AppIcon.appiconset, adding custom glass or a material, comparing a screen against
  the lock, or changing how navigation, sheets, tabs, or deep links are structured.
---

# Designing UI

**Owns:** the visual decisions every screen obeys and where they are recorded — the
design lock, the values in `DesignTokens` (`MyAppUI/DesignSystem/DesignTokens.swift`),
custom glass and materials, and how the lock is researched. **Does not own:** the craft
rules a single view follows — semantic colors, text styles, 44-point targets, contrast,
toolbars, haptics, previews, and the screenshot set (`.claude/rules/ui.md`, loaded with
any file under `MyAppUI/` or `App/`); the device family and scene model
(`starting-an-app`); launching the app and taking screenshots (`running-the-app`).

Apple's Human Interface Guidelines are the baseline and are not restated. The template's
own research — every reference, the reference lock, the ledger, and why each token
has its value — is `docs/design-system.md`, the record the lock's values came from.
Why navigation is a Core route enum and a per-scene path, how sheets are presented, how
deep links are parsed, and what tabs or a split view would change:
[references/navigation.md](references/navigation.md).

## System first, custom by exception

An iOS app earns trust by behaving like the other apps on the phone, so the system's
answer is the default to every visual question, and a departure is made once, in the
lock, never per screen. `.claude/rules/ui.md` › System first holds what that means
for a view; this skill decides the departures.

- **Accent:** `App/Assets.xcassets/AccentColor.colorset` is the one place it is set;
  `project.yml`'s `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` makes it
  every control's tint. The template ships it empty (system blue).
- **A custom color** is a Color Set with Any, Dark, and increased-contrast variants, and
  one role; **a custom font** comes with its license and scales with Dynamic Type.
- **Symbols** stay in the default rendering mode until the lock picks one per context.

## Tokens

`DesignTokens` is a scale, not a style: `Spacing` (2, 4, 8, 12, 16, 24, 32 pt), `Radius`
(8, 12, 20 pt), `Size.minimumHitTarget` (44 pt), and `Motion.animation(reduceMotion:)`.
Changing a value is a lock decision that every screen inherits, which is the point.
Color and type get no token: they are the system's semantic colors and text styles, or a
Color Set and a font the lock names.

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
  itself; within content, use the standard materials.

## The design lock

The lock is the app's answer to "what does every screen here look like?" — a handful of
decisions made once, each a value or an explicit "system default".

- **It is [references/design-lock.md](references/design-lock.md)'s "The lock"**, the
  present state: one value per field, each with its reason. The template ships its
  reference lock there; an app rewrites it for itself after the bootstrap. The owner
  reviews it in the pull request that writes it; until it merges, screens may be built
  against it only as an experiment.
- **When:** after the device family is decided and before the second screen.
- **What it holds, and where each value lands:** **REQUIRED:** the same file's Fields.
- **How to research it:** **REQUIRED:**
  [references/research-workflow.md](references/research-workflow.md) — the HIG,
  Apple's own apps doing the same task, and `.claude/rules/ui.md`.
- **Changing it:** edit the section in place — a corrected value and a new direction (a
  new accent, custom type, denser layout) alike — in the pull request that changes the
  code, rewriting the reason beside it; git history holds what it used to say.
- **In the template itself** the lock is the system-first reference lock, and research
  behind a change to it updates `docs/design-system.md`'s ledger.

| Template default | Each app decides in its design lock |
|---|---|
| Spacing, radius, hit-target, motion tokens above | Adjusted spacing or radii, density |
| Semantic system colors; system accent | Accent color (Any/Dark/Increased-contrast variants), brand colors |
| System font, text styles, Dynamic Type | A custom font (with license and Dynamic Type scaling), type roles per screen |
| SF Symbols, default rendering | Rendering mode per context, custom symbols/images |
| Standard components; automatic Liquid Glass | Custom glass or materials, where and on which OS |
| — | Navigation structure (tabs vs. stack), iPad layout, haptics, motion personality, copy voice and capitalization, app icon |

## Reviewing a screen against the lock

Take the screenshot set `.claude/rules/ui.md` › Verifying a screen names and compare
each against the lock (`references/design-lock.md`). Fix drift, or name it in the pull
request as accepted. No gate sees any of this: the screenshots in the pull request are
the evidence.

## Sources

All checked 2026-09-30.

- <https://developer.apple.com/design/human-interface-guidelines/color> — system colors
  and their dark and increased-contrast variants; the accent on prominent buttons.
- <https://developer.apple.com/design/human-interface-guidelines/typography> — custom
  fonts must support Dynamic Type.
- <https://developer.apple.com/design/human-interface-guidelines/sf-symbols> — rendering
  modes.
- <https://developer.apple.com/design/human-interface-guidelines/materials> — Liquid
  Glass for controls and navigation; standard materials within content.
- <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass> —
  standard components adopt Liquid Glass when built with the latest SDKs.
- <https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility>
  — compatibility mode, iOS 26.0; ignored when building for iOS 27.
- <https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)> — iOS 26.0,
  macOS 26.0.
- <https://developer.apple.com/documentation/xcode/build-settings-reference> —
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, the default tint color on iOS.
