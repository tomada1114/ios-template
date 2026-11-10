# Why the toolchain is shaped this way

The reasoning behind the build and gate choices every app cut from this template starts
with. The values themselves live in their files (`project.yml`, `Package.swift`,
`.xcode-version`, `justfile`); this file holds only the why. A change that replaces one
of these choices rewrites its entry here, in the present tense, in place of the old
reason.

## iOS 27 as the minimum OS, built with Xcode 27

`deploymentTarget` in `project.yml` and `platforms:` in `Packages/MyAppKit/Package.swift`
are iOS 27, built with the Xcode in `.xcode-version`. Apps cut from this template are
built for their owner's own devices, which run the current iOS, so the floor is the
current major release: every API the SDK ships, Liquid Glass included, is usable without
an `#available` branch, and the one simulator runtime CI's Xcode ships is the floor
itself. Lowering it is an app's design change (`AGENTS.md`'s "Before changing the
architecture").

## XcodeGen, with a gitignored `.xcodeproj`

`project.yml` is declarative, diffable, and safely editable by both humans and agents; a
raw `pbxproj` is a UUID graph that merge conflicts and agents can silently corrupt, and
the whole app target stays reviewable as text. `MyApp.xcodeproj` is treated like a
lockfile-derived artifact: regenerate it (`just generate`), never hand-edit it. The
trade-off is that XcodeGen is a third-party tool with its own bus factor, but the
manifest is simple enough to migrate away from if that ever matters.

## Swift 6 language mode, warnings as errors

`Package.swift`'s `strictSettings` turns on the Swift 6 language mode and treats every
warning as an error from the first line, so data-race safety is checked from day one and
there is never a "migrate later" (`SKILL.md`'s "`Package.swift`'s `strictSettings`").

## Just

One command — `just check` — runs the same gates locally that CI runs. Just has cleaner
syntax than Make and is a task runner, not a build system, which is exactly what an Xcode
project needs. Every recipe also works without Just: `CONTRIBUTING.md` lists the commands
each one runs.

## A gitignored `Config/Local.xcconfig`, and no distribution pipeline

Apps cut from this template run on the owner's own iPhone. A development team is its
owner's and that machine's, so it stays out of every tracked file: it lives in
`Config/Local.xcconfig`, which is gitignored, which the commit-time guard refuses, and
which `Config/Debug.xcconfig` includes only when it exists; `just run-device` then
builds, installs, and launches from the command line. App Store and TestFlight
distribution are left to the app that needs one — a design change and a signing change
(`AGENTS.md`'s "Security and human approval"). The setup is `docs/running-on-device.md`;
the rules are `.claude/rules/project.md`'s Local Signing Identity.
