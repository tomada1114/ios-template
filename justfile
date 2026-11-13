# Development task runner — requires Just (https://just.systems)
# All commands also work without Just by running the underlying commands directly.
# Tools come from mise (mise.toml pins the versions).

# Show available recipes
default:
    @just --list

# Install pinned tools, git hooks, and generate the Xcode project
install:
    mise install
    if git rev-parse --git-dir >/dev/null 2>&1; then git config core.hooksPath .githooks; else echo "Skipping git hook installation (not a Git repository)."; fi
    mise exec -- xcodegen generate
    @if command -v xcodebuild >/dev/null 2>&1; then xcode_local="$(xcodebuild -version | head -n1 | awk '{print $2}')"; xcode_pinned="$(cat .xcode-version)"; if [ "$xcode_local" != "$xcode_pinned" ]; then echo "warning: local Xcode $xcode_local differs from the CI-pinned $xcode_pinned — results may diverge from CI"; fi; fi
    just verify-hooks

# Regenerate MyApp.xcodeproj from project.yml
generate:
    mise exec -- xcodegen generate

# Format code
fmt:
    mise exec -- swiftformat .

# Format and auto-fix SwiftLint violations, then run the full lint check: some
# violations have no safe auto-fix, and the check reports what still needs a hand edit
[doc("Format, auto-fix SwiftLint violations, then run the full lint check")]
fix:
    mise exec -- swiftformat .
    mise exec -- swiftlint lint --fix --quiet
    just lint

# Run formatters and linters in check mode (swiftformat, swiftlint, shellcheck, actionlint, typos)
lint:
    mise exec -- scripts/lint.sh

# Verify the git hooks are installed and executable (skips under CI or ALLOW_MISSING_GIT_HOOKS)
verify-hooks:
    scripts/verify-hooks.sh

# Run the plain-bash tests for the scripts under scripts/ (through mise: the
# lint_test.sh number-separator case calls the pinned swiftformat and swiftlint)
[doc("Run the plain-bash tests for scripts/ and the skills' Python suites")]
test-scripts:
    mise exec -- scripts/tests/run.sh

# Re-assert the harness's claims about itself: every check under scripts/checks/,
# each listed in .claude/skills/changing-gates/references/enforcement-layers.md
[doc("Re-assert the harness's claims about itself (scripts/checks/)")]
check-harness:
    mise exec -- scripts/checks/run-all.sh

# Run the MyAppKit tests on the host Mac with the 80% line / 75% function coverage floors
# on MyAppCore, at a lower QoS with half the cores (scripts/run-throttled.sh; no lock:
# host `swift test` touches no simulator)
[doc("Run the MyAppKit tests on the host with the 80% line / 75% function floors on MyAppCore")]
test:
    scripts/run-throttled.sh -- scripts/coverage.sh

# Run only the tests matching FILTER (swift test --filter), with no coverage floor —
# for fast local iteration; `just test` is still the gate
[doc("Run only the tests matching FILTER, with no coverage floor")]
test-fast filter:
    cd Packages/MyAppKit && ../../scripts/run-throttled.sh -- swift test --jobs "$(../../scripts/run-throttled.sh --print-jobs)" --filter '{{filter}}'

# Build the app (Debug) for the iOS Simulator. The generic destination needs no
# particular device installed, and its product installs on any simulator (`just run`).
# Every xcodebuild and simulator recipe runs through `scripts/run-throttled.sh --lock`:
# one at a time across every worktree on this Mac, at a lower QoS, with half the cores
# (CHECK_JOBS and CHECK_QOS override; CI runs them at full speed, unlocked).
build:
    mise exec -- xcodegen generate
    set -o pipefail && scripts/run-throttled.sh --lock -- xcodebuild -jobs "$(scripts/run-throttled.sh --print-jobs)" -project MyApp.xcodeproj -scheme MyApp -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dev-derived-data build | mise exec -- xcbeautify --quiet

# Build Release for the iOS device SDK (`iphoneos`), unsigned, and assert the linked app
# exists and bundles a valid copy of App/PrivacyInfo.xcprivacy that declares every
# required-reason API the executable uses (scripts/build-device.sh): the one device-SDK
# compile any gate runs. No team is needed; nothing is archived,
# exported, signed, or installed.
[doc("Build Release for the iOS device SDK, unsigned, and assert the app and its privacy manifest")]
build-device:
    mise exec -- xcodegen generate
    mise exec -- scripts/run-throttled.sh --lock -- scripts/build-device.sh

