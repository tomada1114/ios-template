# Project Guide

This file holds what every agent needs before it knows which task it is on: what the
app is, how to check a change, where code goes, and which decisions need a human. It is
the one guide Claude Code and Codex CLI share. The reasoning behind the architecture is
in [`docs/architecture.md`](docs/architecture.md); the conventions of one kind of change
belong to a skill under `.agents/skills/` ([Skills](#skills)); a value a gate enforces
belongs to its config (`.swiftlint.yml`, `.swiftformat`, `Package.swift`,
`scripts/coverage.sh`, `mise.toml`), and running the gate is how you learn it.

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
- **Where these decisions are recorded** — TODO: where the reasoning behind the three
  entries above lives.

## Quick Reference

```bash
just install       # Install pinned tools (mise), git hooks, and generate the Xcode project
just generate      # Regenerate MyApp.xcodeproj from project.yml
just fmt           # Format code (swiftformat)
just fix           # Format, auto-fix SwiftLint violations, then run just lint
just lint          # Lint (scripts/lint.sh: swiftformat --lint + swiftlint --strict + shellcheck + actionlint + typos + skills mirror)
just verify-hooks  # Verify the git hooks are installed and executable (scripts/verify-hooks.sh)
just test          # Run the package tests on the host Mac with the 80% line / 75% function floors on MyAppCore
just test-fast TodoItemTests  # Run only the matching tests, no coverage floor (iteration only)
just test-scripts  # Run the plain-bash tests for scripts/ and the skills' Python suites (scripts/tests/run.sh)
just check-harness # Re-assert the harness's claims about itself (scripts/checks/run-all.sh)
just build         # Build the app (Debug) for the iOS Simulator
just run           # Build, then install and launch it on an iOS Simulator (SIMULATOR_DEVICE picks one)
just run-device    # Build (Debug), then install and launch it on a connected iPhone (Config/Local.xcconfig; IOS_DEVICE picks one)
just logs          # Stream this app's log output from the booted simulator (Ctrl-C to stop)
just reset-permissions  # Make the booted simulator forget this app's privacy grants
just uitest        # Run the XCUITest launch test on an iOS Simulator (uitest-build, then uitest-run)
just uitest-build  # Build the app and the launch UI test for an iOS Simulator, without running it
just uitest-run    # Run the launch UI test uitest-build compiled, without rebuilding
just test-ios      # Run the package tests on an iOS Simulator (no coverage floor)
just smoke         # Build Release and assert the app launches and stays alive on a simulator
just check         # Run all checks: verify-hooks → fmt → lint → test-scripts → check-harness → test → build
just agents-sync   # Regenerate the .claude/skills/ mirror from .agents/skills/
just agents-check  # Fail if .claude/skills/ differs from .agents/skills/
just clean         # Remove build artifacts and the generated project
just labels        # Create/update GitHub labels from .github/labels.yml (never deletes)
just ruleset       # Create/update the "main" branch ruleset from .github/rulesets/main.json (admin-only)
```

Without Just: run the underlying commands listed in each `justfile` recipe (see
CONTRIBUTING.md).

Building the app needs Xcode (`.xcode-version`) **with its iOS platform installed**
(Xcode › Settings › Components); `just test` needs only the Swift toolchain.

## Validating a change

Run the narrowest check that can fail, then `just check` before you open a PR.

| What you changed | The narrowest check that can fail |
|---|---|
| A Swift file under `Packages/MyAppKit/Sources/MyAppCore/` | `just test` |
| A test under `Packages/MyAppKit/Tests/` | `just test` |
| An adapter under `Packages/MyAppKit/Sources/MyAppPlatform/` | `just test` (its contract runs against the real framework on the host); `just build` if `App/` wires it |
| A fake or a port contract under `Packages/MyAppKit/Tests/MyAppTestSupport/` | `just test` (the contract runs against both the fake and the adapter) |
| A view under `Packages/MyAppKit/Sources/MyAppUI/`, or anything under `App/` | `just build`; `just uitest` if it changes what the launch test touches |
| How a screen looks (`DesignTokens`, colors, type, the design lock) | `just build`, then screenshots per `designing-ui`'s review pass (light, dark, largest Dynamic Type, Increase Contrast) |
| Formatting or style of any Swift file | `just lint` (`just fix` for what is auto-fixable) |
| One Core suite, while iterating | `just test-fast <filter>` — no coverage floor, so finish with `just test` |
| A `PreferenceKeys` name | `just test` (`PreferenceKeysTests` pins every stored name and default; a rename is a migration, not an edit to that test) |
| `Localizable.xcstrings`, or a `LocalizedStringResource` in Core | `just test` (`LocalizationTests` scans Core's `LocalizedStringResource(…)` calls and holds their keys and English to the catalog); `just build` to compile the catalog into the app |
| `project.yml` | `just generate && just build` |
| A route, a deep link, or the URL scheme | `just test` (`DeepLinkTests` holds Core's scheme to `project.yml`); `just uitest` |
| A test under `LaunchUITests/`, or launch behavior | `just uitest` |
| Code behind `#if os(iOS)` in `MyAppKit`, or behavior that differs on the iOS runtime | `just test-ios` |
| The Release configuration, or anything only a Release launch shows | `just smoke` |
| Behavior only the running app shows | `just run`, then `just logs` — no gate asserts it, so the PR carries the evidence (a screenshot: `xcrun simctl io booted screenshot shot.png`; the `running-the-app` skill) |
| `Config/Debug.xcconfig` | `just generate && just build`; `just run-device` on a connected phone (owner-run) |
| `scripts/run-device.sh` | `just lint`, then `just test-scripts` (`scripts/tests/run-device_test.sh`); `just run-device` on a connected phone (owner-run) |
| A permission prompt, or behavior after a grant is revoked | `just reset-permissions`, then `just run` |
| A shell script under `scripts/` (including the sourced `scripts/guard/*.sh`), or `.githooks/pre-commit` | `just lint`, then `just test-scripts` |
| `scripts/verify-hooks.sh` | `just lint`, then `just test-scripts`; `just verify-hooks` for the check itself |
| A harness check under `scripts/checks/` (including the sourced `scripts/checks/lib.sh`) | `just lint`, then `just test-scripts`; `just check-harness` for the checks themselves |
| A `just` recipe name, a workflow's `uses:`, `permissions:`, `concurrency:`, or `run:` shell, a Dependabot or Renovate commit prefix or cooldown, a skill's frontmatter, the Skills table, the `## Product` section, `.claude/settings.json`'s `permissions` rules, the Core import ban list (`.swiftlint.yml`'s `no_ui_import_in_core` or `ArchitectureBoundaryTests.forbiddenModules`), the gates `just check` or `ci.yml` runs, `.github/rulesets/main.json`'s required contexts, or a label an issue form, a workflow, a dependency bot, or `scripts/label-pr.sh` applies | `just check-harness` |
| A skill under `.agents/skills/` | `just agents-sync`, then `just agents-check` and `just check-harness`; `just test-scripts` when the skill ships scripts (it runs their `scripts/tests/` unittest suite) |
| A workflow under `.github/workflows/` | `just lint` (actionlint), then `just check-harness` |
| Markdown | `just lint` (its `typos` spell-check) |
| `docs/architecture/` (an ADR, the index, the roadmap) | `just lint` (its `typos` spell-check) |
| `mise.toml` | `mise install`, then `just check` |
| `.github/labels.yml`, or an issue form under `.github/ISSUE_TEMPLATE/` | `just lint` (its `typos` spell-check), then `just check-harness` (every applied label declared, once); `scripts/tests/sync-labels_test.sh` for `scripts/sync-labels.sh` itself |
| `.github/rulesets/main.json`, or `scripts/apply-ruleset.sh` | `scripts/tests/apply-ruleset_test.sh`; `just check-harness` for `main.json` (`scripts/checks/ruleset-contexts.sh` reads it) |

## Architecture

```
Config/                     # Debug.xcconfig; optionally includes the gitignored
                            #   Local.xcconfig holding DEVELOPMENT_TEAM (`just run-device`)
App/                        # Thin shell: @main entry point + resources, NO logic.
                            #   The composition root: opens the SwiftData adapter and
                            #   hands it, as a port, to Core's AppModel
Packages/MyAppKit/
├── Sources/MyAppCore/      # Domain values, view models, ports (protocols), wording,
│                           #   logging — no UI, persistence, or OS-integration import
│                           #   (enforced by lint and test); coverage-gated
├── Sources/MyAppUI/        # SwiftUI views — thin, render Core view models; shared
│                           #   presentation values in `DesignSystem/DesignTokens.swift`
├── Sources/MyAppPlatform/  # Adapters behind Core ports (SwiftData, URLSession, UserDefaults) — translation
│                           #   only, no domain logic, outside the coverage floor
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
  Core declares, with one fake and one contract function in `Tests/MyAppTestSupport`.
  The worked example is `TodoRepository` / `SwiftDataTodoRepository`; networking
  included: `HTTPClient` / `URLSessionHTTPClient`; preferences included:
  `PreferencesStoring` / `UserDefaultsPreferences`.
- `MyAppCore` never imports SwiftUI, UIKit, AppKit, Cocoa, SwiftData, CoreData, CloudKit,
  UserNotifications, CoreLocation, Photos, PhotosUI, StoreKit, or WidgetKit — in any
  spelling. Enforced twice: `.swiftlint.yml`'s `no_ui_import_in_core` and
  `ArchitectureBoundaryTests`; their module lists change together.
- The package also builds for macOS so `swift test` runs on the host; an iOS-only API in
  `MyAppUI` or `MyAppPlatform` goes behind `#if os(iOS)`.
- Shipped code logs through `AppLog` (`os.Logger`); `print`, `debugPrint`, and `NSLog`
  are rejected under `Packages/*/Sources/` and `App/` by `no_print_in_sources`.
- `MyApp.xcodeproj` is generated — edit `project.yml` instead.
- Four things are contract — Core's public API, the bundle identifier, the stored
  SwiftData schema, and `UserDefaults` keys/file formats — and each changes only as
  `docs/architecture.md` › What is contract says.

## Before changing the architecture

An app cut from this template records its architecture decisions as ADRs under
`docs/architecture/` — start at its `README.md`, the index, whose statuses say what is
decided and what is only proposed. `docs/architecture.md` describes the layers every app
starts with; the ADRs record what the app decided on top of them. A change to any of
these owes an ADR, as `recording-architecture-decisions` sets out:

- a new target (`project.yml`, `Package.swift`) or a new Core port;
- the device family and scene model — iPhone only or iPhone and iPad
  (`TARGETED_DEVICE_FAMILY`), and multiple windows (`UIApplicationSupportsMultipleScenes`);
- a capability or entitlement — Push Notifications, iCloud/CloudKit, App Groups,
  Background Modes, Associated Domains, Sign in with Apple, HealthKit, or any other;
- persistence — where and in what format state is kept: the SwiftData schema and its
  migration plan (`VersionedSchema`/`SchemaMigrationPlan`), CloudKit sync, `UserDefaults`
  keys, files;
- a new dependency;
- distribution — App Store, TestFlight (internal or external), or another channel;
- `deploymentTarget` in `project.yml`, with `platforms:` in `Package.swift`;
- a privacy-gated permission — an `Info.plist` usage-description key (camera, photo
  library, location, contacts, microphone, notifications authorization, App Tracking
  Transparency) — or a required-reason API declared in `PrivacyInfo.xcprivacy`;
- a shipped language beyond English.

An agent writes an ADR as Proposed; only a human accepts it. An ADR records reasoning and
grants nothing: an entitlement, a signing change, or a new dependency still needs the
sign-off "Security and human approval" asks for. The template repository ships the index
empty — its own reasoning lives in `docs/architecture.md`'s "Decisions at a glance", and
ADRs belong to the apps cut from it.

## Skills

Each skill owns one kind of change. Load the one whose subject you are working on.

Skills are authored under `.agents/skills/` — the path Codex CLI reads — and mirrored
into `.claude/skills/`, the only path Claude Code reads:

- Edit a skill only under `.agents/skills/`, then run `just agents-sync` and commit both
  trees together. Never hand-edit `.claude/skills/`; `just agents-check` (also part of
  `just lint` and the pre-commit hook) reports any drift.
- The mirror is a real, byte-identical copy, never a symlink: Codex follows a linked
  directory and registers a nested `references/SKILL.md` as a skill of its own.

| Skill | Load it when you are working on |
|---|---|
| `shipping-issues` | shipping the open issue backlog: ranking issues by `priority: P0`-`P3`, implementing the top one, reviewing it with `/code-review`, and taking its PR through CI to merge |
| `triaging-issues` | filing or triaging an issue: the labels in `.github/labels.yml`, priority tiers, the `Depends on #N` convention, and what an issue body must contain |
| `tdd` | a behavior change in `MyAppCore`: writing a failing Swift Testing test before the implementation |
| `create-pr` | opening or updating a pull request: the `just check` pre-check, title, template, and checklist |
| `smart-commit` | committing and pushing changes: grouping them into Conventional Commits, excluding sensitive files |
| `changing-gates` | a file that enforces rather than implements: `.swiftlint.yml`, `.swiftformat`, `Package.swift`'s `strictSettings`, `mise.toml`, `.githooks/pre-commit`, `scripts/lint.sh`, `scripts/coverage.sh`, the `scripts/guard/` commit-time guard, a `scripts/checks/` harness check, or a workflow — and which gate would catch a change |
| `merging-dependency-prs` | landing open Dependabot (SwiftPM, GitHub Actions) and Renovate (`mise.toml`, gitleaks) PRs: the security checklist, holding a bump that raises a package's `platforms:` floor, `just test-ios` and `just uitest` after a SwiftPM bump, one human approval for a listed batch of passing PRs, and a combined branch for conflicting bumps |
| `authoring-skills` | adding, editing, or reviewing a skill: authoring under `.agents/skills/`, the `just agents-sync` mirror, frontmatter, layout, and size limits |
| `writing-repo-scripts` | writing or testing a shell script under `scripts/`, `.githooks/pre-commit`, or `scripts/tests/`: why bash, refusing or skipping outside a git checkout, the stderr contract by example, and `scripts/tests/lib.sh` |
| `designing-errors` | an `Error` type, a `throws`/`throws(E)` signature, a `do`/`catch`, or cancellation: Core error enums, typed throws, no user data in errors or logs, `CancellationError`, and mapping a SwiftData or Foundation (`NSError`/`CocoaError`) error in an adapter |
| `designing-core-logic` | shaping logic in `MyAppCore`: injecting time (`Clock`, a `() -> Date`), identifiers, `Locale`, and a `RandomNumberGenerator`; one `Tuning` type for tunables; action-shaped `@Observable` view models; and the patterns deliberately not adopted |
| `recording-architecture-decisions` | the ADRs under `docs/architecture/`: whether a change owes an ADR (a target or port, the device family and scene model, a capability or entitlement, persistence, a dependency, distribution, `deploymentTarget`, a privacy-gated permission, a shipped language), an ADR's statuses, amending versus superseding, and fact discipline — every external claim with a URL and a checked date |
| `steering-the-roadmap` | the app's direction in `docs/architecture/roadmap.md`: its Now / Next / Later horizons, who changes it and when, how the backlog and parked `on hold` issues feed it, and answering "what is next?" before `shipping-issues` |
| `starting-an-app` | turning this template into a new app: `scripts/bootstrap.sh`'s rename, the template-only passages it removes, what the new repository keeps, its `just labels` and `just ruleset` setup, choosing the device family (iPhone only or iPhone and iPad), and deciding which capabilities and entitlements it takes |
| `running-the-app` | seeing a change work on the iOS Simulator: `just run` and confirming the installed app is the fresh build, reading `just logs`, `simctl` screenshots in dark mode and at large Dynamic Type sizes, deep links, simulated pushes, launch arguments, a throwaway XCUITest, `just reset-permissions`, and the evidence a PR then carries |
| `integrating-system-apis` | reaching an iOS system API through a Core port: the adapter in `MyAppPlatform`, a permission as a Core enum, usage descriptions and `Info.plist` keys in `project.yml`, `PrivacyInfo.xcprivacy`, notifications, PhotosPicker, background tasks, `simctl privacy`, `#if os(iOS)`, and what `just test`, `just test-ios`, and a device each prove |
| `designing-ui` | how a screen looks: HIG craft rules, `DesignTokens`, Liquid Glass with an iOS 27 floor, and the app's design lock ADR, researched with `/refero-design` |
| `building-swiftui-screens` | a view in `MyAppUI`: a thin renderer over a `MyAppCore` `@Observable` view model, navigation, sheets and alerts, size classes, Dynamic Type, safe areas and the keyboard, touch targets, `#Preview` per state, accessibility identifiers and labels, and verifying a screen |
| `updating-docs` | deciding whether a change owes a documentation update and which surface it lands on: `README.md`, `AGENTS.md`, `CHANGELOG.md`, `docs/architecture.md`, `docs/architecture/`, a skill, or a `///` comment |
| `localizing-the-app` | a string a person reads: the String Catalog `Localizable.xcstrings` in `MyAppCore`, `defaultLocalization`, Core returning `LocalizedStringResource` (`bundle: .module`), `Text(verbatim:)` in `MyAppUI`, keeping the catalog and `LocalizationTests` in step, `xcodebuild -exportLocalizations`, plurals, `InfoPlist.xcstrings`, and what adding a language involves |

### Rules

The files under `.claude/rules/` load by path: each applies while you touch a file
matching its `paths:` globs.

| Rule | Loads when you touch |
|---|---|
| `.claude/rules/project.md` | `project.yml`, `Packages/**/Package.swift`, `Packages/**/Package.resolved`, `mise.toml`, `.swiftlint.yml`, `.swiftformat`, `scripts/coverage.sh` |
| `.claude/rules/docs.md` | `docs/**/*.md`, `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md` |
| `.claude/rules/swift.md` | `Packages/**/*.swift`, `App/**/*.swift` |
| `.claude/rules/testing.md` | `Packages/**/Tests/**`, `LaunchUITests/**` |

### Sub-agents

`.claude/agents/` defines four named sub-agent tiers a skill or session hands a step to
by name (`subagent_type: executor`): `executor` (settled spec, clear pass/fail),
`architect` (design judgment, review, complex multi-file work), `scout` (read-only,
judgment-free research, collection, or enumeration that changes no files), `worker`
(single-shot, tool-free writing or checking). The tier files are generated by the
`syncing-agent-tiers` skill; do not edit them by hand. Codex
CLI reads nothing under `.claude/agents/`; there, a delegated step runs inline.

## Security and human approval

Only what is mechanically decidable is blocked at commit time; whether a commit
*should* contain what it contains stays in PR review. See `scripts/guard/` for exactly
what is checked: the pre-commit hook's "Staged guard" section (`scripts/check-staged.sh`)
refuses a secret-shaped staged path or credential-shaped staged content.

Never read a secret-shaped file, even to check it: `.env`, `.env.*`, or `.envrc.*`
(the `.example`/`.sample`/`.template` samples excepted), anything under a `secrets/`
directory, `*.p12`, `*.pfx`, `*.p8`, `*.provisionprofile`,
`*.mobileprovision`, `*.keychain`/`*.keychain-db`, `*key*.pem`, `private-key.*`,
`.netrc`, `credentials.json`, `secrets.json`, `GoogleService-Info.plist`, and
`Config/Local.xcconfig`. This is the same list `scripts/guard/paths.sh` refuses to
commit, so the read rule and the commit guard agree (the guard also refuses
`.claude/settings.local.json`, which is per-user settings rather than a secret, so
reading it is fine and only committing it is not); if a task seems to need one, ask the
human for the non-secret fact instead.

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
  a merge. `scripts/sync-labels.sh` (`just labels`) is a script this repository ships
  for labels: it only ever creates or updates a label `.github/labels.yml` declares,
  via `gh label create --force`, and never deletes one — but running it against the
  live repository still needs sign-off before its first run there, the same as any
  other remote write. `scripts/apply-ruleset.sh` (`just ruleset`) is the same kind of
  script for branch protection: it only ever creates or updates the ruleset named
  "main" from `.github/rulesets/main.json`, needs repository admin permissions to
  succeed, and still needs sign-off before its first run against the live repository.

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

### What no local gate sees

Every local layer can be skipped, so these reach `main` only if CI or GitHub stops them
(see "Enforcement layers" for the gaps each one leaves):

- `git commit --no-verify`, a clone where `just install` never ran, or a commit made
  outside this checkout's hooks — the pre-commit hook and staged guard never run.
- An edit made through GitHub's web UI or API, which touches no local hook.
- A secret inside a file whose path and content pattern the guard does not know.
- Any tool other than Claude Code: a Claude Code permission list binds nothing else.

### GitHub settings a new repository must enable

"Use this template" copies files, not settings, so a repository's admin turns these on
once under Settings › Advanced Security (Code security on older UIs):

- **Secret scanning** and **Push protection** — the server-side layer for secrets that
  the staged guard misses or a bypass skips; push protection blocks a detected secret
  at `git push`.
- **Private vulnerability reporting** — `SECURITY.md` sends reporters to a private
  security advisory, which this setting enables.
- **Dependabot alerts** — `.github/dependabot.yml` configures version updates; alerts
  for known-vulnerable dependencies are a separate switch.
- The `main` ruleset, applied by `just ruleset`. `.github/rulesets/main.json`
  deliberately lists no `bypass_actors`: a bypass lets an admin, or an agent acting
  with an admin's token, merge without the PR and green checks the ruleset exists to
  require, and an emergency change can still go through a PR.

## Repository scripts

Every script under `scripts/` follows these rules, whoever writes it
(`scripts/tests/lib.sh`, `scripts/checks/lib.sh`, and the `scripts/guard/*.sh`
libraries are sourced, so they carry no shebang or `set` line of their own):

- `#!/usr/bin/env bash` and `set -euo pipefail`, and bash 3.2-compatible (macOS
  `/bin/bash`): no associative arrays, no `mapfile`/`readarray`, no `${var,,}`, and no
  `"${arr[@]}"` on a possibly empty array under `set -u` (use `${arr[@]+"${arr[@]}"}`).
  Under `pipefail`, never pipe into a reader that exits early (`grep -q`, `head`): feed
  it a here-string, `grep -qxF -- "${x}" <<<"${list}"`.
- `shellcheck`-clean — `scripts/lint.sh` checks every tracked `*.sh`
  outside the generated `.claude/skills/` mirror.
- Pinned tools are called by bare name; the caller provides PATH (`mise exec -- …`
  locally and in `just` recipes, `jdx/mise-action` in CI). Beyond that, assume only
  `git` and POSIX utilities, and no GNU- or BSD-only flag (`sed -i`, `readlink -f`,
  `mktemp -t`) — the scripts run on macOS and on CI's Ubuntu. The simulator scripts
  also need Xcode's `xcrun` and `python3`, as their headers say.
- Failure contract: the first stderr line is `ERR_<STAGE>_<WHAT>: <what failed>`, then
  `Expected:`, `Actual:`, and `Next:` lines (the next safe command); exit 1. List the
  codes in the script's header comment. Never print a secret value. The one exit-code
  exception is `scripts/format-edited-file.sh`, which exits 2: Claude Code feeds a
  `PostToolUse` hook's stderr back to the agent only on exit 2.
- Never assume the checkout is the only repository on the machine. A script that
  enumerates or rewrites tracked files refuses to run outside a git work tree (the
  `scripts/lint.sh` pattern, `ERR_LINT_NOT_A_REPO`); a check that is meaningless
  outside one skips with a one-line notice instead. Each script's header states which
  it does.
- Every script directly under `scripts/` has a test file `scripts/tests/<script-name>_test.sh`
  built on `scripts/tests/lib.sh`, and `scripts/tests/run.sh` (`just test-scripts`,
  part of `just check` and CI's lint job) runs them all — concurrently, so a test file
  must share no state with any other: its own throwaway repository or temp directory,
  its own stubs, and only read-only use of the checkout. The runner itself is covered
  by `scripts/tests/run_test.sh`. A test works in a throwaway repository or temp
  directory, never the real checkout, and fakes external commands with
  `stub_command` — a simulator test stubs `xcrun` in every case, since CI's lint job
  runs on Ubuntu, where there is none. A sourced library under `scripts/guard/` gets
  its own test file too, `scripts/tests/guard-<library>_test.sh`
  (`guard-paths_test.sh`, `guard-credentials_test.sh`). The harness checks under
  `scripts/checks/`, their runner `run-all.sh`, and their sourced `lib.sh` share one
  test file, `scripts/tests/checks_test.sh`, which builds a fixture tree per failure
  mode and points each check at it with `--root`. Known exceptions, each with its
  reason: `bootstrap.sh`, which has no test file — it is exercised end to end by CI's
  `bootstrap-smoke` job, which renames a clone of the template with it; and
  `coverage.sh`, whose test file `scripts/tests/coverage_test.sh` is partial — it stubs
  `swift` to cover its rejection of the removed environment override and its line- and
  function-floor comparisons, but not a real coverage run, which is CI's `test` job.
  `coverage.sh`'s below-the-line-floor failure also predates the failure contract and
  does not follow it yet (its function-floor failure,
  `ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR`, does).

## Enforcement layers

| Layer | Fires on | Holds |
|---|---|---|
| `.githooks/pre-commit` (installed by `just install`) | `git commit` | `scripts/lint.sh --staged-tree` on the staged Swift files; the skills-mirror check when a staged path is under `.agents/skills/` or `.claude/skills/`; the staged guard (`scripts/check-staged.sh`, rules in `scripts/guard/`) on every commit that stages a change — no secret-shaped path or credential-shaped content lands in a commit, and a staged deletion is never inspected |
| `scripts/verify-hooks.sh` (`just install`'s last step, and `just check`'s first) | `just install`, `just check` | git resolves the hooks directory to `.githooks/` and `.githooks/pre-commit` is executable — skips under CI or the `ALLOW_MISSING_GIT_HOOKS` opt-out |
| `scripts/checks/run-all.sh` (`just check-harness`, part of `just check` before `just test`) | `just check-harness`, `just check`, CI `lint` | the harness's claims about itself stay true — every `just <recipe>` in this file exists and every `Bash(just <recipe>…)` rule in a committed `.claude/settings.json`, if one is added, names a recipe the justfile defines, every workflow has a top-level `permissions:` and every non-local `uses:` (workflows and composite actions) is pinned to a full SHA with a `# v…` comment, no workflow grants a `write` scope or a `read-all`/`write-all` shorthand at the top level (a write goes on the job that needs it, and no job takes a shorthand), every workflow triggered on `pull_request` declares a top-level `concurrency:`, and every declared group varies per run, is unique to its workflow unless it names `github.workflow`, and never cancels in progress on a `push` except through a `github.event_name` expression, every `run:` step (composite actions included) resolves to `shell: bash` (`-eo pipefail`) or opens with a `set` carrying `-e` and `pipefail`, every Dependabot entry's and Renovate's commit prefix is set to a type the PR-title check's `types` accepts and their release cooldowns are set and agree, every skill's frontmatter is exactly a matching `name` and a `description`, no `SKILL.md` sits below a skill's top directory and every skill's `description` is printable ASCII, at most 1,024 characters, and free of unquoted values Codex CLI's YAML parser rejects, the Skills table matches `.agents/skills/`, every required status-check context in `.github/rulesets/main.json` matches a job `name:` (or id) in a workflow triggered on `pull_request`, `.swiftlint.yml`'s `no_ui_import_in_core` regex and `ArchitectureBoundaryTests.forbiddenModules` ban the same modules, the gates `just check` runs and the `run:` steps of `.github/workflows/ci.yml` match in both directions apart from the reasoned exception list in `scripts/checks/just-check-matches-ci.sh`, and every label an issue form, a workflow, a dependency bot (Dependabot's implied `dependencies`, Renovate's `labels`), or `scripts/label-pr.sh`'s type-to-label mapping applies is declared in `.github/labels.yml` and no label is declared there twice, and the `## Product` section above stays a `TODO:` skeleton here while `project.yml` still names the template's app-name placeholder and holds no `TODO:` marker once `scripts/bootstrap.sh` has renamed this into an app |
| `.swiftlint.yml`'s `no_ui_import_in_core` + `ArchitectureBoundaryTests` | the hook, `just lint`, CI `lint`; `just test`, CI `test` | Core's import ban; Core never names `URLSession` or `UserDefaults` (Foundation types no import ban sees); UI and Platform never import each other; no shipped module imports `MyAppTestSupport` |
| `.swiftlint.yml`'s `no_print_in_sources` | the hook, `just lint`, CI `lint` | no `print`/`debugPrint`/`NSLog` in shipped code |
| `scripts/coverage.sh` | `just test`, CI `test` | 80% line / 75% function coverage on `MyAppCore` |
| `AppLogTests` | `just test`, CI `test` | `AppLog.subsystem` equals the bundle identifier in `project.yml` |
| `DeepLinkTests` | `just test`, CI `test` | the scheme Core parses is the one `project.yml` registers |
| `PreferenceKeysTests` | `just test`, CI `test` | stored preference key names and defaults never change silently |
| `LocalizationTests` | `just test`, CI `test` | every `LocalizedStringResource(…)` in Core has a key, a `defaultValue`, and `bundle: .module`; its keys are exactly the catalog's; the catalog's English is what Core renders |
| CI (`.github/workflows/ci.yml`) | push to `main`, every pull request | `lint` (format, lint, shellcheck, actionlint, typos, skills mirror; `scripts/tests/run.sh` — the script tests and the skills' Python suites; the harness checks (`scripts/checks/run-all.sh`)), `test` (package tests + coverage floor), `app` (iOS Simulator build + XCUITest), `smoke` (`Release Smoke Launch (iOS Simulator)`, in parallel with `app`: the Release smoke launch, `just smoke`), `ios-tests` (`Package Tests (iOS Simulator)`: every package test suite on an iOS Simulator, `just test-ios`, no coverage floor), `bootstrap-smoke` (`Template Bootstrap Smoke`: `scripts/bootstrap.sh` renames a clone of the template, which is then linted, tested, and built for the simulator — template-only, so the rename removes it from every app), `changes` (ubuntu: diffs a pull request's files; when none matches the simulator-relevant path list in `ci.yml`, `app`, `smoke`, and `ios-tests` still run and report but skip their steps — a push to `main`, or a failed detection, runs them in full), and the `zizmor` workflow lint (`Workflow Security Lint`) |
| Security workflows (`codeql.yml`, `gitleaks.yml`, `osv-scan.yml`, `dependency-review.yml`, `scorecard.yml`) | every pull request (OSV, dependency review), push to `main` (CodeQL), a pull request that edits `gitleaks.yml`, and weekly schedules (CodeQL, gitleaks, OSV, Scorecard) | CodeQL for the package's Swift, a checksum-verified full-history gitleaks scan, OSV and dependency-review checks of SwiftPM dependencies, OpenSSF Scorecard |
| `.github/workflows/check-pr-title.yml` (job `Validate PR title`) | every pull request (opened, reopened, edited, synchronize) | the PR title is a Conventional Commit whose type is in its `types` list |

`git commit --no-verify` bypasses the hook, and a clone where `just install` never ran
has no hook at all (`scripts/verify-hooks.sh` makes that fail loudly at `just install`
and `just check` time, but a contributor who runs neither still commits without hooks).
CI is the backstop for everything except the staged guard, which no CI job re-runs over
a pull request's diff: a secret committed with `--no-verify` or from a clone without
`just install` reaches the branch unchecked. GitHub push protection and secret scanning
are the server-side layer for secrets, and `.github/workflows/gitleaks.yml` scans the
full git history weekly with a pinned, checksum-verified gitleaks, so a secret that
slipped past both is found after the fact rather than never.

**Whether `main`'s ruleset is actually in force is invisible from the checkout.** The
intended ruleset — PR required, checks green, no force-push or deletion — is defined as
code in `.github/rulesets/main.json`; `just ruleset` (`scripts/apply-ruleset.sh`)
creates or updates it via the GitHub API for whoever runs it as a repository admin.
Nothing in the checkout verifies that it was actually applied to the live repository —
that is visible only via `gh api repos/{owner}/{repo}/rulesets`, never from a git
checkout. "Use this template" does not copy rulesets, so every repository created from
this template still needs its own admin to run `just ruleset` once.

**This repository ships no Claude Code permission list.** There is no committed
`.claude/settings.json`: which commands run without a prompt is each person's own
choice, in their user-level `~/.claude/settings.json` or the gitignored
`.claude/settings.local.json`, and that choice shapes where a human is consulted rather
than what is possible. The same file is where to register `scripts/format-edited-file.sh`
as a `PostToolUse` hook on `Edit|Write|MultiEdit`
(`cd "$CLAUDE_PROJECT_DIR" && mise exec -- scripts/format-edited-file.sh`), which runs
`swiftformat` on the one `.swift` file an edit touched and reports a failure back to the
agent (exit 2) — a convenience on that host, not a gate. Codex CLI, another agent, and a
human at a shell are bound by the instructions in this file and by the gates above.

**No gate runs the app on a device, or on any iOS release but the one the pinned Xcode
ships: CI's simulators run the Xcode-pinned runtime only.**

## Review Checklist

Before submitting a PR:

1. `just check` passes, and `just uitest` when the change is visible in the running app
2. New public APIs have `///` doc comments explaining *why*
3. Tests cover the new functionality (happy path AND error path)
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
