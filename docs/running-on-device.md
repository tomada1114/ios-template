# Running on your own iPhone

`just run-device` builds the Debug app, installs it on a connected iPhone or iPad, and
launches it. It is the only route off the simulator this template ships: apps cut from
it are for the owner's own phone, and App Store and TestFlight distribution are not
planned.

## What you need

- An Apple account signed in under Xcode › Settings › Accounts.
- A free Personal Team works, with limits: provisioning profiles expire 7 days after
  they are issued, a free account covers up to 3 devices and up to 3 apps per device,
  and capabilities such as push notifications and iCloud are not available
  ([Choosing a membership](https://developer.apple.com/support/compare-memberships/),
  checked 2026-09-30).
- A paid Apple Developer Program membership lifts those limits (same page).

## One-time setup

1. Create `Config/Local.xcconfig` holding one line, `DEVELOPMENT_TEAM = <team ID>`,
   with the team ID Xcode › Settings › Accounts shows for your account.
   `Config/Debug.xcconfig` includes it; it is gitignored, and the commit-time guard
   refuses it. Never set `DEVELOPMENT_TEAM` in `project.yml`: a target's own setting,
   even an empty one, overrides the xcconfig.
2. Connect the iPhone with a cable, unlock it, and tap Trust for this Mac.
3. Enable Developer Mode under Settings › Privacy & Security › Developer Mode. The
   phone restarts
   ([Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device),
   checked 2026-09-30).
4. With a Personal Team, after the first install, trust the developer under
   Settings › General › VPN & Device Management; until then the launch is refused.

## The bundle identifier

The template's `com.example.MyApp` may be refused, because an App ID is unique across
all teams. Run `just run-device` in an app cut from the template, after
`scripts/bootstrap.sh` has given it your own prefix. Never work around this by
overriding `PRODUCT_BUNDLE_IDENTIFIER` in `Local.xcconfig`: the bundle identifier is
contract (`docs/architecture.md` › What is contract and what is private), and
`AppLog.subsystem` follows it.

## Everyday use

- `just run-device` regenerates the project, checks a team is set (it never prints
  it), picks the connected device, builds with `-allowProvisioningUpdates
  -allowProvisioningDeviceRegistration` (so Xcode may create a profile and register
  the phone in your Apple account), installs, and relaunches the app, replacing any
  running instance.
- With more than one phone connected, set `IOS_DEVICE` to a device name or identifier
  from `xcrun devicectl list devices`: `IOS_DEVICE="My iPhone" just run-device`.
- After a Personal Team's 7-day expiry the app no longer opens; run `just run-device`
  again.
- For logs, open Console.app, select the device, and filter by subsystem (the bundle
  identifier). `just logs` reads the simulator only.
- Each failure names itself on its first stderr line (`ERR_DEVICE_NO_TEAM`,
  `ERR_DEVICE_NONE`, `ERR_DEVICE_BUILD_FAILED`, `ERR_DEVICE_INSTALL_FAILED`,
  `ERR_DEVICE_LAUNCH_FAILED`), followed by what to do next.

## What is unverified

Checked on 2026-09-30 against this Mac's Xcode: `xcodebuild -help` lists both
provisioning flags, `devicectl device process launch --help` lists
`--terminate-existing`, and `devicectl --device` accepts a UDID, a CoreDevice UUID, or
a name. `devicectl list devices --json-output` reports a CoreDevice `identifier`
distinct from `hardwareProperties.udid`; the script passes the latter to both
`xcodebuild -destination id=` and `devicectl`.

- Unverified (2026-09-30): a full `just run-device` on a real phone — no owner-run
  build, install, and launch has been recorded yet.
- Unverified (2026-09-30): the `connectionProperties.tunnelState` value a connected
  phone reports. Only `unavailable` (a paired but disconnected phone) was observed, so
  the script skips `unavailable` rather than requiring a specific connected value.
- Unverified (2026-09-30): that `xcodebuild -destination id=` accepts
  `hardwareProperties.udid` for a phone connected over CoreDevice.
