# Permissions, usage descriptions, and the privacy manifest

Where each privacy-related declaration lives in this repository, how a permission is
exercised on the Simulator, and what adding one owes. Apple's pages are linked, not
restated; every link and command below was last verified on 2026-09-30 against Xcode 26.5
with the iOS 26.5 simulator, and has not been re-run on the pinned Xcode 27.0 except
where a passage says so.

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
The app's manifest is `App/PrivacyInfo.xcprivacy`: `project.yml`'s `sources: [App]`
picks it up, and a Debug build copies it into the bundle root (verified on 2026-11-11 with
`plutil -p` on the built `MyApp.app/PrivacyInfo.xcprivacy`). It exists because
`UserDefaultsPreferences` reads and writes the app's own defaults: it declares no
tracking, no tracking domains, no collected data, and one accessed-API entry,
`NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` — "read and write
information that is only accessible to the app itself" (checked on 2026-11-11 against
the reasons listed under `NSPrivacyAccessedAPIType`). An app that also shares defaults
through an App Group suite adds `1C8F.1` alongside `CA92.1` in the same entry.
`PrivacyManifestTests` parses the file and fails when that entry or `CA92.1` goes
missing, when the accessed-API array is malformed, or when a category has two entries.

A new required-reason API adds its own entry, with its own reason, in the same pull
request as the code that calls it. `RequiredReasonAPITests` holds that: it scans every
Swift, C, and Objective-C file (`.swift`, `.c`, `.h`, `.m`, `.mm`) under
`Packages/MyAppKit/Sources/` and `App/` for the symbols Apple lists per category, in
their Swift and Objective-C spellings — `UserDefaults`/`NSUserDefaults` (and SwiftUI's
`AppStorage` over it); file timestamps (`creationDate`, `modificationDate`,
`fileModificationDate`, `contentModificationDateKey`, `creationDateKey`, and calls to
`stat`, `lstat`, `fstat`, `fstatat`, `getattrlist` and its variants); system boot time
(`systemUptime`, `mach_absolute_time`); disk space (the `volume…CapacityKey` keys,
`systemFreeSize`, `systemSize`, and calls to `statfs`, `statvfs`, `fstatfs`,
`fstatvfs`); active keyboards (`activeInputModes`) — and fails, naming the file and
line, for each category the manifest gives no reason for (the table was checked on
2026-11-11 against the list under `NSPrivacyAccessedAPIType`). The scan is textual. It
strips `//` and `/* … */` comments and the text of one-line string literals before it
matches, and it counts a C function whose name is an everyday word (`stat`, `statfs`,
`getattrlist`) only as a call, the name followed by `(` on the same line. So it misses
a reference to one of those functions, a call split before its `(`, a call inside a
binary dependency or behind a renamed alias; it reports a listed name inside a
multi-line `"""` string, or a domain identifier that shares one (rename it, or
declare the category); and it cannot tell whether the declared reason is the right one
— choosing the reason stays the author's and the reviewer's. When Apple adds a symbol
or a category, the table in `RequiredReasonAPIScan` gains it, and so does
`scripts/build-device.sh`'s `REQUIRED_REASON_APIS` in its linked spelling.

The manifest only counts once it is in the bundle, and both suites read the source
file. `scripts/build-device.sh` (`just build-device`, in `just check-release`) therefore
fails when the Release device build's `MyApp.app` has no
`PrivacyInfo.xcprivacy` at its root (`ERR_BUILD_DEVICE_NO_PRIVACY_MANIFEST`, what a
`project.yml` that narrows `sources: [App]` or excludes the file would ship), when the
bundled file fails `plutil -lint` (`ERR_BUILD_DEVICE_PRIVACY_MANIFEST_INVALID`), or when
it differs from `App/PrivacyInfo.xcprivacy`, byte for byte and again as XML after
`plutil -convert xml1` (`ERR_BUILD_DEVICE_PRIVACY_MANIFEST_MISMATCH`). It then holds
the linked executable to the bundled manifest: the symbols the binary imports (`xcrun nm -u` — C functions such as `_stat`,
Foundation constants such as `_NSFileModificationDate` that Swift's `FileAttributeKey`
and `URLResourceKey` members link to, `_OBJC_CLASS_$_NSUserDefaults`, and Swift
symbols carrying `NSUserDefaults`, as `AppStorage`'s do) and the Objective-C selectors
it sends (`xcrun otool`: `systemUptime`, `activeInputModes`, `fileModificationDate`),
mapped by its `REQUIRED_REASON_APIS` table, and fails with
`ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API`, naming each category and the symbols
that put the binary in it, when one has no entry with a reason. That sees a call made
through a package or an alias, which the source scan does not; it still misses an
embedded framework, `dlsym`, and a selector built at run time. The
Keychain is not one of the required-reason categories: storing a secret through
`SecureStoring` adds no required-reason declaration.

## Adding a permission is a design change

A privacy-gated permission — a usage-description key, a background mode, a
required-reason declaration — is one of the changes `AGENTS.md` › "Before changing the
architecture" lists. The same pull request rewrites the present-state description in
`AGENTS.md`'s Architecture section, naming the feature that needs it and what the app
does while it is denied.
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

On Xcode 26.5, and again on Xcode 27.0 (2026-11-10), the help lists `all`, `calendar`, `contacts-limited`, `contacts`,
`location`, `location-always`, `photos-add`, `photos`, `media-library`, `microphone`,
`motion`, `reminders`, and `siri`. Two findings from Xcode 26.5, not re-checked on 27.0:

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
