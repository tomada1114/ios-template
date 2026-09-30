# Observing behavior with no human at the keyboard

Ways to watch a running build on the iOS Simulator: screenshots in the states a person
may put the device in, deep links and pushes, a launch into a known state, and a
throwaway UI test that drives a flow. Every command here was run against this
template's app on Xcode 26.5 with the iOS 26.5 simulator (checked 2026-09-30); each
subcommand's own `xcrun simctl help <subcommand>` is the authority when an Xcode
changes it. Write every artifact under `build/` — it is gitignored, and nothing below
belongs in a commit.

## Screenshots

```bash
mkdir -p build/screenshots
xcrun simctl io booted screenshot build/screenshots/list-light.png
```

It writes a PNG of the device's display (`--type=jpeg` and others exist) and needs no
permission on the host. Look at the file before believing it: a screenshot taken
before the app finished drawing shows the launch screen.

The states a screen owes its evidence in:

```bash
xcrun simctl ui booted appearance dark        # and back: appearance light
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
xcrun simctl ui booted content_size large     # the default
xcrun simctl status_bar booted override --time 9:41
xcrun simctl status_bar booted clear
```

- Run either `ui` subcommand with no argument to print the current value; do that first
  and put back what you found. `content_size` takes the standard sizes `extra-small`
  … `extra-extra-extra-large` and the accessibility sizes `accessibility-medium` …
  `accessibility-extra-extra-extra-large`, the largest.
- The running app picks up an appearance or text-size change without a relaunch; give
  it a second to redraw before the screenshot.
- `ui booted increase_contrast enabled` is there too, for a screen whose colors are the
  change.
- A status-bar override stays until `clear` or a device erase, across app launches —
  clear it when you are done, or the next person's screenshots carry your 9:41.

## Deep links and pushes

```bash
xcrun simctl openurl booted https://example.com          # opens Safari
xcrun simctl openurl booted myapp://item/1               # fails: no app claims the scheme
```

`openurl` hands the URL to the system exactly as a tap on a link would, so it exercises
the app's URL handling only once the app declares a scheme or an associated domain —
the template declares neither, and the second line fails with
`LSApplicationWorkspaceErrorDomain, code=115`. Declaring either is an app's decision.

```bash
printf '{"aps":{"alert":{"title":"Probe","body":"Hello"}}}\n' > build/payload.apns
xcrun simctl push booted "$(scripts/bundle-id.sh)" build/payload.apns
```

`simctl push` delivers a remote-notification payload (a top-level `aps` object, at most
4096 bytes) to the app as if APNs had sent it; it prints
`Notification sent to '<bundle-id>'`. Whether a banner appears depends on the app's
notification authorization, and a payload whose top-level `Simulator Target Bundle` key
names the app can omit the identifier argument. It never proves your server or your
APNs configuration — that is a device, and a human.

## Start the app in a known state

```bash
xcrun simctl launch --terminate-running-process booted com.example.MyApp -uiTesting
SIMCTL_CHILD_PROBE_STATE=known-state \
  xcrun simctl launch --terminate-running-process booted com.example.MyApp -uiTesting
```

- Everything after the bundle identifier becomes the process's arguments.
  `App/MyAppApp.swift` reads `-uiTesting` and opens an in-memory store, so the list
  starts empty and nothing touches the on-disk store; `LaunchTests` passes the same
  argument through `XCUIApplication.launchArguments`.
- An environment variable reaches the app only with the `SIMCTL_CHILD_` prefix, which
  `simctl` strips: the line above starts the app with `PROBE_STATE=known-state`, which
  `ProcessInfo` reads. Nothing in the template reads it; it proves the channel.
- To check what a launch really received: the app runs as a host process, so
  `ps -o command= -p <pid>` shows its arguments and `ps -E -o command= -p <pid>` its
  environment. The pid is the number `simctl launch` prints.

**Do not add a launch hook to the app just to look at a state.** A state a Core test can
construct is a state a `#Preview` can show by injecting a view model already in it
(`building-swiftui-screens`). A hook is warranted only for a state that is expensive to
reach by hand and wanted from both a UI test and a person; it is read in `App/`, the
composition root, and turned into one value a Core type takes, as `-uiTesting` is.

## Drive a flow with a throwaway XCUITest

`LaunchUITests/` is the one XCTest target (`project.yml`'s `MyAppLaunchUITests` takes
the whole directory), so a probe is one file plus `just generate`. The screen already
carries identifiers for what a test touches — `newItemField`, `addButton`,
`retryButton`, `toggle-<uuid>` (`TodoListView.swift`) — and a new control needs one
before it can be driven.

```swift
// LaunchUITests/ScratchProbeTests.swift — throwaway, never committed
import XCTest

final class ScratchProbeTests: XCTestCase {
    @MainActor
    func testProbe() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let field = app.textFields["newItemField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("Water plants")
        app.buttons["addButton"].tap()
        XCTAssertTrue(app.staticTexts["Water plants"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "after-adding-an-item"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
```

Run only that test, into a result bundle of its own, and export the screenshot:

```bash
mise exec -- xcodegen generate
xcodebuild test -project MyApp.xcodeproj -scheme MyApp \
  -destination "$(scripts/simulator-destination.sh)" \
  -derivedDataPath build/dev-derived-data -resultBundlePath build/Probe.xcresult \
  -only-testing:MyAppLaunchUITests/ScratchProbeTests
xcrun xcresulttool export attachments --path build/Probe.xcresult \
  --output-path build/probe-attachments
```

`xcodebuild` refuses to overwrite an existing result bundle, so move the old one aside
first. The export writes each attachment under a UUID file name plus a `manifest.json`
mapping it to its `suggestedHumanReadableName` (`after-adding-an-item_0_….png`) and the
test it came from. `just uitest` runs the whole scheme, the launch guarantee included,
into `build/LaunchUITests.xcresult`; use it when you want both.

The probe is deleted before the pull request, followed by `just generate`.
`LaunchUITests/` holds the launch guarantee and nothing else; a behavior worth keeping
is a Core test against a fake (`.claude/rules/testing.md` › Where a Test Goes).

## An iOS Simulator control tool, if your host has one

Some hosts give the agent a tool that taps, types, swipes, and screenshots a booted
simulator directly — in Claude Code's desktop app, the `Claude_Code_iOS_Simulator` MCP
server's `control` tool, with actions such as `attach`, `launch`, `screenshot`, `tap`,
`swipe`, `text`, and `open_url`. When it is there, it drives a flow without a test file
and taps a permission prompt `simctl privacy` cannot answer. Its first use of a device
asks the user for access, so it is part of the up-front ask, and with nobody at the
keyboard that request goes unanswered — everything above works without it, and the
evidence is still a `simctl` screenshot a reader can reproduce.
