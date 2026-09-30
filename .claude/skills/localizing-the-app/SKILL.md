---
name: localizing-the-app
description: >
  Covers every string a person reads and its translation, meaning the String Catalog
  Localizable.xcstrings under Sources/MyAppCore/Resources, defaultLocalization in
  Package.swift, Core returning LocalizedStringResource with bundle .module,
  Text(verbatim:) in MyAppUI, LocalizationTests, xcodebuild -exportLocalizations, and an
  app-target InfoPlist.xcstrings for Info.plist strings. Use when adding or changing
  user-facing wording, a Text or Button title, a catalog key, comment, plural, or
  translation; when a string shows its key, reads right in English but never translates,
  or a catalog key goes stale; when an app adds a usage description or display name; or
  when an app considers a second language.
---

# Localizing the App

**Owns:** where user-facing wording lives, how a string is declared so it can be
translated, keeping the String Catalog and the code in step, where `Info.plist` strings
go, and what adding a language involves. **Does not own:** a view model's shape and
injecting a `Locale` to format a number or date (`designing-core-logic`); how a view is
wired to its model and its accessibility identifiers (`building-swiftui-screens`);
capitalization and voice (`designing-ui`'s copy rules and design lock); which
usage-description key a system API needs (`integrating-system-apis`); the ADR a second
language owes (`recording-architecture-decisions`); the English-only rule and its one
exception (`AGENTS.md`'s "Important Reminders").

## What the template decides

- **English only.** `Package.swift` sets `defaultLocalization: "en"`, and the one
  catalog's source language is `en`. Shipping a second language is an app's decision,
  recorded as an ADR: every later string then owes a translation, and every translation
  owes a reviewer.
- **Core owns the wording.** Core returns `LocalizedStringResource` (Foundation, which
  Core may import) and a view renders it. The wording then sits under the coverage floor,
  where a test asserts it; a Core API that handed out bare keys would leave the view to
  know the key, the bundle, and the fallback, none of it tested.
- **One catalog, in Core.** `MyAppCore` declares `resources: [.process(...)]` for it;
  `MyAppUI` has no catalog and no resources. The one exception is the app target's own
  `Info.plist` strings ("Strings outside Core" below).

## Declaring a string

`TodoListStrings.emptyDescription` is the worked example:

```swift
LocalizedStringResource(
    "todoList.empty.description",
    defaultValue: "Items you add appear here.",
    bundle: .module,
    comment: "Explanation under the empty-list headline.",
)
```

Every part is there for a reason:

- **`bundle: .module`.** The default, `.main`, is the app bundle, which has no catalog:
  the string would read correctly in English and never translate. `.module` resolves to
  `Bundle.module`, which SwiftPM generates because the target declares a resource.
- **`defaultValue`.** `swift test` (`just test`) builds with SwiftPM's native build
  system, which copies the `.xcstrings` into Core's bundle uncompiled, so the English a
  test sees comes from here. Without it a test would see the key.
- **An explicit key**, `feature.purpose` (`todoList.add`, `todoList.failure.save`), not
  the English text: the English can be polished without re-keying every translation, and
  a key is something a test and a search can name.
- **`comment`** is a translator's only context: where the text appears and what each
  argument is.
- **One whole sentence per state**, with arguments interpolated (a `String` becomes
  `%@`, an `Int` becomes `%lld`), never a fixed prefix glued to a swapped-in fragment: a
  translation must be free to reorder the sentence around its arguments.
  `TodoListFailure.message` shows the shape — one sentence per failure, not one prefix
  and three endings.
- **A computed property**, as every `TodoListStrings` member and
  `TodoListFailure.message` are: the initializer's `locale` defaults to `.current` when
  the resource is built, so each read builds it afresh.
- **No generated symbols.** `xcodebuild` runs `GenerateStringSymbols` over the catalog,
  but SwiftPM's native build does not, so code that names one fails to compile under
  `just test`.

## In `MyAppUI`

- A view has no localizable literal. `Text("…")` and `Button("…")` take a
  `LocalizedStringKey` that is looked up in the app's main bundle, not the package's, and
  `-exportLocalizations` exports it under a `MyAppUI` strings file that has nowhere to
  ship. Render a Core resource instead, as `TodoListView` does:
  `Text(TodoListStrings.emptyTitle)`, `Button(TodoListStrings.add) { … }`,
  `.accessibilityLabel(Text(toggleLabel))`.
- What is not language is `Text(verbatim:)`: the user's own text (`TodoRow`'s
  `Text(verbatim: item.title)`), a number (formatted in Core with an injected `Locale`
  when formatting matters), a glyph, and a preview's note to the developer.
- Accessibility identifiers are never localized (`building-swiftui-screens`).

## Strings outside Core

- `Info.plist` strings are the app target's, not Core's: a usage description such as
  `NSCameraUsageDescription`, or `CFBundleDisplayName`. The system reads them from the
  app bundle, so a package catalog cannot hold them.
- When an app adds one, its wording lives in `App/InfoPlist.xcstrings`, an app-target
  String Catalog (`project.yml`'s `sources: [App]` already takes in any file under
  `App/`). The template ships none.
- That catalog is exempt from `LocalizationTests` — the suite scans Core only — and is
  reviewed by hand: every key has a `comment` and an `en` value.
- The export below already carries the generated `Info.plist`'s `CFBundleName` as a
  synthesized `App/en.lproj/MyApp-InfoPlist.strings`; no file by that name exists in the
  repository.

## Keeping the catalog in step

- A new or changed key lands in the Core code, `Localizable.xcstrings`, and
  `LocalizationTests.everyCase()` in the same change. The suite scans every
  `LocalizedStringResource(…)` call in `Sources/MyAppCore` (`ResourceDeclarationScan`)
  and fails until all three agree: a call without an explicit key, a `defaultValue`, or
  `bundle: .module`; a declared key the catalog or `everyCase()` lacks; a catalog key
  declared nowhere; or catalog English that differs from `defaultValue`. It reads the
  catalog's source, not a compiled bundle, because `swift test` never compiles one.
- A new case on an enum whose `message` is a resource (`TodoListFailure`) fails the
  source-scan test until `everyCase()` lists it. That is intended.
- The scan is text, not a parser. It does not see a resource made from a bare literal
  (`let title: LocalizedStringResource = "Add"`, which also lands in the main bundle),
  `String(localized:)`, or anything in `MyAppUI` — review catches those.
- Edit the catalog in Xcode's editor, or by hand in the format Xcode writes: two-space
  indent, `" : "` separators, keys sorted, no trailing newline (`.editorconfig`'s
  `[*.xcstrings]` section keeps an editor from fighting that). A key the code uses has a
  `comment` and an `en` `stringUnit` with `"state" : "translated"`, and no
  `extractionState`.
- To find drift, run:

  ```bash
  just generate
  xcodebuild -exportLocalizations -project MyApp.xcodeproj -localizationPath build/localizations -exportLanguage en
  ```

  Checked on Xcode 26.5 (17F42), 2026-09-30: it exits 0 without `-sdk` (it builds for
  the generic iOS device SDK) and writes `build/localizations/en.xcloc`, which is
  gitignored. On a catalog already in step it left `Localizable.xcstrings` untouched
  (`git diff --stat` empty). It extracts every key from Core's source **and can rewrite
  the catalog in place**: a key in code but not in the catalog is added
  (`"extractionState" : "extracted_with_value"`, `"state" : "new"`), and a key no code
  uses gains `"extractionState" : "stale"`. Review that diff like any other, and revert
  it if it only reordered keys or added `extractionState`; neither `just build` nor
  `swift build` touches the catalog.

## What each build does with the catalog

Checked on Xcode 26.5 (17F42) with Swift 6.3.2, 2026-09-30:

| | `swift build` / `swift test` (`just test`) | `xcodebuild` (`just build`, the app) |
|---|---|---|
| The catalog in Core's resource bundle (`*_MyAppCore.bundle`) | copied as `Localizable.xcstrings`, uncompiled | compiled to `en.lproj/Localizable.strings` |
| Where English comes from at run time | each resource's `defaultValue` | the catalog |

An iOS app bundle is flat: Core's resource bundle sits directly inside `MyApp.app/`, with
no `Contents/`. `swift build --build-system swiftbuild` (a preview) compiles the
catalog too, but `scripts/coverage.sh` uses the native build. No gate looks inside the
app: after `just build`,
`find build -path '*MyApp.app/*' -name 'Localizable.strings*'` finds the compiled
strings, and `plutil -p` on that file shows what shipped.

## Plurals

A count inside a sentence is a plural, not `"\(count) items"`: vary the entry by plural
in Xcode's catalog editor, which stores `variations` instead of a `stringUnit`.
`LocalizationTests` reads `stringUnit` only, so the first plural extends its
`CatalogLocalization` to read `variations` and asserts the `one` and `other` English
forms.

## Adding a language

In an app cut from the template, a second language is an ADR the owner accepts before
any translation lands (`recording-architecture-decisions`): which language, who
translates, and who reviews. Then:

- Add the language in Xcode's catalog editor, or import a translated `.xcloc` with
  `xcodebuild -importLocalizations`. Keys, comments, and the English stay English; the
  translated values are the one non-English text the repository allows. An
  `App/InfoPlist.xcstrings`, if the app has one, owes the same language.
- Unverified: whether iOS offers the app in that language from the package bundle's
  `.lproj` alone or also needs `CFBundleLocalizations` in `project.yml`. The ADR keeps
  this as an open question until it is checked in the running app (`running-the-app`),
  then records the answer.
- Unverified: how `typos` (`just lint`) treats translated values; the ADR decides whether
  an exclusion is warranted, which is a gate change (`changing-gates`).