# Run SwiftLint's analyzer rules (.swiftlint.yml's analyzer_rules: unused declarations
# and imports) over the compiler log of a clean build-for-testing of the app and of the
# package for the iOS Simulator (scripts/analyze.sh, which makes that log itself)
[doc("Run swiftlint analyze (unused declarations and imports) over a clean iOS Simulator build's log")]
analyze:
    mise exec -- xcodegen generate
    mise exec -- scripts/run-throttled.sh --lock -- scripts/analyze.sh

# Build (Debug), then install and launch it on an iOS Simulator, replacing any
# running instance (scripts/run-simulator.sh; SIMULATOR_DEVICE picks the device)
[doc("Build (Debug), then install and launch it on an iOS Simulator")]
run: build
    scripts/run-throttled.sh --lock -- scripts/run-simulator.sh

# Build (Debug) for a connected iPhone, then install and launch it there — needs
# Config/Local.xcconfig (docs/running-on-device.md); IOS_DEVICE picks the device
[doc("Build (Debug), then install and launch it on a connected iPhone")]
run-device:
    mise exec -- xcodegen generate
    scripts/run-throttled.sh --lock -- scripts/run-device.sh

# Stream this app's unified-log output from the booted simulator (subsystem == the
# bundle identifier project.yml declares), until you stop it with Ctrl-C
[doc("Stream this app's log output from the booted simulator (Ctrl-C to stop)")]
logs:
    bundle_id="$(scripts/bundle-id.sh)" && xcrun simctl spawn booted log stream --level debug --predicate "subsystem == \"${bundle_id}\""

# Make the booted simulator forget every privacy decision recorded for this app, so the
# next request prompts again (scripts/reset-permissions.sh; the identifier comes from
# project.yml). Changes simulator state.
[doc("Make the booted simulator forget this app's privacy grants")]
reset-permissions:
    scripts/reset-permissions.sh

# Run the XCUITest launch test on an iOS Simulator (scripts/simulator-destination.sh
# picks the device — an iPhone, or an iPad under SIMULATOR_FAMILY=ipad;
# SIMULATOR_DEVICE overrides it): uitest-build, then uitest-run
[doc("Run the XCUITest launch test on an iOS Simulator")]
uitest: uitest-build uitest-run

# Run the launch UI test on an available iPad (uitest-build and uitest-run under
# SIMULATOR_FAMILY=ipad; SIMULATOR_IPAD_DEVICE picks one, SIMULATOR_DEVICE is ignored),
# then shut that iPad down if this run booted it; skipped with a one-line notice when
# the app the test runs in resolves to TARGETED_DEVICE_FAMILY "1". scripts/uitest-ipad.sh
[doc("Run the launch UI test on an iPad simulator, then shut it down (skipped for an iPhone-only app)")]
uitest-ipad:
    mise exec -- scripts/uitest-ipad.sh

# Compile the app (Debug) and the launch UI test for the simulator uitest runs on,
# without running it. It is the one Debug compile in CI's app job and in `just check` (#58).
[doc("Build the app and the launch UI test for an iOS Simulator, without running it")]
uitest-build:
    mise exec -- xcodegen generate
    set -o pipefail && scripts/run-throttled.sh --lock -- xcodebuild build-for-testing -jobs "$(scripts/run-throttled.sh --print-jobs)" -project MyApp.xcodeproj -scheme MyApp -destination "$(scripts/simulator-destination.sh)" -derivedDataPath build/dev-derived-data | mise exec -- xcbeautify

# Where uitest-run writes its result bundle: its own path on an iPad
# (SIMULATOR_FAMILY=ipad, as `just uitest-ipad` runs it), so check-release keeps the
# iPhone run's bundle beside the iPad one.
uitest_result := if env_var_or_default("SIMULATOR_FAMILY", "") == "ipad" { "build/LaunchUITests-ipad.xcresult" } else { "build/LaunchUITests.xcresult" }

# Run the launch UI test that uitest-build compiled, without building it again
[doc("Run the launch UI test uitest-build compiled, without rebuilding")]
uitest-run:
    rm -rf {{uitest_result}}
    # Everything that touches the device runs inside one --lock, so a parallel run in
    # another worktree cannot boot, load, or measure it in the middle of this one; the
    # UDID is resolved once, and xcodebuild's own output alone goes to xcbeautify.
    # First boot the simulator and wait for it to finish: a cold boot inside
    # xcodebuild's launch window is what timed out on CI (#32). After a cold boot, wait
    # for it to settle too: a cold-booted simulator spends minutes on its own post-boot
    # work, during which a UI-test snapshot takes seconds and the test's waits time out
    # (#141). A device already booted is not waited for, and past a bound the run
    # continues under load and says so (scripts/wait-simulator-settled.sh; SIM_SETTLE_*
    # tune it).
    # Then pin the full software keyboard: with automatic minimization on, a hardware
    # keyboard shrinks it to a bar of no height, and the launch test waits for the full
    # one (#137). The setting persists on the device, so without this each run inherits
    # the last.
    set -o pipefail && scripts/run-throttled.sh --lock -- sh -c 'udid="$(scripts/simulator-destination.sh --udid)" && scripts/wait-simulator-settled.sh "$udid" >&2 && xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false >&2 && exec xcodebuild test-without-building -jobs "$THROTTLE_JOBS" -parallel-testing-enabled NO -project MyApp.xcodeproj -scheme MyApp -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/dev-derived-data -resultBundlePath {{uitest_result}}' | mise exec -- xcbeautify

