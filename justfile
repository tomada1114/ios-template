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

# Run formatters and linters in check mode (swiftformat, swiftlint, shellcheck, actionlint, typos, skills mirror)
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
# each listed in AGENTS.md's Enforcement layers
[doc("Re-assert the harness's claims about itself (scripts/checks/)")]
check-harness:
    mise exec -- scripts/checks/run-all.sh

# Run the MyAppKit tests on the host Mac with the 80% line / 75% function coverage floors on MyAppCore
test:
    scripts/coverage.sh

# Run only the tests matching FILTER (swift test --filter), with no coverage floor —
# for fast local iteration; `just test` is still the gate
[doc("Run only the tests matching FILTER, with no coverage floor")]
test-fast filter:
    cd Packages/MyAppKit && swift test --filter '{{filter}}'

# Build the app (Debug) for the iOS Simulator. The generic destination needs no
# particular device installed, and its product installs on any simulator (`just run`).
build:
    mise exec -- xcodegen generate
    set -o pipefail && xcodebuild -project MyApp.xcodeproj -scheme MyApp -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dev-derived-data build | mise exec -- xcbeautify --quiet

# Build (Debug), then install and launch it on an iOS Simulator, replacing any
# running instance (scripts/run-simulator.sh; SIMULATOR_DEVICE picks the device)
[doc("Build (Debug), then install and launch it on an iOS Simulator")]
run: build
    scripts/run-simulator.sh

# Stream this app's unified-log output from the booted simulator (subsystem == the
# bundle identifier project.yml declares), until you stop it with Ctrl-C
[doc("Stream this app's log output from the booted simulator (Ctrl-C to stop)")]
logs:
    bundle_id="$(scripts/bundle-id.sh)" && xcrun simctl spawn booted log stream --level debug --predicate "subsystem == \"${bundle_id}\""

# Run the XCUITest launch test on an iOS Simulator (scripts/simulator-destination.sh
# picks the device; SIMULATOR_DEVICE overrides it)
[doc("Run the XCUITest launch test on an iOS Simulator")]
uitest:
    mise exec -- xcodegen generate
    rm -rf build/LaunchUITests.xcresult
    set -o pipefail && xcodebuild test -project MyApp.xcodeproj -scheme MyApp -destination "$(scripts/simulator-destination.sh)" -derivedDataPath build/dev-derived-data -resultBundlePath build/LaunchUITests.xcresult | mise exec -- xcbeautify

# Run every MyAppKit test suite on an iOS Simulator, with no coverage floor (`just test`
# holds the floor on the host). Exercises code behind `#if os(iOS)` and the iOS runtime.
[doc("Run the package tests on an iOS Simulator (no coverage floor)")]
test-ios:
    rm -rf build/MyAppKitTests-iOS.xcresult
    set -o pipefail && cd Packages/MyAppKit && xcodebuild test -scheme MyAppKit-Package -destination "$(../../scripts/simulator-destination.sh)" -derivedDataPath ../../build/ios-test-derived-data -resultBundlePath ../../build/MyAppKitTests-iOS.xcresult | mise exec -- xcbeautify

# Build Release, then assert the app launches and stays alive on an iOS Simulator
# (scripts/smoke_launch.sh; SIMULATOR_DEVICE picks the device)
[doc("Build Release and assert the app launches and stays alive on a simulator")]
smoke:
    mise exec -- scripts/smoke_launch.sh

# Run all checks: verify hooks, format, lint, script tests, harness checks, test, build
# (CI adds uitest, smoke, and test-ios)
[doc("Run all checks: verify-hooks, fmt, lint, test-scripts, check-harness, test, build")]
check: verify-hooks fmt lint test-scripts check-harness test build

# Regenerate the .claude/skills/ mirror from .agents/skills/ (run after any skill edit)
agents-sync:
    scripts/sync-agents.sh

# Fail if .claude/skills/ is not byte-identical to .agents/skills/ (writes nothing)
agents-check:
    scripts/sync-agents.sh --check

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
