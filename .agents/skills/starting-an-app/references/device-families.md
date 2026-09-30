# Device families: iPhone only, or iPhone and iPad

Two choices cover most apps started from this template. Make one before writing
features: it decides which layouts every screen owes, which devices the launch test
runs on, and what the App Store lists. Record it as the app's first ADR (`SKILL.md` ›
"Recording both decisions").

| | iPhone and iPad (what the template ships) | iPhone only |
|---|---|---|
| `TARGETED_DEVICE_FAMILY` (app and UI-test targets) | `"1,2"` | `"1"` |
| Orientation keys in `project.yml` | `…_iPhone` and `…_iPad` | `…_iPhone` only |
| Multiple windows | on (the generated scene manifest) | not applicable |
| `just uitest` | the first available iPhone; an iPad on request | the first available iPhone |

Everything else is identical: the layers and the one-way dependency direction, ports
and adapters, the coverage floor, signing, and every gate.

## `project.yml`

`project.yml` is the only place these settings live; `MyApp.xcodeproj` is generated
(`just generate`) and never edited. Change the app target and the `MyAppLaunchUITests`
target together — the UI-test bundle declares its own `TARGETED_DEVICE_FAMILY`, and the
two should name the same families.

### iPhone only

```yaml
        TARGETED_DEVICE_FAMILY: "1"
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: >-
          UIInterfaceOrientationPortrait
```

Set `"1"` on both targets, and delete `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`,
which no longer applies. The orientation list is its own decision: the template allows
portrait and both landscapes on iPhone; a portrait-only app keeps just
`UIInterfaceOrientationPortrait`, as above.

### iPhone and iPad

Keep `"1,2"` and both orientation keys. The template's iPad list allows all four
orientations; narrowing it is a decision to record in the same ADR, with the platform
rule it runs into cited by URL, not a default to reach for.

### Multiple windows on iPad

The template sets `INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES`, and the
manifest Xcode generates from it sets `UIApplicationSupportsMultipleScenes` to `true`:
an iPad user can open the app in more than one window. There is no `INFOPLIST_KEY_…`
build setting for that one key — Xcode's build-setting specification lists only the
`…_Generation` switch for the manifest (checked in Xcode 26.5,
`CoreBuildSystem.xcspec`). To turn multiple windows off, drop the generation switch and
declare the manifest through XcodeGen's `info:` on the app target instead:

```yaml
    info:
      path: App/Info.plist
      properties:
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
```

Measured on a clone of this template with Xcode 26.5: with the generation switch still
set, the generated manifest wins and the built `Info.plist` still reads `true`; with it
removed and the `info:` block above added, the built `Info.plist` reads `false` and the
other generated keys (`CFBundleShortVersionString` from `MARKETING_VERSION` among them)
are unchanged. That was checked with `plutil -p` on the Debug simulator build's
`Info.plist` only — run `just build` and `just uitest` on the change before relying on
it. `App/Info.plist` is then a generated file XcodeGen rewrites on every
`just generate`, so the `properties:` block is the source of truth, never the file.

## `App/MyAppApp.swift`

The device family changes nothing in the entry point: one `WindowGroup` serves iPhone
and iPad alike. Multiple windows do change what it means. The template holds its view
model in `@State` on the `App` struct, so the model outlives any one scene's view tree;
with multiple windows on, every window shows that same instance — two windows are two
views of one list. If each window should hold its own state, the state moves into the
scene's view tree (a view that owns it inside the `WindowGroup`), and that is part of
the same ADR. A phone-only app, or an iPad app with multiple windows off, has one scene
and no such question.

## `LaunchUITests`

`just uitest` runs `LaunchUITests` on the device `scripts/simulator-destination.sh`
chooses: the first available iPhone on the newest installed iOS runtime, unless
`SIMULATOR_DEVICE` names a device. For an app that keeps iPad, run the launch test on
an iPad too before merging a layout change:

```bash
xcrun simctl list devices available | grep iPad   # pick a name from this list
SIMULATOR_DEVICE="iPad (A16)" just uitest
```

Device names change with each Xcode's runtimes, which is why nothing pins one. CI's
`app` job runs the iPhone destination only, so an iPad layout is asserted by no gate
unless the app adds a step for it — a gate change (`changing-gates`). The launch test
itself needs no edit for either family: it finds its elements by accessibility
identifier and label, not by position.

## Not this reference's subject

How a screen adapts between compact and regular size classes, and which layouts an
iPad screen owes, is `building-swiftui-screens`'s subject. Recording the choice is
`recording-architecture-decisions`'.