# Run every MyAppKit test suite on an iOS Simulator, with no coverage floor (`just test`
# holds the floor on the host). Exercises code behind `#if os(iOS)` and the iOS runtime.
[doc("Run the package tests on an iOS Simulator (no coverage floor)")]
test-ios:
    rm -rf build/MyAppKitTests-iOS.xcresult
    set -o pipefail && cd Packages/MyAppKit && ../../scripts/run-throttled.sh --lock -- xcodebuild test -jobs "$(../../scripts/run-throttled.sh --print-jobs)" -parallel-testing-enabled NO -scheme MyAppKit-Package -destination "$(../../scripts/simulator-destination.sh)" -derivedDataPath ../../build/ios-test-derived-data -resultBundlePath ../../build/MyAppKitTests-iOS.xcresult | mise exec -- xcbeautify

# Build Release, then assert the app launches and stays alive on an iOS Simulator
# (scripts/smoke_launch.sh; SIMULATOR_DEVICE picks the device)
[doc("Build Release and assert the app launches and stays alive on a simulator")]
smoke:
    mise exec -- scripts/run-throttled.sh --lock -- scripts/smoke_launch.sh

# Run the checks a pull request needs: verify hooks, format, lint, script tests, harness
# checks, test, then each simulator check the change since origin/main touches
# (scripts/simulator-relevant.sh --check holds the path lists): the launch UI test for a
# UI or app change, the iOS package tests for a platform-adapter change. CHECK_ALL=1 runs
# both regardless; CHECK_JOBS and CHECK_QOS set the throttle (scripts/run-throttled.sh).
# smoke, build-device, and analyze are not here: `just check-release` runs them.
[doc("Run the pull-request checks: verify-hooks, fmt, lint, test-scripts, check-harness, test, and the simulator checks the change touches")]
check: verify-hooks fmt lint test-scripts check-harness test
    @if [ "$(scripts/simulator-relevant.sh --check uitest)" != false ]; then just uitest-build && just uitest-run; else echo "Skipped uitest-build, uitest-run (CHECK_ALL=1 runs them)"; fi
    @if [ "$(scripts/simulator-relevant.sh --check test-ios)" != false ]; then just test-ios; else echo "Skipped test-ios (CHECK_ALL=1 runs it)"; fi

# Run everything, on the commit a release is cut from: `just check` with every simulator
# check forced (the launch UI test on an iPhone), then the checks no pull request runs —
# the launch UI test on an iPad (skipped for an iPhone-only app), the Release launch,
# the Release device-SDK build, and the analyzer rules. Long by design (several clean
# builds); what it finds was merged earlier, so run it on main before tagging a
# release, and after a batch of merges.
# The iPhone legs pin SIMULATOR_FAMILY=iphone, so a SIMULATOR_DEVICE naming an iPad
# fails them instead of running the "iPhone" test on an iPad.
[doc("Run every check, the release-only ones included: check (all simulator checks), uitest-ipad, smoke, build-device, analyze")]
check-release:
    CHECK_ALL=1 SIMULATOR_FAMILY=iphone just check
    just uitest-ipad
    SIMULATOR_FAMILY=iphone just smoke
    just build-device
    just analyze

# Remove build artifacts and the generated project
clean:
    rm -rf build Packages/MyAppKit/.build MyApp.xcodeproj

# Create or update this repository's GitHub labels from .github/labels.yml
# (never deletes). Requires `gh`, authenticated against this repository: it is
# not a mise tool (see mise.toml), so it comes from your own PATH, not `mise exec --`.
[doc("Create or update GitHub labels from .github/labels.yml (never deletes)")]
labels:
    scripts/sync-labels.sh

# Create or update the "main" branch ruleset from .github/rulesets/main.json
# (admin-only: applying a ruleset needs repository admin permissions). Requires
# `gh`, authenticated against this repository: like `labels` above, it is not a
# mise tool, so it comes from your own PATH, not `mise exec --`.
[doc("Create or update the \"main\" branch ruleset (admin-only)")]
ruleset:
    scripts/apply-ruleset.sh
