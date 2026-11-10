# The design lock

What every screen in this app looks like, one value per field. The lock lives here, in
the skill, and binds every screen; `SKILL.md` says when it is written and how it changes,
and `refero-workflow.md`, beside this file, how its values are researched.
`docs/design-system.md` is the research record the values came from — the brief, the
reviewed references, the decision ledger, and the sources — and is never a second copy
of the lock.

## The lock

This is the template's reference lock: system-first and unbranded, because the template
is the neutral base every app departs from. An app cut from the template rewrites this
section for itself after the bootstrap; changing a value later is an edit to this
section in place, in the pull request that changes the code, with the reason in the
sentence beside it — git history holds what it used to say.

- Accent color: system default (`AccentColor` with no value). Nothing depends on its hue.
- Custom colors: none; semantic system colors only.
- Type: system font and text styles with Dynamic Type; a large navigation title.
- Spacing and corner radius: the template scale in `DesignTokens`, unchanged.
- Density: regular; the system `List` default style.
- Symbols: SF Symbols only, default rendering.
- Materials and Liquid Glass: standard components only.
- Navigation structure: one `NavigationStack`; the Add button beside the draft field.
- iPad layout: same as iPhone (the template targets both, `TARGETED_DEVICE_FAMILY: "1,2"`).
- Haptics: none.
- Motion: system transitions only (`.default`), none under Reduce Motion.
- Copy style: title case for navigation titles and buttons; sentence case for alerts and
  empty states. Voice: short and plain.
- App icon: placeholder until distribution is decided.

## Fields

The fields every lock fixes, and where each value lands in code.

Every field is either a value or the words "system default". "System default" is a real
decision — often the right one for a first version — and saying it explicitly stops the
next implementer from inventing a value. A field left out is a gap, not a default: list
it as an open question in the pull request until it is decided.

| Field | What "decided" looks like | Where it lands in code |
|---|---|---|
| Accent color | "System default", or one color with its Any, Dark, and increased-contrast variants as sRGB values, and what it marks (prominent buttons, selection, links) | `App/Assets.xcassets/AccentColor.colorset`; `project.yml`'s `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` already points at it |
| Custom colors | Each named color, its one role, and its Any, Dark, and increased-contrast variants — or "none; semantic system colors only" | One Color Set each in `App/Assets.xcassets`, read with `Color("Name")` |
| Type | The text styles the app uses and for what (`.largeTitle` for a screen title, `.body` for rows, `.footnote` for metadata); a custom font, its license, and how it scales with Dynamic Type — or "system font only" | `.font(...)` at the call site; a custom font as a bundled resource registered in `project.yml` |
| Spacing | "Template scale", or the changed values and which one separates what (control from control, group from group) | `DesignTokens.Spacing` |
| Corner radius | "Template scale", or the values for tags, controls, and cards | `DesignTokens.Radius`, always `.continuous` |
| Density | Regular or compact; list style (`.insetGrouped`, `.plain`) and control size if not the default | A modifier on the root view in `App/`, so every screen inherits it |
| Symbols | SF Symbols only, or where custom images are allowed; the rendering mode (monochrome, hierarchical, palette, multicolor) per context | `Image(systemName:)`, `Label`, `.symbolRenderingMode(...)` |
| Materials and Liquid Glass | "Standard components only", or where a custom glass or material surface appears | One `ViewModifier` in `MyAppUI`, as `designing-ui` › Materials and Liquid Glass sets out |
| Navigation structure | A single `NavigationStack`, or a `TabView` with its tabs named; where the primary action lives (toolbar, bottom bar, inline) | The root view in `MyAppUI`, handed its models by `App/` |
| iPad layout | "Same as iPhone, readable width", or a `NavigationSplitView` at regular width — or "iPhone only" when the device family is | The root view, switching on `horizontalSizeClass`; `TARGETED_DEVICE_FAMILY` in `project.yml` |
| Haptics | "None", or which actions play which system pattern | `.sensoryFeedback(_:trigger:)` at those call sites only |
| Motion | "System transitions only", or which custom animations exist and what each says; always none under Reduce Motion | `DesignTokens.Motion`, extended if the lock adds curves |
| Copy style | Title case or sentence case per element type (buttons, navigation titles, section headers, alerts); the voice in one sentence | The English values in `Localizable.xcstrings`, returned by Core (`TodoListStrings`) |
| App icon | Who supplies it and in which format — an Icon Composer `.icon` file, or `AppIcon.appiconset` with dark and tinted variants — or "placeholder until distribution" | `App/Assets.xcassets/AppIcon.appiconset`, or the `.icon` file the target references in `project.yml` |

## Sharing values between views

`DesignTokens` is where a value two views share lives, and the lock is what sets its
numbers: changing a value there changes every screen at once, which is the point. It
stays in `MyAppUI` — presentation, never `MyAppCore`, which does not import SwiftUI. A
value only one view needs, that the scale does not cover, stays in that view's
`private enum Layout` (`no_magic_numbers`, on through `.swiftlint.yml`'s
`opt_in_rules: all`, rejects a bare number in a view body). Color and type get no token:
they are the system's semantic colors and text styles, or a Color Set and a font the
lock names.

## A lock, sketched

An illustration of an app's own lock, departing from the reference one; replace every
value with the app's own.

```markdown
## The lock

- Accent color: system default. Nothing depends on its hue.
- Custom colors: none; semantic system colors only.
- Type: system font; `.largeTitle` for screen titles, `.body` for rows, `.footnote`
  for dates and counts.
- Spacing and corner radius: template scale, unchanged.
- Density: regular; `.insetGrouped` lists.
- Symbols: SF Symbols only; hierarchical rendering in toolbars, monochrome in rows.
- Materials and Liquid Glass: standard components only.
- Navigation structure: one `NavigationStack`; the primary action in the bottom bar.
- iPad layout: same as iPhone, text column at readable width.
- Haptics: `.success` when an item is completed; nothing else.
- Motion: system transitions only.
- Copy style: title case for navigation titles and buttons; sentence case for section
  headers, alerts, and empty states. Voice: short, plain, no exclamation marks.
- App icon: placeholder until distribution is decided.
```

Keep the sketch's level of detail: values and one reason each, not a style guide. The
research that beat the alternatives stays in `docs/design-system.md`'s ledger, and
anything the owner has not settled stays an open question in the pull request, never
filled in from habit.

## What does not belong in the lock

- The device family and scene model — `starting-an-app`, written in `AGENTS.md`'s
  Architecture section.
- A single screen's layout — that is the screen's own pull request, built against the
  lock.
- Anything the HIG already fixes for every iOS app (the standard toolbar placements, the
  system swipe-to-delete); the lock records only this app's choices on top of it.
