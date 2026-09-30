---
name: running-the-app
description: >
  Covers running this iOS app on the Simulator to see a change working: just run to
  install and launch the fresh Debug build, confirming the installed app really is that
  build (simctl get_app_container), reading its unified-log output with just logs or
  simctl spawn log show, screenshots with simctl io screenshot, dark appearance, Dynamic
  Type content sizes and a clean status bar with simctl ui and simctl status_bar, deep
  links with simctl openurl, simulated pushes with simctl push, launch arguments such as
  -uiTesting, a throwaway XCUITest under just uitest, answering a permission prompt with
  simctl privacy or just reset-permissions, and an iOS Simulator control tool when the
  host has one. Use when asked to run, launch, or screenshot the app, when a change has
  to be verified in the real app rather than in tests, when the app must be observed
  with no human at the keyboard, or when deciding what evidence a pull request carries
  for behavior no CI job can assert.
---

# Running the App

**Owns:** launching this app on the iOS Simulator to observe a change, reading what it
emits, and the evidence that lands in the pull request. **Does not own:** whether a
behavior belongs in a test at all (`.claude/rules/testing.md`, `tdd`); how a system API
is structured behind a port (`integrating-system-apis`); how a view is written
(`building-swiftui-screens`); what a pull request looks like (`create-pr`).

Running the app proves wiring, not logic. Every decision is owned by `MyAppCore` and
gated by `just test`; `just build`, `just uitest`, and `just smoke` prove the app
compiles, launches, and stays alive. None of them shows what a person sees — the view
that renders nothing, the empty state behind a denied permission, the log line that
never fires. That is what launching is for, and its result is evidence in the pull
request, never a substitute for a test.

## Launch the build you just made

```bash
just run      # just build, then scripts/run-simulator.sh
```

`scripts/run-simulator.sh` boots the device `scripts/simulator-destination.sh` picks
(`SIMULATOR_DEVICE="iPhone 17" just run` picks another), opens Simulator.app, installs
the Debug build, and launches it with `--terminate-running-process`: launching an app
that is already running only foregrounds the old process, so you would be watching the
previous build. The bundle identifier comes from `project.yml` through
`scripts/bundle-id.sh`, never a literal.

Confirm the installed app is the build in *this* checkout before trusting what you see.
Another worktree or clone of the same app installs under the same identifier and
replaces this one silently:

```bash
app="$(xcrun simctl get_app_container booted "$(scripts/bundle-id.sh)")"
diff -rq "$app" build/dev-derived-data/Build/Products/Debug-iphonesimulator/MyApp.app \
  && echo "installed bundle matches this checkout's build"
```

Compare the whole bundle, not the `MyApp` executable: a Debug build keeps its code in
`MyApp.debug.dylib`, and the executable beside it is a small stub that barely changes
between builds. A log line the change adds is the other proof — see it in the stream.

## Read what it says

Shipped code logs through `AppLog` (`os.Logger`), never `print`
(`docs/architecture.md` › Logging): one subsystem, the bundle identifier, and one
category per concern (`todos`, `persistence`).

```bash
just logs     # simctl spawn booted log stream --level debug, this app's subsystem
```

Four things cost time if you guess them:

- **`just logs` streams until Ctrl-C**, which an unattended session cannot send, and
  killing the `just` process leaves its `simctl` child streaming. Run the stream
  itself in the background, do the thing, then stop it by pid:

  ```bash
  mkdir -p build/logs
  xcrun simctl spawn booted log stream --level debug \
    --predicate 'subsystem == "com.example.MyApp"' > build/logs/stream.log 2>&1 &
  stream_pid=$!
  xcrun simctl launch --terminate-running-process booted com.example.MyApp
  kill "$stream_pid"; cat build/logs/stream.log
  ```

- **`log show` reaches only what was persisted.** `xcrun simctl spawn booted log show
  --last 5m --predicate 'subsystem == "com.example.MyApp"'` prints an empty table for
  `.debug` lines such as `load: 0 items`, even with `--debug --info`; it sees `.notice`
  (Default) and above. Stream for anything lower.
- **Anything user-derived is redacted.** `title=<private>` is the design
  (`TodoListViewModel.addDraft()` logs it `.private`). Assert on the public half of the
  line instead of turning private data on.
- **`getpwuid_r did not find a match for uid 501`** on the first line is the simulator's
  noise, not your app's.

Swap `com.example.MyApp` for `"$(scripts/bundle-id.sh)"` in a script; a renamed app has
its own identifier.

## See it without a human at the keyboard

[references/observing-behavior.md](references/observing-behavior.md) has the verified
recipes: `xcrun simctl io booted screenshot`, dark appearance, Dynamic Type sizes and a
clean status bar, deep links and simulated pushes, launch arguments and environment
variables for a known state, a throwaway XCUITest that drives a flow, and an iOS
Simulator control tool if your host has one.

## Where a human is unavoidable

On the Simulator, nothing is by default. A permission prompt is answered without one:
`xcrun simctl privacy booted grant <service> <bundle-id>` for the services it supports
(**REQUIRED:** `integrating-system-apis`, its `references/permissions.md` lists them for
this Xcode), a tap with a Simulator control tool, or `just reset-permissions` to make
the next launch ask again. What still needs a person, asked for once, up front, in one
message:

- **A physical device** — signing with a development team, a real camera, real push
  delivery through APNs, a background task launch (Apple's debugger route works only on
  a device), anything the Simulator does not model.
- **A service `simctl privacy` cannot set** — its list varies by Xcode, and a prompt it
  cannot answer needs a tap, by a person or a control tool.

## The evidence a pull request carries

No gate runs any of this, so the pull request is where it lands. State the exact
commands, not a paraphrase, and attach:

- **A screenshot per changed state**, taken with the commands in the reference — light
  and dark, and the largest Dynamic Type size for a screen that shows text.
- **A log excerpt** with the predicate above it, for behavior whose only observable is a
  log line.

Never paste a Team ID, a signing identity, an Apple ID, a provisioning-profile name, or
a physical device's UDID: a pull request here, or in a repository cut from this
template, may be public. Simulator UDIDs and container paths are harmless but noisy —
shorten them to `<udid>` and `~`. Redact, and say that you did.

Leave nothing behind: delete any throwaway test and re-run `just generate`, put the
simulator back (`xcrun simctl ui booted appearance light`,
`xcrun simctl ui booted content_size large`, `xcrun simctl status_bar booted clear`),
and check `git status --porcelain` is empty. `build/` is gitignored, so screenshots and
logs written there can stay.
