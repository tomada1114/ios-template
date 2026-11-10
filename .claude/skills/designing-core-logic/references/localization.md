# Localization: what each build does with the catalog

Core owns every fixed string a reader sees, in
`Sources/MyAppCore/Resources/Localizable.xcstrings`, and English is the only shipped
language (`defaultLocalization: "en"`). How a string is declared and how the catalog is
kept in step with the code are `.claude/rules/core.md` › Wording and localization; this
file holds why those rules are what they are, how to find drift, and what a second
language raises.

## The two builds

Checked on Xcode 26.5 (17F42) with Swift 6.3.2, 2026-09-30:

| | `swift build` / `swift test` (`just test`) | `xcodebuild` (`just build`, the app) |
|---|---|---|
| The catalog in Core's resource bundle (`*_MyAppCore.bundle`) | copied as `Localizable.xcstrings`, uncompiled | compiled to `en.lproj/Localizable.strings` |
| Where English comes from at run time | each resource's `defaultValue` | the catalog |

That is why every resource carries a `defaultValue` (tests resolve English from it,
through the `english` helper in `MyAppCoreTests`), and why `LocalizationTests` reads the
catalog's source rather than a compiled bundle. An iOS app bundle is flat: Core's
resource bundle sits directly inside `MyApp.app/`. No gate looks inside the app; after
`just build`, `find build -path '*MyApp.app/*' -name 'Localizable.strings*'` finds the
compiled strings and `plutil -p` shows what shipped.

## Finding drift between code and catalog

```bash
just generate
xcodebuild -exportLocalizations -project MyApp.xcodeproj -localizationPath build/localizations -exportLanguage en
```

It writes the gitignored `build/localizations/en.xcloc` and can rewrite the catalog in
place: a key in code but not the catalog is added (`"state" : "new"`), and a key no code
uses gains `"extractionState" : "stale"`. Review that diff, and revert it when it only
reorders keys or adds `extractionState`. Neither `just build` nor `swift build` touches
the catalog. The export also carries the generated `Info.plist`'s `CFBundleName` as a
synthesized `App/en.lproj/MyApp-InfoPlist.strings`, which exists in no file.

## A second language

A second language is a design change the owner approves first (`.claude/rules/core.md`).
It is added in Xcode's catalog editor or with `xcodebuild -importLocalizations`; keys,
comments, and the English stay English, and an `App/InfoPlist.xcstrings` owes the same
language. Two questions stay open until an app checks them: whether iOS offers the
language from the package bundle's `.lproj` alone or also needs `CFBundleLocalizations`
in `project.yml` (checked in the running app), and how `typos` treats translated values
(an exclusion would be a gate change).
