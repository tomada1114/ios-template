# Design system

The template's default design system and the research it rests on. It fixes a small set
of tokens every screen draws from — `DesignTokens` in
`Packages/MyAppKit/Sources/MyAppUI/DesignSystem/DesignTokens.swift` — and leaves color
and type to the system, so a screen built from the template is correct in light, dark,
every Dynamic Type size, and Increase Contrast before anyone decides a brand. Every brand
decision belongs to the app's own design lock, an ADR written as the `designing-ui` skill
says (its `references/refero-workflow.md` is how an app researches one).

Researched 2026-09-30 with the owner's `/refero-design` skill and the Refero MCP tools
(screens and flows on `platform: "ios"`; styles only as a check). Apple claims were
checked the same day against the pages under [Sources](#sources).

## Brief

```text
Designing the default design system of an iOS app template (a SwiftUI to-do list is the example screen) for developers who will cut their own apps from it, on iOS (iPhone first; iPad must not break).
Goal: every screen built from the template is correct by default — light/dark, Dynamic Type to AX5, Increase Contrast, 44 pt targets — and looks native on iOS 18 and iOS 26 (Liquid Glass).
Tone: neutral, native, unbranded. The template must not impose a brand; brand belongs to each app's design lock.
Main objection/risk: a template default that fights the platform, or a brand look every app then has to undo.
Must remember: system first, custom by exception — tokens are a scale, not a style.
Constraints: SwiftUI only; iOS 18 deployment floor built with the Xcode 26 SDK; no custom fonts; semantic system colors only; MyAppUI also compiles for macOS.
Research needed: screens and flows (platform ios); styles only as a secondary check.
Path: direct build.
```

The skill's default pull toward a distinctive, memorable direction is overridden here on
purpose: the template is the neutral base every app's own lock departs from. That is the
first row of the decision ledger.

## Queries

| Tool | Query | Platform | Result |
|---|---|---|---|
| `refero_search_screens` | `to-do list` | ios | 2,425 screens; Todoist, Rise, Amie, Asana on page 1 |
| `refero_search_screens` | `task list empty state` | ios | 1,581 screens; Superlist, Amie, Asana, OKURI on page 1 |
| `refero_search_screens` | `add item sheet` | ios | 2,340 screens; Apple Books, District, Klarna, Gizmo on page 1 |
| `refero_search_screens` | `settings list toggles` | ios | 4,049 screens; LookUp, Brink, Weather mini, YouTube Music on page 1 |
| `refero_search_screens` | `list swipe to delete` | ios | 1,170 screens; Ivory, FoodNoms, Crouton, Planny, Wise on page 1 |
| `refero_get_screen` | the ten screens under [Reviewed screens](#reviewed-screens), in one batch | ios | full descriptions |
| `refero_get_similar_screens` | LookUp — Translations (`f2da9d79-35f3-4141-ac10-fb3a2d3c0ad0`), limit 8 | ios | Microsoft Copilot, Castro, Ivory, PayPal, SSENSE pickers |
| `refero_get_similar_screens` | Ivory — Drafts (`6e265b74-f9b9-4c6e-9409-735577c55d8d`), limit 8 | ios | Gmail, ChatGPT, Meta AI, WhatsApp settings and sheets |
| `refero_search_flows` | `create a task` | ios | 790 flows; OKURI, Canopi, Structured on page 1 |
| `refero_search_flows` | `onboarding permission request` | ios | 117 flows; Miles, Denim, Exoplan, Joi on page 1 |
| `refero_get_flow` | flows `11865` (OKURI) and `6704` (Miles) | ios | step-by-step goals, actions, system responses |
| `refero_search_styles` | `native iOS productivity app minimal` | — (web only) | 1,000 styles; Perplexity, Shuttle, ChatGPT, Things, Todoist, Goodnotes on page 1 |

`refero_get_screen_image` was used on LookUp and Ivory to check the described insets by
eye. `refero_get_style` was not called: no token is taken from a web style.

## Reviewed screens

Each opened with `refero_get_screen`. Pixel figures are Refero's own estimates from its
capture, not measurements; they are read for proportion, not copied as values.

| App — screen — Refero ID | Margins and spacing | Radii and targets | Type roles | Accent use |
|---|---|---|---|---|
| Superlist — Inbox, empty state — `02d61834-d91c-490e-8105-e8cfecfeafb1` | Single column, generous whitespace, three placeholder rows under the title | Circular filter button; floating add button | Large bold left-aligned title; muted placeholder rows | Brand red only on the add button and the active tab |
| Todoist — Inbox task list — `0f4e64b8-fe00-491f-8703-8fef32218aac` | Rows separated by hairline dividers, consistent side padding | Circular check targets; floating add button | Bold row title over smaller gray metadata | Brand red app bar and add button; due dates in color *and* text |
| Ivory — Drafts, swipe to delete — `6e265b74-f9b9-4c6e-9409-735577c55d8d` | One inset white row on a grouped gray background (about 16 pt from the edge by eye) | Row radius near the system's; Delete action as tall as the row | System font; centered bold nav title | Accent on the Close and Done bar buttons; system red for Delete |
| Brink — News Settings sheet — `768f87f2-62bf-42a9-b069-6f72889daaf0` | Side margins 12–16, section gap 18–22, icon-to-label 12, card inner padding 16–20 | Card radius 20; rows 52–60 tall; description asks for 44x44 targets | 17 pt regular labels; muted section headers; Dynamic Type called out | System green switches only |
| Apple Books — Add to Collection sheet — `8482728f-897e-486a-a1cf-026071e9bdb1` | Grouped card with generous padding; icon-to-text 16–20 | Large card radius; pill-shaped "New Collection…" button; tall rows | Serif display title (brand); sans labels, gray counts | None — black, gray, white |
| FoodNoms — Favorites, swipe to delete — `b706cc96-8078-4662-89e7-8b3fe1a1547e` | One rounded row with horizontal padding under a standard bar | Standard bar buttons; row-height Delete action | System font, bold centered title | Brand orange on Back, +, and Edit; system red Delete |
| Rise — Tasks — `c0c13aa0-2583-401e-abcb-6c411a23a53b` | Consistent vertical spacing; sections labeled Todo and Done | Rounded filled search field; circular checkboxes; floating add button | Bold title near 24 pt; gray section labels | Brand purple on done checkboxes, add button, active tab |
| Crouton — Groceries — `c470a16f-db1d-451a-9950-1851e26b1691` | Evenly spaced rounded cards with padding | Circular + and more buttons; swipe Delete | Large bold title; medium-weight items | System blue (#007AFF) for quantities and the active tab; system red Delete |
| LookUp — Translations settings — `f2da9d79-35f3-4141-ac10-fb3a2d3c0ad0` | System grouped layout: cards about 16 pt from the edge, rows about 50 pt, thin inset separators (by eye) | System inset-grouped radius; system switch | 34 pt bold large title; 17 pt regular rows | System blue back link; system green switch |
| Weather mini — Settings sheet — `f5d2dddb-6895-4c78-9b0b-b90cf8fd36cc` | Cards inset 16–20; row padding 20–24; pronounced gaps between sections | Large continuous-looking card radii; grab handle | Bold section headers in gray; footnote helper text | Almost none: monochrome with chevrons |

Expanded with `refero_get_similar_screens`: from LookUp — Microsoft Copilot "Display
language" (`c7681c44-a034-4f95-adae-b84402a75550`), Castro "Discover Country"
(`4e211cef-e70c-4a16-b5e2-a6d8ae681e14`), and Ivory "Languages"
(`5177ce30-e07b-4c96-a77e-59f0b158916c`): plain single-column lists, thin separators, and
the accent only on the selection checkmark. From Ivory — Gmail "Chat" settings
(`ab797462-9a06-4bf6-8bac-9cd1ef3dcc5f`): one rounded card with a toggle on the grouped
background; ChatGPT "Saved Memories" (`ba41eee1-b866-4f25-a54c-1de3cf501e90`): a red
"Delete All" text button as the non-gesture path to a destructive action.

## Reviewed flows

- **OKURI — Add To-Do Item — flow `11865`** (5 steps): the list's add action opens a
  composer with the keyboard already up; the entry is validated as non-empty; it submits
  from the button or the keyboard's return key; the composer closes and the new row is in
  the list. The template's pinned add bar is the same loop without the modal step.
- **Miles — First-time onboarding and Health permission setup — flow `6704`** (5 steps):
  a welcome card, an in-app explanation before the system permission sheet, the sheet,
  a one-card tutorial, then the main screen in its empty state. The pattern an app's lock
  inherits: explain before the system prompt, and land on an honest empty state.

## Styles, as a check

`refero_search_styles` for `native iOS productivity app minimal` returned web marketing
pages only (Perplexity, Shuttle, ChatGPT, Things, Doo, Todoist, Goodnotes). They agree on
restraint — a neutral canvas and one accent reserved for the primary action — which
confirms the direction. Nothing else is taken from them: their hex palettes and web font
stacks are not iOS tokens.

## Synthesis

**Where the references agree.** One column. Content about 16 pt from the screen edge —
the system inset, not a value each app invents. Rows at least 44 pt tall, usually 50–60,
with hairline separators inset to the text. Grouped content on the grouped background in
rounded containers. A large bold title, 17 pt body text, and secondary gray for
metadata and section headers. The accent marks what can be tapped or what is selected,
never text that cannot. Destructive swipe actions are system red, and the good ones also
offer a non-gesture route (FoodNoms' and Ivory's Edit or Done, ChatGPT's Delete All). An
empty list shows a symbol, a title, and a sentence, and keeps the add action in reach.

**Where they disagree, and the call.**

- *Add action:* a floating add button (Todoist, Rise, Superlist) versus a bar button
  (Crouton, FoodNoms) versus a bottom composer (OKURI). The floating button is a brand
  and Android idiom with no standard iOS component; the template keeps its pinned add bar
  built from standard components in a `safeAreaInset`.
- *Accent:* brand red, purple, or orange versus system blue (Crouton, LookUp). The
  template keeps system blue by leaving `AccentColor` without a value.
- *Rows:* custom shadowed cards (Crouton, Planny) versus system list rows (LookUp, Ivory,
  FoodNoms). The template uses `List` and lets the OS draw the rows.
- *Radius:* system containers keep the system's radius (LookUp); custom containers in
  the references run large (Brink's 20, Weather mini). `Radius.large` is 20 for a custom
  card; a standard component is never re-rounded.

## Reference lock

```text
Primary reference/direction: the native iOS system list as LookUp's Translations settings renders it (f2da9d79-35f3-4141-ac10-fb3a2d3c0ad0) — grouped background, standard List rows, SF text styles, system controls.
Preserve: system canvas and semantic colors; text styles with a large navigation title; the system's content inset and row height (at least 44 pt); accent only on interactive or selected elements; hairline separators and the system swipe-to-delete.
Borrow only: (1) Rise's filled rounded field (c0c13aa0-2583-401e-abcb-6c411a23a53b) for the draft field — a semantic tertiary fill in a continuous rounded rectangle, so it reaches 44 pt; (2) Superlist's empty inbox (02d61834-d91c-490e-8105-e8cfecfeafb1) — the empty state keeps the add action on screen.
Role rules: accent tints controls and the prominent Add button, nothing else; system red only for destructive actions; secondary style for metadata and completed items; color never the only signal (a completed item is also struck through and its glyph changes).
Media strategy: none — SF Symbols in their default rendering (checklist, circle, checkmark.circle.fill); no images or illustration.
Reject: floating add buttons; brand-colored bars; shadowed custom cards; serif display titles; custom Color Sets; any token from a web style.
Token commitments: background — system (List default); type — system text styles, Dynamic Type; accent — AccentColor with no value (system blue); spacing — 2/4/8/12/16/24/32 pt; radius — 8/12/20 pt, continuous; minimum hit target — 44 pt; motion — .default, or none under Reduce Motion; no shadows, no custom materials.
```

## Decision ledger

| Decision | Source | Rule / role | Why |
|---|---|---|---|
| Template stays unbranded | Brief constraint | Overrides the skill's push toward a distinctive direction | Every app departs from the template; a brand here is one every app must undo |
| `Spacing.xxSmall = 2` | Brief (pre-decided scale); no reviewed screen contradicts | Glyph to a tightly bound caption | The smallest step that still reads as a gap |
| `Spacing.xSmall = 4` | Brief; Rise and Todoist stack a title over metadata tightly | Lines of one block; `TodoRow`'s glyph box to its title | With the 44 pt glyph box centered, 4 more lands the title about 15 pt from the glyph — Brink's 12–16 |
| `Spacing.small = 8` | Brief; SwiftUI's own default between related views is of this order | Related controls in one row | Keeps a row's controls reading as one group |
| `Spacing.medium = 12` | Brink `768f87f2` (icon-to-label 12); the old `Layout.barSpacing` was 12 | Field to its submit action | Unchanged value, now shared |
| `Spacing.large = 16` | Brink `768f87f2` and Weather mini `f5d2dddb` (inner padding 16–20); LookUp `f2da9d79` edge inset ≈ 16 | Inside a custom container | Matches the system's own inset, so custom and standard content align |
| `Spacing.xLarge = 24` | Brink `768f87f2` (section gap 18–22); Weather mini `f5d2dddb` (pronounced section gaps) | Between groups | The next step that separates groups rather than items |
| `Spacing.xxLarge = 32` | Brief; Apple Books `8482728f` and Superlist `02d61834` use generous space around headers | Between sections that stand apart | Doubles `large`, the scale's top |
| Screen-edge inset is the system's, not a token | LookUp `f2da9d79`, Ivory `6e265b74` (≈ 16 pt, system-drawn); HIG Layout | `List`/`Form` insets and `.padding()` | The system varies it by device and size class; a token would freeze one value |
| `Radius.small = 8` | Brief; Rise `c0c13aa0` rounded badges | Tags, thumbnails | Small elements need a visibly smaller radius than their container |
| `Radius.medium = 12` | Rise `c0c13aa0` (rounded filled search field); LookUp `f2da9d79` (system card radius ≈ 10–12 by eye) | Control-sized containers — the draft field | Close to the system's control rounding, so a custom field sits beside system controls |
| `Radius.large = 20` | Brink `768f87f2` (card radius 20); Weather mini `f5d2dddb` (large card radii) | Cards and grouped containers | The two custom-card references agree |
| Radii are `.continuous` | HIG Layout and the system's own containers; RoundedRectangle docs | `RoundedRectangle(cornerRadius:style: .continuous)` | Matches the curvature the OS draws |
| `Size.minimumHitTarget = 44` | HIG Buttons and Accessibility (44x44 pt on iOS); Brink `768f87f2` | Every tappable element, both dimensions | Measured in the simulator after the change: toggle 44x44, field 44 tall, Add 50 tall |
| `Motion.animation(reduceMotion:)` → `nil` or `.default` | HIG Motion ("make motion optional"); `accessibilityReduceMotion` docs | Every state-change animation | No custom durations; motion personality is an app's lock |
| Color: semantic only | HIG Color, Dark Mode, Accessibility; Crouton `c470a16f` and LookUp `f2da9d79` use system colors | `.primary`, `.secondary`, `.tint`, `.background`, `.fill` styles | System colors carry light, dark, and increased-contrast variants for free |
| Accent: `AccentColor` with no value (system blue) | HIG Color; build setting `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` (set in `project.yml`) | Tint of controls app-wide | The template does not brand |
| Type: text styles, system font, Dynamic Type; `@ScaledMetric` for text-bound sizes | HIG Typography; LookUp `f2da9d79` (34/17 pt system styles) | `.font(.body)` and siblings | Verified to AX5 in the screenshots |
| Symbols: SF Symbols, default rendering | HIG SF Symbols; every reviewed screen uses glyphs, not images | `Image(systemName:)`, `Label` | Rendering mode per context is an app's lock |
| Liquid Glass by standard components; no `UIDesignRequiresCompatibility` | Adopting Liquid Glass; `UIDesignRequiresCompatibility` docs | `NavigationStack`, `List`, bars, sheets | Built with the Xcode 26 SDK they take Liquid Glass on iOS 26 and the older look on iOS 18 |
| No iOS 26-only API in template code; custom glass only via the documented `ViewModifier` pattern | `glassEffect(_:in:)` docs (iOS 26.0, macOS 26.0) | `designing-ui` › Materials and Liquid Glass | The floor is iOS 18 and `MyAppUI` builds for macOS 15 |
| Draft field: plain style on `.fill.tertiary` in `Radius.medium` | Rise `c0c13aa0`; measured: `.roundedBorder` stays 34 pt tall under a taller frame | The one custom-drawn container in `TodoListView` | The only way found to a 44 pt field without a custom control |
| Add button: `.borderedProminent` at `.controlSize(.large)` | HIG Buttons (44 pt); measured 50 pt tall | The primary action | The regular size falls under 44 pt |
| App icon: placeholder stays | HIG App Icons; Icon Composer docs | `App/Assets.xcassets/AppIcon.appiconset` | Icon Composer `.icon` versus an asset catalog is an app decision |

## Template defaults vs. app decisions

| Template default | Each app decides in its design-lock ADR |
|---|---|
| Spacing, radius, hit-target, motion tokens above | Adjusted spacing or radii, density |
| Semantic system colors; system accent | Accent color (Any/Dark/Increased-contrast variants), brand colors |
| System font, text styles, Dynamic Type | A custom font (with license and Dynamic Type scaling), type roles per screen |
| SF Symbols, default rendering | Rendering mode per context, custom symbols/images |
| Standard components; automatic Liquid Glass | Custom glass or materials, where and on which OS |
| — | Navigation structure (tabs vs. stack), iPad layout, haptics, motion personality, copy voice, app icon |

## Visual QA

The to-do list with two items and its empty state, on an iPhone 16e (the smallest iPhone
device type offered, iOS 26.1), in light, dark, `accessibility-extra-extra-extra-large`,
and Increase Contrast, taken with `running-the-app`'s `simctl` commands. The screenshots
are the pull request's evidence, not files in the repository. Compared against the lock:

- Held: system grouped background and rows, large title, secondary gray for the empty
  state's text, accent only on the Add button, 44 pt or larger targets, text wrapping at
  AX5 with nothing clipped, legible in dark and Increase Contrast.
- Accepted: the done glyph sits about 11 pt inside the row's leading inset because its
  44 pt hit box is centered on it; the field (44 pt) is shorter than the large Add button
  (50 pt). Both are the cost of the hit-target rule on system components.
- Not the template's to fix: the disabled Add button is faint — the system's disabled
  style, shown while the draft is empty.

## Sources

All checked 2026-09-30.

- <https://developer.apple.com/design/human-interface-guidelines/accessibility> — 44x44 pt
  default control size on iOS; 4.5:1 minimum text contrast; Increase Contrast; more than
  color alone.
- <https://developer.apple.com/design/human-interface-guidelines/buttons> — a hit region
  of at least 44x44 pt.
- <https://developer.apple.com/design/human-interface-guidelines/color> — system colors
  carry light, dark, and increased-contrast variants; accent on prominent buttons.
- <https://developer.apple.com/design/human-interface-guidelines/dark-mode> — 4.5:1
  minimum, 7:1 for custom colors in small text.
- <https://developer.apple.com/design/human-interface-guidelines/typography> — text
  styles with the system font support Dynamic Type.
- <https://developer.apple.com/design/human-interface-guidelines/layout> — safe areas,
  system margins, readable text width, size classes.
- <https://developer.apple.com/design/human-interface-guidelines/motion> — make motion
  optional.
- <https://developer.apple.com/design/human-interface-guidelines/sf-symbols> — the four
  rendering modes.
- <https://developer.apple.com/design/human-interface-guidelines/app-icons> — layered
  icons in Icon Composer; default, dark, clear, and tinted appearances.
- <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass> —
  standard components adopt Liquid Glass when built with the latest SDKs.
- <https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility>
  — a temporary compatibility-mode key, iOS 26.0; ignored when building for iOS 27.
- <https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)> — iOS 26.0,
  macOS 26.0.
- <https://developer.apple.com/documentation/xcode/build-settings-reference> —
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, the default tint color on iOS.
- <https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion>
  — iOS 13.0, macOS 10.15.
- <https://developer.apple.com/documentation/swiftui/roundedrectangle> — iOS 13.0,
  macOS 10.15.
