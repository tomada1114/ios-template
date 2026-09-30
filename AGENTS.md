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
answer to "is this in scope?".

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
just build         # Build the app (Debug) for the iOS Simulator
just run           # Build, then install and launch it on an iOS Simulator (SIMULATOR_DEVICE picks one)
just logs          # Stream this app's log output from the booted simulator (Ctrl-C to stop)
just uitest        # Run the XCUITest launch test on an iOS Simulator
just check         # Run all checks: verify-hooks → fmt → lint → test-scripts → test → build
just agents-sync   # Regenerate the .claude/skills/ mirror from .agents/skills/
just agents-check  # Fail if .claude/skills/ differs from .agents/skills/
just clean         # Remove build artifacts and the generated project
```

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
| Formatting or style of any Swift file | `just lint` (`just fix` for what is auto-fixable) |
| One Core suite, while iterating | `just test-fast <filter>` — no coverage floor, so finish with `just test` |
| `Localizable.xcstrings`, or a `LocalizedStringResource` in Core | `just test`; `just build` to compile the catalog into the app |
| `project.yml` | `just generate && just build` |
| A test under `LaunchUITests/`, or launch behavior | `just uitest` |
| Behavior only the running app shows | `just run`, then `just logs` — no gate asserts it, so the PR carries the evidence (a screenshot: `xcrun simctl io booted screenshot shot.png`) |
| A shell script under `scripts/` (including the sourced `scripts/guard/*.sh`), or `.githooks/pre-commit` | `just lint`, then `just test-scripts` |
| `scripts/verify-hooks.sh` | `just lint`, then `just test-scripts`; `just verify-hooks` for the check itself |
| A skill under `.agents/skills/` | `just agents-sync`, then `just agents-check`; `just test-scripts` when the skill ships scripts (it runs their `scripts/tests/` unittest suite) |
| A workflow under `.github/workflows/` | `just lint` (actionlint) |
| Markdown | `just lint` (its `typos` spell-check) |
| `mise.toml` | `mise install`, then `just check` |

## Architecture

```
App/                        # Thin shell: @main entry point + resources, NO logic.
                            #   The composition root: opens the SwiftData adapter and
                            #   hands it to Core view models
Packages/MyAppKit/
├── Sources/MyAppCore/      # Domain values, view models, ports (protocols), wording,
│                           #   logging — no UI, persistence, or OS-integration import
│                           #   (enforced by lint and test); coverage-gated
├── Sources/MyAppUI/        # SwiftUI views — thin, render Core view models
├── Sources/MyAppPlatform/  # Adapters behind Core ports (SwiftData today) — translation
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
  The worked example is `TodoRepository` / `SwiftDataTodoRepository`.
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

A change to any of these is a decision a human makes, recorded as an ADR once the ADR
tree (`docs/architecture/`) is ported — until then, in the pull request description:

- a new target (`project.yml`, `Package.swift`) or a new Core port;
- persistence — a new store, a schema version, CloudKit sync;
- a new dependency;
- a capability or entitlement (push, iCloud, App Groups, HealthKit, …) or a permission
  prompt (notifications, location, photos, camera, tracking);
- distribution — TestFlight, the App Store, signing;
- `deploymentTarget` in `project.yml`, with `platforms:` in `Package.swift`;
- a shipped language beyond English.

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

More skills are ported from the macOS template by open issues (see
[Harness status](#harness-status)).

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

`.claude/agents/` defines three named sub-agent tiers a skill or session hands a step to
by name (`subagent_type: executor`), each pinned to a model alias and an effort level:
`executor` (settled spec, clear pass/fail), `architect` (design judgment, review,
complex multi-file work), `worker` (single-shot, tool-free writing or checking). Codex
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
- Editing `.claude/settings.local.json` or a user-level settings file: an agent adding an
  `allow` rule there widens its own permissions unreviewed. The committed
  `.claude/settings.json` is reviewed in its pull request like any other file.
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
  a merge.

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

## Repository scripts

Every script under `scripts/` follows these rules, whoever writes it
(`scripts/tests/lib.sh` and the `scripts/guard/*.sh` libraries are sourced, so they
carry no shebang or `set` line of their own):

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
  (`guard-paths_test.sh`, `guard-credentials_test.sh`). Known exception: `coverage.sh`, whose test file
  `scripts/tests/coverage_test.sh` is partial — it stubs `swift` to cover its rejection
  of the removed environment override and its line- and function-floor comparisons,
  but not a real coverage run, which is CI's `test` job. `coverage.sh`'s
  below-the-line-floor failure also predates the failure contract and does not follow
  it yet (its function-floor failure, `ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR`, does).

## Harness status

This repository is being brought up to the macOS template's harness
(`tomada1114/macos-app-template`) one issue at a time; the tracking issue, #1, lists them
in order. What exists today is what the tables above describe. Not yet ported, each owned by
an open issue: the harness self-checks (`scripts/checks/`, `just check-harness`), the
remaining skills and the ADR tree, labels and the branch ruleset as code, PR hygiene
and security workflows, dependency bots, `scripts/bootstrap.sh`, the localization
harness, the iOS design system, distribution, and the fuller documentation. When an issue
lands one of these, it updates this section and the tables above in the same pull
request.

## Enforcement layers

| Layer | Fires on | Holds |
|---|---|---|
| `.githooks/pre-commit` (installed by `just install`) | `git commit` | `scripts/lint.sh --staged-tree` on the staged Swift files; the skills-mirror check when a staged path is under `.agents/skills/` or `.claude/skills/`; the staged guard (`scripts/check-staged.sh`, rules in `scripts/guard/`) on every commit that stages a change — no secret-shaped path or credential-shaped content lands in a commit, and a staged deletion is never inspected |
| `scripts/verify-hooks.sh` (`just install`'s last step, and `just check`'s first) | `just install`, `just check` | git resolves the hooks directory to `.githooks/` and `.githooks/pre-commit` is executable — skips under CI or the `ALLOW_MISSING_GIT_HOOKS` opt-out |
| `.swiftlint.yml`'s `no_ui_import_in_core` + `ArchitectureBoundaryTests` | the hook, `just lint`, CI `lint`; `just test`, CI `test` | Core's import ban; UI and Platform never import each other; no shipped module imports `MyAppTestSupport` |
| `.swiftlint.yml`'s `no_print_in_sources` | the hook, `just lint`, CI `lint` | no `print`/`debugPrint`/`NSLog` in shipped code |
| `scripts/coverage.sh` | `just test`, CI `test` | 80% line / 75% function coverage on `MyAppCore` |
| `AppLogTests` | `just test`, CI `test` | `AppLog.subsystem` equals the bundle identifier in `project.yml` |
| `.claude/settings.json` | every tool call Claude Code makes here | the routine local loop runs without a prompt; `--no-verify`, force pushes, and entitlement edits are denied. A prompt policy for Claude Code only, not a boundary. `hooks` holds one `PostToolUse` hook, `scripts/format-edited-file.sh`, that runs `swiftformat` on the one `.swift` file an `Edit`/`Write`/`MultiEdit` touched and reports a failure back to the agent (exit 2) — a convenience on this host only; the git hook is the gate |
| CI (`.github/workflows/ci.yml`) | push to `main`, every pull request | `lint` (format, lint, shellcheck, actionlint, typos, skills mirror; `scripts/tests/run.sh` — the script tests and the skills' Python suites), `test` (package tests + coverage floor), `app` (iOS Simulator build + XCUITest) |

`git commit --no-verify` bypasses the hook, and a clone where `just install` never ran
has no hook at all (`scripts/verify-hooks.sh` makes that fail loudly at `just install`
and `just check` time, but a contributor who runs neither still commits without hooks).
CI is the backstop for everything except the staged guard, which no CI job re-runs over
a pull request's diff: a secret committed with `--no-verify` or from a clone without
`just install` reaches the branch unchecked (#10 adds the history scan).

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
