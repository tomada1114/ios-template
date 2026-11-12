# Project Guide

This file holds what every agent needs before it knows which task it is on: what the
app is, how to check a change, where code goes, and which decisions need a human. Each
area's coding conventions are a rule under `.claude/rules/` ([Rules](#rules)); a kind of
change's procedure, and the design of the subject it touches, is a skill; a value a gate
enforces belongs to its config, and running the gate is how you learn it.

## Overview

This is an iOS SwiftUI app built from a strict template: XcodeGen generates the Xcode
project from `project.yml`, all real code lives in a local Swift package
(`Packages/MyAppKit`), and quality gates (SwiftLint strict, SwiftFormat, Swift 6
language mode, an 80% line-coverage and a 75% function-coverage floor on the Core
module) are enforced from day one. It ships a small worked example — a to-do list —
that exercises every seam an app needs: MVVM with `@Observable` view models, a
repository port with a SwiftData adapter, a fake and a contract test, and an XCUITest.

## Product

**TODO: in the template this section is a placeholder.** It is the one part of this
file about the application rather than the harness, so every repository cut from the
template writes its own: without it an agent implementing an issue here has no in-repo
answer to "is this in scope?". Fill in every `TODO:` below right after the rename
(`README.md`'s "Using This Template", step 3) — once `scripts/bootstrap.sh` has run,
`just check-harness` fails while one is left (`scripts/checks/product-section-filled.sh`).

- **What it is, and who it is for** — TODO: one paragraph. The problem it solves, and
  whose problem that is.
- **The core interaction** — TODO: the one thing a user does most. If the app does not
  do this well, nothing else about it matters.
- **Non-goals** — TODO: what this app deliberately does not do, even where it would be
  easy. Moving anything from here to a goal is a human's decision, not an implementer's.
- **Why it is shaped this way** — TODO: the reasoning behind the three entries above,
  in the present tense — why this audience, why this interaction comes first, and why
  each non-goal stays out — so a reader finds why and not only what. It is rewritten
  when the reasoning changes, not appended to ("Before changing the architecture").

## Quick Reference

```bash
just install       # Install pinned tools (mise), git hooks, and generate the Xcode project
just generate      # Regenerate MyApp.xcodeproj from project.yml
just fmt           # Format code (swiftformat)
just fix           # Format, auto-fix SwiftLint violations, then run just lint
just lint          # Lint (scripts/lint.sh: swiftformat --lint + swiftlint --strict + shellcheck + actionlint + typos)
just verify-hooks  # Verify the git hooks are installed and executable (scripts/verify-hooks.sh)
just test          # Run the package tests on the host Mac with the 80% line / 75% function floors on MyAppCore
just test-fast TodoItemTests  # Run only the matching tests, no coverage floor (iteration only)
just test-scripts  # Run the plain-bash tests for scripts/ and the skills' Python suites (scripts/tests/run.sh)
just check-harness # Re-assert the harness's claims about itself (scripts/checks/run-all.sh)
just build         # Build the app (Debug) for the iOS Simulator
just build-device  # Build Release for the iOS device SDK, unsigned, and assert the app and its privacy manifest
just run           # Build, then install and launch it on an iOS Simulator (SIMULATOR_DEVICE picks one)
just run-device    # Build (Debug), then install and launch it on a connected iPhone (Config/Local.xcconfig; IOS_DEVICE picks one)
just logs          # Stream this app's log output from the booted simulator (Ctrl-C to stop)
just reset-permissions  # Make the booted simulator forget this app's privacy grants
just uitest        # Run the XCUITest launch test on an iOS Simulator (uitest-build, then uitest-run)
just uitest-build  # Build the app and the launch UI test for an iOS Simulator, without running it
just uitest-run    # Run the launch UI test uitest-build compiled, without rebuilding
just test-ios      # Run the package tests on an iOS Simulator (no coverage floor)
just smoke         # Build Release and assert the app launches and stays alive on a simulator
just check         # Run all checks: verify-hooks → fmt → lint → test-scripts → check-harness → test → (uitest-build → uitest-run → smoke → build-device → test-ios, when simulator-relevant)
just clean         # Remove build artifacts and the generated project
just labels        # Create/update GitHub labels from .github/labels.yml (never deletes)
just ruleset       # Create/update the "main" branch ruleset from .github/rulesets/main.json (admin-only)
```

Without Just: run the commands in each `justfile` recipe (see CONTRIBUTING.md).
Building the app needs Xcode (`.xcode-version`) **with its iOS platform installed**
(Xcode › Settings › Components); `just test` needs only the Swift toolchain.

## Validating a change

Run the narrowest check that can fail, then `just check` before you open a PR. The rule
for the area you touched names its own check; the rest are here.

| What you changed | The narrowest check that can fail |
|---|---|
| The Release configuration, or anything only a Release launch shows | `just smoke`; `just build-device` too for the Release device build — the one `iphoneos` compile, which a device-only branch (`#if !targetEnvironment(simulator)`), an API one SDK lacks, or asset-catalog or linker validation breaks while every simulator build passes |
| Behavior only the running app shows | `just run`, then `just logs` — no gate asserts it, so the PR carries the evidence (a screenshot: `xcrun simctl io booted screenshot shot.png`; the `running-the-app` skill) |
| A permission prompt, or behavior after a grant is revoked | `just reset-permissions`, then `just run` |
| A `just` recipe name, a workflow's `uses:`, `permissions:`, `concurrency:`, or `run:` shell, a Dependabot or Renovate commit prefix or cooldown, a skill's frontmatter, the `## Product` section, `.claude/settings.json`'s `permissions` rules, the Core import ban list (`.swiftlint.yml`'s `no_ui_import_in_core` or `ArchitectureBoundaryTests.forbiddenModules`), the gates `just check` or `ci.yml` runs, `.github/rulesets/main.json`'s required contexts, or a label an issue form, a workflow, a dependency bot, or `scripts/label-pr.sh` applies | `just check-harness` |
| A skill under `.claude/skills/` | `just check-harness`; `just test-scripts` when the skill ships scripts (it runs their `scripts/tests/` unittest suite) |
| A workflow under `.github/workflows/` | `just lint` (actionlint), then `just check-harness` |
| Markdown, including a rule under `.claude/rules/` | `just lint` (its `typos` spell-check) |
| `.github/labels.yml`, or an issue form under `.github/ISSUE_TEMPLATE/` | `just lint` (its `typos` spell-check), then `just check-harness` (every applied label declared, once); `scripts/tests/sync-labels_test.sh` for `scripts/sync-labels.sh` itself |
| `KeychainSecureStore`, or anything else that stores a Keychain item | `just test` for the fake's `SecureStoringContract` run and the adapter's status mapping, write sequence, and query dictionaries; then `just run` with the adapter called from `App/` — no gate stores a Keychain item, because the Keychain answers `errSecMissingEntitlement` to a test runner with no app around it, on the host and under `just test-ios` alike, so the PR carries the log evidence (`persisting-data`'s `references/secure-storage.md`) |
| `.github/rulesets/main.json`, or `scripts/apply-ruleset.sh` | `scripts/tests/apply-ruleset_test.sh`; `just check-harness` for `main.json` (`scripts/checks/ruleset-contexts.sh` reads it) |

## Architecture

```
Config/                     # Debug.xcconfig and Release.xcconfig: per-configuration
                            #   build settings (API_BASE_URL). Debug alone optionally
                            #   includes the gitignored Local.xcconfig holding
                            #   DEVELOPMENT_TEAM (`just run-device`)
App/                        # Thin shell: @main entry point + resources, NO logic.
                            #   The composition root: opens the SwiftData adapter and
                            #   hands it, as a port, to Core's AppModel; reads
                            #   Info.plist once into Core's AppConfiguration
Packages/MyAppKit/
├── Sources/MyAppCore/      # Domain values, view models, ports (protocols), wording,
│                           #   logging — no UI, persistence, or OS-integration import
│                           #   (enforced by lint and test); coverage-gated
├── Sources/MyAppUI/        # SwiftUI views — thin, render Core view models; shared
│                           #   presentation values in `DesignSystem/DesignTokens.swift`
├── Sources/MyAppPlatform/  # Adapters behind Core ports (SwiftData, URLSession, UserDefaults,
│                           #   the Keychain) — translation only, no domain logic, outside
│                           #   the coverage floor
├── Tests/MyAppTestSupport/ # Each port's fake and contract function — test code no
│                           #   shipped module imports (enforced by test)
├── Tests/MyAppCoreTests/   # Swift Testing suites — coverage-gated
└── Tests/MyAppPlatformTests/  # Adapters against the real framework, on the host
LaunchUITests/              # XCUITest on the iOS Simulator (XCTest by necessity)
```

- New logic goes in `MyAppCore` with tests; views only render Core state.
- The dependency direction is one-way: Core ← UI and Core ← Platform, both ← App.
  `MyAppUI` and `MyAppPlatform` are siblings and never import each other.
- Storage and OS services go in `MyAppPlatform` as an adapter behind a `Sendable` port
  Core declares, with one fake and one contract function in `Tests/MyAppTestSupport`:
  `TodoRepository`/`SwiftDataTodoRepository`, `HTTPClient`/`URLSessionHTTPClient`,
  `PreferencesStoring`/`UserDefaultsPreferences`, and `SecureStoring`/`KeychainSecureStore`
  are the worked examples. A secret (a token, a key) goes through `SecureStoring`, never
  a preference: `UserDefaults` is unencrypted and backed up in plain text.
- A value that differs per build configuration (the API base URL: staging in Debug,
  production in Release) is a build setting in `Config/<Configuration>.xcconfig`,
  expanded by `project.yml`'s `info.properties` into `Info.plist` under one key, which
  `App/` reads once and Core's `AppConfiguration` parses; the steps are
  `.claude/rules/project.md` › Per-configuration values. Never a secret: both files are
  committed, and `Info.plist` ships readable in every copy of the app — a secret goes
  through `SecureStoring`.
- `MyAppCore` never imports SwiftUI, UIKit, AppKit, Cocoa, SwiftData, CoreData, CloudKit,
  UserNotifications, CoreLocation, Photos, PhotosUI, StoreKit, WidgetKit, or Security —
  in any spelling. Enforced twice: `.swiftlint.yml`'s `no_ui_import_in_core` and
  `ArchitectureBoundaryTests`; their module lists change together. Foundation re-exports
  the four `SecItem` calls (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`,
  `SecItemDelete`), so `ArchitectureBoundaryTests` also scans Core for those four names —
  and only those: no check looks for any other Security function, type, or constant.
- The package also builds for macOS so `swift test` runs it on the host in seconds — the
  only way `scripts/coverage.sh` reads coverage — so every target compiles for macOS too
  (`.claude/rules/swift.md`); the app itself is iOS-only. Shipped code logs through
  `AppLog`, never `print`.
- A new feature is, in order: domain values, a port only for storage or an OS service
  (with its fake and contract), a view model (`AppModel` builds it), the adapter, the
  view, an `AppRoute` case (or, for a sheet, an `AppSheet` case) with its branch in
  `RootView`, and `App/` wiring only for a new port. A new remote API is `Endpoint`
  values sent through `APIClient`, never a new port; a new stored model is a new schema
  version, never an edit to a shipped one.
- `MyApp.xcodeproj` is generated — edit `project.yml` instead.
- **App shape:** iPhone and iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), multiple windows on
  iPad, no capability or entitlement, no permission prompt or usage-description key, and
  one required-reason declaration in `App/PrivacyInfo.xcprivacy`: `UserDefaults`, reason
  `CA92.1`, which `UserDefaultsPreferences` needs to keep settings such as Hide Completed
  (no tracking, no collected data; `PrivacyManifestTests`, with `RequiredReasonAPITests`
  holding every required-reason API the code calls to a declared entry). An app rewrites
  this line when it decides its device family, capabilities, and permissions
  (`starting-an-app`, `integrating-system-apis`), naming the feature that forces each.

### What is contract and what is private

Contract is what something outside a change can observe: another module, a user's device
that ran an earlier build, or the user. Everything else is private: `internal`
declarations, how an adapter talks to its framework, view structure, file and type
layout, test helpers, log messages.

| Contract | What depends on it | What changing it requires |
|---|---|---|
| **Core's public API** | `MyAppUI`, `MyAppPlatform`, `App/`, the tests | Update every caller in the same pull request; a new public declaration carries a `///` saying why; a new port is a design change ("Before changing the architecture") |
| **The bundle identifier** (`PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`) | The app's data container and Keychain items on every device, App Store Connect, push and other capabilities, `AppLog.subsystem`, `just run`/`just logs` | Fixed once a build has left your machine: a new identifier is a new app, and the user's data stays behind. `project.yml` and `AppLog.subsystem` change together (`AppLogTests`) |
| **The stored schema** (`AppSchemaV1` and its successors) | Every store already on a user's device | A new `VersionedSchema` plus an `AppMigrationPlan` stage, with a test that opens a store written by the previous version (`StoreFiles`). Never edit a shipped schema version: `SchemaMigrationTests` pins each one's entities and attributes, and the plan's order (`persisting-data`) |
| **The URL scheme** (`DeepLink.scheme`, registered in `project.yml`) | Links to the app in messages, notes, and other apps | Fixed once a build has left your machine: a renamed scheme breaks every link in the wild. `project.yml` and `DeepLink.scheme` change together (`DeepLinkTests`); a new link shape is a new `DeepLink` case with its tests, and an old shape keeps parsing |
| **Keychain items** (`SecureKeys` names, under the bundle identifier as the service) | Secrets on a user's device — which survive the app's deletion, so a reinstall finds what an earlier install wrote | Read the old key, write the new one, and delete the old, in Core, with a test that starts from the old key; a renamed key otherwise signs every user out and strands the old secret. Every key is a `SecureKeys` constant, pinned by `SecureKeysTests`. The accessibility (`AfterFirstUnlockThisDeviceOnly`) and the default access group are the design in `persisting-data`; a shared access group is an entitlement |
| **`UserDefaults` keys and file formats** | Saved preferences and files on a user's device | Read the old key or format and migrate it in Core, with a test that starts from the old value. Every key is a `PreferenceKeys` constant, pinned by `PreferenceKeysTests` |

## Before changing the architecture

The design is recorded once per subject, as it stands now, never as a log of decisions:
in the rule or skill that owns it, this file's Architecture section (layer rules, app
shape, contract), and its Product section (scope); git history holds what it used to be.
The changes below, design changes, are hard to reverse, so the pull request that makes
one also rewrites that description — the current design and its reasoning (what it
protects and, where it matters, the alternative it rules out), in the present tense, in
place of the sentences it replaces, never as a dated entry beside them:

- a new target (`project.yml`, `Package.swift`) or a new Core port;
- the device family and scene model — iPhone only or iPhone and iPad
  (`TARGETED_DEVICE_FAMILY`), and multiple windows (`UIApplicationSupportsMultipleScenes`);
- a capability or entitlement — Push Notifications, iCloud/CloudKit, App Groups,
  Background Modes, Associated Domains, Sign in with Apple, HealthKit, or any other;
- persistence — where and in what format state is kept: the SwiftData schema and
  migration plan, CloudKit sync, `UserDefaults` keys, Keychain items and their
  accessibility, files;
- a new dependency;
- distribution — App Store, TestFlight (internal or external), or another channel;
- `deploymentTarget` in `project.yml`, with `platforms:` in `Package.swift`;
- a privacy-gated permission — an `Info.plist` usage-description key (camera, photo
  library, location, contacts, microphone, notifications authorization, App Tracking
  Transparency) — or a required-reason API declared in `PrivacyInfo.xcprivacy`;
- a shipped language beyond English.

Writing the reasoning down grants nothing: an entitlement, a signing change, or a new
dependency still needs the sign-off "Security and human approval" asks for, and the
owner reviews the rewritten description with the change. The starting choices' reasons
live in `designing-core-logic` (layers), `persisting-data`, and `changing-gates`
(toolchain); replacing one rewrites that reason too.

## Skills

Each skill under `.claude/skills/` owns one kind of change; load the one whose
description matches the task. Skills are edited there directly. Which gate holds what,
and what none of them sees, is `changing-gates`.

### Rules

Each file under `.claude/rules/` loads once a file matching its `paths:` is opened,
which is after a design is under way, so read the rule for each area a change touches
before designing it: `core.md` (MyAppCore), `ui.md` (MyAppUI, `App/`, LaunchUITests),
`platform.md` (MyAppPlatform and its tests), `swift.md`, `testing.md`, `shell.md`
(`scripts/`, `.githooks/`: how a repository script is written and tested), `project.md`
(project, package, and toolchain config), and `docs.md`.

### Sub-agents

`.claude/agents/` defines the `subagent_type` tiers (`executor`, `architect`, `scout`,
`worker`), generated outside this repository from the owner's canonical tier
definitions; never edit them by hand. Delegate by naming a tier as `subagent_type`,
never with a bare `model`: each tier file carries its model, effort, and instructions,
and a bare `model` drops them. Pick the tier by its `description`. Most work needs no
delegation, and a decision that needs this conversation stays with the main session.

## Security and human approval

Only what is mechanically decidable is blocked at commit time: the pre-commit hook's
staged guard (`scripts/check-staged.sh`, rules in `scripts/guard/`) refuses a
secret-shaped path or credential-shaped content. Whether a commit *should* contain what
it contains stays in PR review.

Never read a secret-shaped file, even to check it: `.env`, `.env.*`, or `.envrc.*` (the
`.example`/`.sample`/`.template` samples excepted), anything under a `secrets/` directory,
`*.p12`, `*.pfx`, `*.p8`, `*.provisionprofile`, `*.mobileprovision`,
`*.keychain`/`*.keychain-db`, `*key*.pem`, `private-key.*`, `.netrc`, `credentials.json`,
`secrets.json`, `GoogleService-Info.plist`, and `Config/Local.xcconfig` — the list
`scripts/guard/paths.sh` refuses to commit (it also refuses `.claude/settings.local.json`,
which is fine to read). If a task seems to need one, ask the human for the non-secret
fact instead.

Get a human's sign-off before acting on any of these:

- Touching an entitlements file, a signing identity or team, a provisioning profile, or
  any App Store Connect, signing, or release secret.
- Creating or pushing a release tag, or uploading a build to TestFlight or the App Store.
- Adding a new package dependency.
- Weakening any gate: lowering the coverage floor, disabling or relaxing a SwiftLint
  rule, widening a workflow's `permissions:`. That includes, when used to make a failing
  check pass: `// swiftlint:disable` (any form) or `// swiftformat:disable`, an added
  exclude path, `@unchecked Sendable` or `nonisolated(unsafe)` to silence a concurrency
  diagnostic, `.disabled(…)` or `withKnownIssue` on a failing test, excluding code from
  coverage, deleting or loosening an assertion, `continue-on-error`, or
  `git commit --no-verify`.
- Working around a denied command. Re-spelling it (`git -C . …`, `bash -c '…'`, bundled
  short flags, an alias or wrapper) is forbidden. Stop and ask.
- Any write to a remote: `git push`, `gh pr create`, `gh issue create`, a label change,
  a merge. That includes the first run against the live repository of `just labels`
  (it only creates or updates the labels `.github/labels.yml` declares, never deletes)
  and `just ruleset` (it only creates or updates the "main" ruleset, and needs admin).

Standing exceptions: invoking one of these skills is the sign-off for the remote writes
that skill exists to make, for that invocation only.

- `smart-commit`, when asked to push: pushing the commits it made to the current branch.
- `create-pr`: pushing the current branch and creating or updating its pull request.
- `shipping-issues`: the writes its `SKILL.md` lists — priority and `blocked:` labels on
  open issues, branches and pushes, the pull request, merging it once CI passes, the
  follow-up issues and comments it files, and removing the branches and worktrees it
  created.

None of them covers anything else in the list above. A skill that reaches one of those
stops and asks.

## Review Checklist

Before submitting a PR:

1. `just check` passes (it runs `just uitest`, `just smoke`, `just build-device`, and `just test-ios` when the change
   touches a simulator path; `CHECK_ALL=1 just check` forces them)
2. New public APIs have `///` doc comments explaining *why*
3. Tests cover the new functionality (happy path and error path)
4. No new dependencies without a human's sign-off
5. User-facing changes have a `CHANGELOG.md` entry under `[Unreleased]`
6. Commits and the PR title follow Conventional Commits (English)

## Important Reminders

- All code, docs, commits, issues, and PRs are written in English. The one exception
  is a translated value in a `*.xcstrings` String Catalog.
- Do what has been asked; nothing more, nothing less.
- Prefer editing an existing file to creating a new one; never create documentation
  files unless asked.
- Never lower the coverage floor or disable safety lint rules to make a check pass.
- A comment carries only what the code cannot: a non-obvious why, a trap the next edit
  would spring, an external constraint. A `///` on public API is its contract and stays.
- A problem you find outside the task is recorded, not fixed: file it as an issue
  (`triaging-issues`) or, where filing is not yours to do, list it in the pull request
  description. Never widen the pull request to fix it.
