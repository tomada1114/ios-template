# Permissions, usage descriptions, and the privacy manifest

Where each privacy-related declaration lives in this repository, how a permission is
exercised on the Simulator, and what adding one owes. Apple's pages are linked, not
restated; every link and command below was checked on 2026-09-30 against Xcode 26.5
with the iOS 26.5 simulator.

## The app's Info.plist is generated

```bash
grep -n GENERATE_INFOPLIST_FILE project.yml
```

The app target sets `GENERATE_INFOPLIST_FILE: YES`: Xcode builds the `Info.plist` from
build settings, and there is no `Info.plist` file in `App/` to edit. So a key goes into
`project.yml` in one of two places, depending on its type.

**A string key** — every usage description — is an `INFOPLIST_KEY_<key>` build setting on
the app target:

```yaml
targets:
  MyApp:
    settings:
      base:
        INFOPLIST_KEY_NSCameraUsageDescription: "Scans a document you choose to add."
```

The [build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
lists the keys Xcode generates this way ("Privacy - Camera Usage Description",
`INFOPLIST_KEY_NSCameraUsageDescription`). The string is what the system prompt shows
under the app's name: say what the person gets, in a sentence
([`NSCameraUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription)).

**An array or dictionary key** — `UIBackgroundModes`,
`BGTaskSchedulerPermittedIdentifiers` — has no build setting. It goes in the app
target's `info:` block, which XcodeGen writes to the named file on every
`just generate`; Xcode then merges the generated keys into it:

```yaml
targets:
  MyApp:
    info:
      path: App/Info.plist
      properties:
        UIBackgroundModes: [processing]
        BGTaskSchedulerPermittedIdentifiers: [com.example.MyApp.refresh]
```

Verified by building with both blocks and reading the product
(`plutil -p build/dev-derived-data/Build/Products/Debug-iphonesimulator/MyApp.app/Info.plist`):
the camera string, both arrays, and the generated keys were all present. XcodeGen
rewrites `App/Info.plist` on every `just generate`, so edit `project.yml`, never that
file. Apple's pages:
[`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes),
[`BGTaskSchedulerPermittedIdentifiers`](https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers).

## A missing usage string is a crash no gate catches

The system terminates an app that requests a protected resource without the matching
usage description
([Requesting authorization to capture and save media](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)).
It compiles, `just test` never requests anything, and `just uitest` only catches it if
its flow reaches the request. So the key lands in the same commit as the adapter, and
the pull request shows the prompt on the Simulator with the string in it
(`running-the-app`).

## The privacy manifest

A required-reason API — `UserDefaults`, file timestamps, disk space, system boot time,
active keyboards — needs a declared reason in a `PrivacyInfo.xcprivacy` in the app
target, or App Store Connect rejects the upload
([Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api);
the category values are listed under
[`NSPrivacyAccessedAPIType`](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype);
the file format is
[Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)).
Put it at `App/PrivacyInfo.xcprivacy`: `project.yml`'s `sources: [App]` picks it up, and
a Debug build copies it into the bundle root (verified). The template ships none,
because nothing in it calls a required-reason API; the first `UserDefaults` key an app
adds brings the manifest with it.

## Adding a permission owes an ADR

A privacy-gated permission — a usage-description key, a background mode, a
required-reason declaration — is one of the changes `AGENTS.md` › "Before changing the
architecture" lists. Write the ADR as Proposed, naming the feature that needs it and
what the app does while it is denied (**REQUIRED:** `recording-architecture-decisions`).
A background mode or any other capability is also an entitlement or signing change,
which needs the owner's sign-off.

## Exercising a permission on the Simulator

```bash
xcrun simctl privacy booted grant photos com.example.MyApp
xcrun simctl privacy booted revoke photos com.example.MyApp
xcrun simctl privacy booted reset all com.example.MyApp    # what just reset-permissions runs
```

`grant` answers the prompt before it appears, `revoke` puts the app in its denied state,
and `reset` makes the next request prompt again. Some changes terminate the running app.
Use `"$(scripts/bundle-id.sh)"` in place of the literal identifier in anything you keep.

The services `simctl privacy` accepts vary by Xcode. Print them first:

```bash
xcrun simctl help privacy
```

On Xcode 26.5 the help lists `all`, `calendar`, `contacts-limited`, `contacts`,
`location`, `location-always`, `photos-add`, `photos`, `media-library`, `microphone`,
`motion`, `reminders`, and `siri`. Two findings from that version:

- `grant camera` exited 0 although `camera` is not in the help. Unverified: whether it
  has any effect — the Simulator has no camera to test it against.
- `grant notifications` fails with `Operation not permitted`. Notification
  authorization on the Simulator is answered by tapping the prompt — by a person, or a
  Simulator control tool if the host has one — and put back with
  `just reset-permissions`.

`just reset-permissions` (`scripts/reset-permissions.sh`) reads the identifier from
`project.yml`, refuses with `ERR_RESETPERM_NO_BOOTED_DEVICE` when no simulator is
booted, and resets every service for this app on the booted device only — never the
person's own grants on a physical device, which only Settings changes.

`simctl privacy` is a shortcut, not a substitute: its own help warns that bypassing the
prompt can mask a missing usage description. Before the pull request, `reset` and let
the real prompt appear once.
