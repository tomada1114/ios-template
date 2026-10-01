# Contributing

Thank you for considering a contribution! This document explains how to set up
your development environment and submit changes.

## Prerequisites

Install these tools:

- [Xcode][xcode], the version pinned in `.xcode-version`
  (CI uses exactly that one), **with its iOS platform installed**: Xcode › Settings ›
  Components. A fresh Xcode can lack it, and then every simulator step fails.
- [mise][mise] — provides the pinned CLI tools from `mise.toml`
- [Just][just] (optional — you can run
  the underlying commands directly)

Then:

```bash
mise trust     # approve mise.toml (asked once per fresh clone)
just install
```

If your Xcode lacks the iOS platform, `just test` and `just lint` still run; the
simulator steps run in CI's `App Build & UI Test (iOS Simulator)` and
`Package Tests (iOS Simulator)` jobs.

## Development Workflow

Every recipe, in `justfile` order:

```bash
# Show available recipes
just

# Install pinned tools, git hooks, and generate the Xcode project
just install

# Regenerate MyApp.xcodeproj from project.yml
just generate

# Format code
just fmt

# Format, auto-fix SwiftLint violations, then run the full lint check
just fix

# Run formatters and linters in check mode (swiftformat, swiftlint, shellcheck, actionlint, typos, skills mirror)
just lint

# Verify the git hooks are installed and executable (skips under CI or ALLOW_MISSING_GIT_HOOKS)
just verify-hooks

# Run the plain-bash tests for scripts/ and the skills' Python suites
just test-scripts

# Re-assert the harness's claims about itself (scripts/checks/)
just check-harness

# Run the package tests on the host Mac with the 80% line / 75% function coverage floors on MyAppCore
just test

# Run only the tests matching FILTER, with no coverage floor
just test-fast TodoItemTests

# Build the app (Debug) for the iOS Simulator
just build

# Build (Debug), then install and launch it on an iOS Simulator
just run

# Build (Debug), then install and launch it on a connected iPhone
just run-device

# Stream this app's log output from the booted simulator (Ctrl-C to stop)
just logs

# Make the booted simulator forget this app's privacy grants
just reset-permissions

# Run the XCUITest launch test on an iOS Simulator
just uitest

# Run the package tests on an iOS Simulator (no coverage floor)
just test-ios

# Build Release and assert the app launches and stays alive on a simulator
just smoke

# Run all checks: verify-hooks → fmt → lint → test-scripts → check-harness → test → build
just check

# Regenerate the .claude/skills/ mirror from .agents/skills/ (run after any skill edit)
just agents-sync

# Fail if .claude/skills/ is not byte-identical to .agents/skills/ (writes nothing)
just agents-check

# Remove build artifacts and the generated project
just clean

# Create or update GitHub labels from .github/labels.yml (never deletes)
just labels

# Create or update the "main" branch ruleset (admin-only)
just ruleset
```

**Without Just**, run the equivalent commands (`just check` is the justfile's
`check` recipe: verify-hooks, fmt, lint, test-scripts, check-harness, test, build):

```bash
mise install
git config core.hooksPath .githooks   # pre-commit lint gate (just install does this)
scripts/verify-hooks.sh               # confirm the hooks are installed and executable
mise exec -- xcodegen generate        # just generate
mise exec -- swiftformat .            # just fmt
mise exec -- swiftlint lint --fix --quiet   # just fix = swiftformat, this, then scripts/lint.sh
mise exec -- scripts/lint.sh          # just lint
mise exec -- scripts/tests/run.sh     # just test-scripts
mise exec -- scripts/checks/run-all.sh   # just check-harness
scripts/coverage.sh                   # just test
(cd Packages/MyAppKit && swift test --filter TodoItemTests)   # just test-fast TodoItemTests
xcodebuild -project MyApp.xcodeproj -scheme MyApp -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dev-derived-data build   # just build
scripts/run-simulator.sh              # just run (after the build)
scripts/run-device.sh                 # just run-device (after xcodegen generate)
xcrun simctl spawn booted log stream --level debug --predicate "subsystem == \"$(scripts/bundle-id.sh)\""   # just logs
scripts/reset-permissions.sh          # just reset-permissions
rm -rf build/LaunchUITests.xcresult
xcrun simctl bootstatus "$(scripts/simulator-destination.sh --udid)" -b
xcodebuild test -project MyApp.xcodeproj -scheme MyApp -destination "$(scripts/simulator-destination.sh)" -derivedDataPath build/dev-derived-data -resultBundlePath build/LaunchUITests.xcresult   # just uitest
(cd Packages/MyAppKit && xcodebuild test -scheme MyAppKit-Package -destination "$(../../scripts/simulator-destination.sh)" -derivedDataPath ../../build/ios-test-derived-data -resultBundlePath ../../build/MyAppKitTests-iOS.xcresult)   # just test-ios
mise exec -- scripts/smoke_launch.sh  # just smoke
scripts/sync-agents.sh                # just agents-sync
scripts/sync-agents.sh --check        # just agents-check
scripts/sync-labels.sh                # just labels — writes labels to the GitHub repo gh is pointed at
scripts/apply-ruleset.sh              # just ruleset — admin-only
```

## Pull Request Process

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Ensure `just check` passes
4. Write or update tests for your changes
5. Open a pull request and fill in its checklist —
   [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md)

### Code Standards

- New logic lives in `MyAppCore` with Swift Testing coverage (happy + error path)
- SwiftLint strict and SwiftFormat must pass with no warnings
- Maintain or improve the 80% line-coverage and 75% function-coverage floors on `MyAppCore`
- Public API carries `///` doc comments that explain *why*

### Commit Messages

Use Conventional Commits for both commits and PR titles:

```
<type>(<optional-scope>): <short summary>
```

Examples:

- `feat: add JSON export support`
- `fix(ui): keep the keyboard from covering the text field`
- `docs: update installation guide`

Recommended types: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`,
`perf`, `build`, `deps` (dependency bumps).

### Changelog Policy

`CHANGELOG.md` (in [Keep a Changelog][keep-a-changelog] format) is
the canonical, human-curated record of user-facing changes. Add an entry
under `[Unreleased]` for any user-facing change in the same PR that makes it.

GitHub's auto-generated release notes are supplementary — useful for a quick
PR-by-PR diff, but `CHANGELOG.md` is what users should read to understand what
changed in a release.

## Getting Help

If something is unclear, open an issue. We're happy to help you get started.

[xcode]: https://developer.apple.com/xcode/
[mise]: https://mise.jdx.dev/
[just]: https://just.systems/man/en/installation.html
[keep-a-changelog]: https://keepachangelog.com/
