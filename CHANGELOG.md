# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The list refreshes quietly when a window comes back from the background, so changes
  made while the app was away show up. Each window keeps a `SceneLifecycleModel`
  (`AppModel.makeSceneLifecycleModel()`) and forwards its `scenePhase` to it as a
  `LifecyclePhase`, recorded synchronously so phases apply in order. A window's first
  active and every active after a trip through the background ask for
  `TodoListViewModel.refresh()`; dismissing Control Center or a system alert
  (inactive → active) does not. A refresh fetches only when the list has already loaded
  and no other refresh is in flight, so a launch loads once and several windows
  returning together fetch once; it shows no progress, and a failed refresh keeps the
  items and shows no alert. Lifecycle decisions log under the new `lifecycle` category.
- A per-configuration API base URL: `API_BASE_URL` in `Config/Debug.xcconfig` and a new
  `Config/Release.xcconfig` (placeholder `.invalid` hosts, the `//` written `/$()/`),
  expanded into `Info.plist` under `APIBaseURL` and parsed by Core's `AppConfiguration`,
  which throws `missing` or `malformed`. `App/` reads it once at launch, stops on a
  broken value, and builds the `APIClient` over `URLSessionHTTPClient` at that URL; no
  feature calls it yet. Release no longer builds without an xcconfig, and never
  includes `Config/Local.xcconfig`.
- `SchemaMigrationTests` pins every shipped schema version's stored shape — entities,
  uniqueness constraints, and each attribute's and relationship's stored properties as
  `Schema(versionedSchema:)` exposes them — against a hand-written literal, so editing
  `AppSchemaV1` in place, or removing it or changing its version identifier, fails
  `just test` with the instruction to add a new version and a migration stage instead. It also asserts that `AppMigrationPlan` lists its versions oldest first,
  that each stage joins one version to the next, and that `PersistenceStore` opens the
  plan's last schema. `StoreFiles` in `MyAppPlatformTests` writes a store with a given
  schema version to a temporary file and reopens it through the production container:
  the harness the first `AppSchemaV2`'s migration test is written in.
- `RetryingAPIClient`, a Core service over `APIClient` that sends a failed call again:
  only a timeout, no connection, a 500, 502, 503, or 504, or a 429; after a jittered
  exponential backoff, or exactly the 429's `Retry-After` (a wait longer than the cap is
  not retried at all); never a `POST` or `PATCH` unless its
  `Endpoint` is declared `isSafeToRepeat`; and never after cancellation, which ends a
  backoff wait at once. Its numbers are `Tuning.default.retry`, a `RetryPolicy` — the
  first tunables in Core's one `Tuning` type. It waits on an injected
  `any Clock<Duration>` and draws jitter from an injected generator, so the
  `RetryPolicy` suites cover every wait with `ManualClock` and the seeded `SplitMix64`
  (both new in `MyAppTestSupport`) and no real sleeping.
- A `SecureStoring` port for secrets, with a Keychain adapter (`KeychainSecureStore`: a
  generic-password item per `SecureKeys` constant, the bundle identifier as its service,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no entitlement), the
  `InMemorySecureStore` fake, and `SecureStoringContract`. The contract runs against the
  fake under `just test`; no gate runs it against the Keychain, which refuses a test
  runner on the host and on the Simulator, so the adapter is verified in the running
  app. `MyAppCore` may no longer import `Security` or call `SecItemAdd`,
  `SecItemCopyMatching`, `SecItemUpdate`, or `SecItemDelete`.

### Changed

- The repository no longer depends on the owner's user-level skills. `designing-ui`
  researches the design lock from the HIG and Apple's own apps
  (`references/research-workflow.md`, formerly `refero-workflow.md`) instead of
  `/refero-design` and the Refero MCP tools, and `AGENTS.md` and `shipping-issues` no
  longer name the skill that generates `.claude/agents/`.
- CI now runs one macOS job: `Test & Coverage Gate` runs the coverage floor and then
  `just build`. The `App Build & UI Test (iOS Simulator)`, `Release Smoke Launch (iOS
  Simulator)`, and `Package Tests (iOS Simulator)` jobs and their required contexts are
  removed; the UI test, smoke launch, and iOS package tests run in local `just check`
  only. A push to `main`, a draft pull request, and a pull request with no
  simulator-relevant change skip the macOS work on an Ubuntu runner (as does
  `Template Bootstrap Smoke`); marking a draft ready for review starts a fresh run.
- `just check` now also runs `uitest-build`, `uitest-run`, `smoke`, and `test-ios` when
  the change since `origin/main` touches a simulator path (`CHECK_ALL=1` forces them),
  and no longer runs `build`, which `uitest-build` covers. The path list moves out of
  `ci.yml` into `scripts/simulator-relevant.sh`, which CI's `changes` job and `just
  check` both call. Every xcodebuild and simulator recipe now runs through
  `scripts/run-throttled.sh --lock`: one at a time across every worktree on the Mac, at
  `utility` QoS with half the cores (`CHECK_JOBS`, `CHECK_QOS`), and at full speed,
  unlocked, under CI.
- Codex CLI is no longer supported: skills live only under `.claude/skills/` and are
  edited there directly. The `.agents/skills/` tree, its byte-identical mirror, `just
  agents-sync`/`just agents-check`, `scripts/sync-agents.sh`, the pre-commit hook's
  "Skills mirror" section, and the Codex-YAML frontmatter rule are removed; `typos` and
  `shellcheck` now cover `.claude/skills/`. The `steering-the-roadmap`, `updating-docs`,
  and `authoring-skills` skills and `docs/architecture/roadmap.md` are removed.
- Coding conventions now live in path-scoped rules that load with the files they govern:
  new `.claude/rules/core.md`, `ui.md`, `platform.md`, and `shell.md` replace the
  `designing-errors`, `tdd`, `localizing-the-app`, `building-swiftui-screens`, and
  `writing-repo-scripts` skills, and `swift.md` and `testing.md` keep only what applies
  to every module. `designing-core-logic` keeps only design judgment on Core: why the
  layers are split, view-model ownership and reentrancy, the composition root, and what
  each build does with the String Catalog. `designing-ui` now covers only
  the design lock, token values, Liquid Glass, Refero research, and why navigation is
  shaped as it is. `AGENTS.md` drops
  its Skills table (and `scripts/checks/skills-index-complete.sh` with it), its
  "Repository scripts", "Enforcement layers", and "What no local gate sees" sections
  (now the `changing-gates` skill's `references/enforcement-layers.md`), and "GitHub
  settings a new repository must enable" (now the `starting-an-app` skill).
- How the app is built and why now lives only in the skill that owns each subject, plus
  `AGENTS.md`'s Architecture section: `docs/architecture.md`, the
  `docs/architecture/roadmap.md` skeleton, the `steering-the-roadmap` skill, and
  README's Design Philosophy are removed. A new `persisting-data` skill owns the
  repository port, the SwiftData store and its schema versions, and preferences; view
  models and the composition root, the HTTP client, and navigation and the design lock
  move into references of `designing-core-logic`, `integrating-system-apis`, and
  `designing-ui`; "What is contract and what is
  private" moves into `AGENTS.md`. The app's direction is the `## Product` section and
  the open issues, and "what is next?" is answered by `triaging-issues`.
- The design is now kept as its present state instead of numbered decision records:
  the record index and template under `docs/architecture/`, and the skill that wrote
  them, are removed. A design change rewrites
  `AGENTS.md`'s Architecture and Product sections, `docs/architecture.md`, and the owning
  skill in place; the design lock is the "Design lock" section of
  `docs/design-system.md`; and the `## Product` section's fourth entry is now "Why it is
  shaped this way". The roadmap stays.
- SwiftData now runs on one app-wide store: a new `MyAppPlatform` `PersistenceStore`
  opens the only `ModelContainer` (`makeContainer(storage:)`) from the app-wide schema
  and migration plan, renamed `AppSchemaV1` and `AppMigrationPlan` (the stored entity,
  attributes, and version identifier are unchanged, so an existing store opens as it
  was), and `App/` hands that one container to every repository's
  `init(modelContainer:)`. `SwiftDataTodoRepository.make(storage:)` and
  `SwiftDataTodoRepository.Storage` are removed; `PersistenceStore.Storage` adds
  `.file(URL)` for tests that reopen a store file (#69)

- The navigation root moved out of `TodoListView` into a new `MyAppUI` `RootView`, which
  owns the app's one `NavigationStack(path:)` and its `navigationDestination` switch;
  `TodoListView(model:)` is now a plain screen. `App/` builds a new Core `AppModel` from
  the ports, which holds the shared `TodoListViewModel` (`todoList`) and builds a pushed
  screen's own view model by a factory per route — the detail screen now runs on
  `TodoDetailViewModel` from `makeTodoDetailViewModel(id:)` (#68)

- The deployment floor is iOS 27 (`project.yml`) with `.iOS(.v27)` and `.macOS(.v27)`
  in `Package.swift` (now `swift-tools-version: 6.4`), and the pinned Xcode is 27.0
  (`.xcode-version`); CI's macOS jobs run on the `xcode-27` runner image, since
  `macos-26` ships no Xcode 27

- `just run` opens Device Hub instead of Simulator.app, which Xcode 27 no longer ships,
  and still installs and launches the build when Device Hub cannot be opened (#64)

- `just uitest` is now `just uitest-build` (`xcodebuild build-for-testing`) followed by
  `just uitest-run` (`test-without-building`), and CI's `app` job runs the two halves
  instead of `just build` plus `just uitest`, so it compiles the Debug app once

- CI's Release smoke launch (`just smoke`) moved out of the `app` job into its own
  `smoke` job, `Release Smoke Launch (iOS Simulator)`, which runs in parallel with `app`
  and is a new required status check in `.github/rulesets/main.json` (re-run
  `just ruleset` to apply it)

- CI's simulator jobs (`app`, `smoke`, `ios-tests`) still report under their required
  names on every pull request but skip their steps when a new `changes` job finds no
  simulator-relevant path in the diff (a Markdown-only change, say); pushes to `main`
  and a failed detection run them in full

- The committed `.claude/settings.json` is removed: Claude Code permissions and the
  format-on-edit hook now live in each person's user-level or gitignored
  `.claude/settings.local.json` settings (see `AGENTS.md`)

### Added

- `LaunchTests` now runs Xcode's accessibility audit (`performAccessibilityAudit`) on the
  empty list, the list with an item, the detail screen, its not-found state, and the All
  Done state, through `auditAccessibility(of:)` in `LaunchUITests/Support/`, with light
  appearance and the default text size pinned. Its issue handler accepts only three
  named exceptions, each matched on the audit type and one element: contrast on the
  disabled `addButton`, contrast on the detail screen's created date (`LabeledContent`'s
  secondary value, given the `createdDate` identifier), and Dynamic Type clipping on the
  single-line `newItemField`. `.claude/rules/ui.md` says what the audit covers and what
  still needs a manual check.
- `LaunchTests` now opens a `my-app://todo/<uuid>` link to the item its walk created
  and asserts the detail screen shows it, then a link to an unknown item and asserts
  the not-found state, so removing `App/`'s `.onOpenURL` fails `just uitest`. The
  helpers and timeouts every UI test file shares (`focus`, `waitForDisappearance`,
  `Timeout`) move to `LaunchUITests/Support/` (#80)

- A typed JSON API layer in `MyAppCore/Networking`, over the `HTTPClient` port: an
  `Endpoint<Response>` describes one call, `APIClient` sends it below a base URL with
  coders configured once (ISO 8601 dates, keys as the type spells them) and returns the
  decoded 2xx body, and a closed `APIError` names every other outcome — `offline`,
  `timedOut`, `unauthorized`, `forbidden`, `notFound`, `rateLimited(retryAfter:)` (read
  from `Retry-After` as delta-seconds or an HTTP-date), `server(status:)`,
  `unexpectedStatus(_:)`, `decoding`, `encoding`, `transport`, and `cancelled`.
  `docs/architecture.md` gains "A worked API service"; `App/` does not wire a client yet
  (#70)

- README design rationale, CONTRIBUTING.md, and docs/getting-started.md (including how to
  remove the example code)
- Initial template: an iOS 18 SwiftUI app generated by XcodeGen, with all code in the
  local `MyAppKit` package (`MyAppCore`, `MyAppUI`, `MyAppPlatform`). A worked to-do
  list example covers MVVM with `@Observable` view models, a `TodoRepository` port with
  a SwiftData adapter (`@ModelActor`, versioned schema), an in-memory fake and a
  contract suite run against both, and an XCUITest on the iOS Simulator.
- Quality gates from day one: Swift 6 language mode with warnings as errors, SwiftLint
  strict, SwiftFormat, an 80% line / 75% function coverage floor on `MyAppCore`, a
  pre-commit hook, and CI (lint, host tests with coverage, simulator build and UI test).
- Agent harness: `AGENTS.md`, `docs/architecture.md`, `.claude/settings.json`, three
  sub-agent tiers, and the `shipping-issues`, `triaging-issues`, `tdd`, `create-pr`,
  and `smart-commit` skills, mirrored from `.agents/skills/` into `.claude/skills/`.
- Plain-bash tests for every script under `scripts/`, run with the skills' Python suites
  by `just test-scripts`
- Pre-commit staged guard for secret-shaped paths and content, and `just verify-hooks`
- Path-scoped Claude Code rules under `.claude/rules/`, and a PostToolUse hook that formats
  the edited Swift file
- Harness self-checks (`just check-harness`)
- Skills for repository scripts, gate changes, and skill authoring
- Label sync, PR title check, PR auto-labeling, release-note categories, and the `main`
  ruleset as code (`just labels`, `just ruleset`)
- Skills for errors, Core logic, ADRs, the roadmap, and documentation, and the empty ADR
  tree under `docs/architecture/`
- CodeQL, gitleaks, OSV, dependency review, Scorecard, and zizmor workflows; SECURITY.md
  and CODE_OF_CONDUCT.md
- Dependabot (SwiftPM, GitHub Actions) and Renovate (mise.toml, gitleaks) with a 7-day
  cooldown, kept in agreement by `scripts/checks/dependency-bots-agree.sh`, and the
  `merging-dependency-prs` skill
- `scripts/bootstrap.sh` renames the template into an app, checked by CI's Template
  Bootstrap Smoke job
- `just test-ios` (package tests on the iOS Simulator) and `just smoke` (Release launch on
  a simulator), both in CI
- iOS skills for running the app on the Simulator, integrating system APIs, and building
  SwiftUI screens; `just reset-permissions`
- `DesignTokens` and the iOS `designing-ui` skill, with the template's design research in
  `docs/design-system.md`
- `LocalizationTests` keep Core's `LocalizedStringResource` keys and the String Catalog in
  step, and the `localizing-the-app` skill
- An `HTTPClient` port with a `URLSession` adapter, a fake, and a contract run against
  both
- A `PreferencesStoring` port with a `UserDefaults` adapter, and the Hide Completed toggle
- Typed navigation (`AppRoute`, `NavigationModel`), a to-do detail screen, and
  `my-app://todo/<id>` deep links
- An Edit button on the to-do list, so an item can be deleted without the swipe
- `just run-device` installs and launches the app on a connected iPhone, with the
  development team kept in a gitignored `Config/Local.xcconfig` (`docs/running-on-device.md`)

### Fixed

- Skill descriptions name the Core and Platform layers without the app prefix, so
  renaming the app no longer lengthens them: after a rename to a 19-character name
  `persisting-data`'s was 1,046 characters, past the 1,024-character limit
  `just check-harness` enforces. `scripts/checks/skills-descriptions.sh` now refuses a
  description that names any placeholder `scripts/bootstrap.sh` rewrites
  (`ERR_CHECK_SKILL_PLACEHOLDER`), and CI's `Template Bootstrap Smoke` also runs it on
  the renamed tree.
- CI's `lint` job runs on `ubuntu-24.04` instead of `ubuntu-latest`, so SwiftLint
  starts again: `ubuntu-latest` moved to Ubuntu 26.04, whose image ships only
  `libxml2.so.16`, while the SwiftLint Linux binary mise installs needs
  `libxml2.so.2` and failed to load. `swiftlint --strict` still runs on every pull
  request.

- `TodoListViewModel.load()` is safe to call while another load is in flight: the
  newest load wins and an older one that returns later drops its result, an add,
  toggle, or delete that finishes during a load is kept rather than overwritten by the
  load's stale answer, and a cancelled load (a `.task` cancelled as its screen leaves)
  reports no failure and puts `phase` back to what it was, so the next appearance loads
  again. The test fake `InMemoryTodoRepository` gains an `onFetch(_:)` hook (#72)

- A failure on a pushed screen now presents there: a toggle that could not be saved on
  the detail screen showed no alert until the user went back to the list. The failure
  alert is now one shared `MyAppUI` modifier, `.failureAlert(_:dismiss:)`, applied once
  in `RootView` outside the `NavigationStack`, over a new Core `PresentableFailure`
  protocol (`title` and `message`) that `TodoListFailure` adopts; `TodoListView` no
  longer declares an alert. `TodoListStrings.dismiss` moved to
  `FailureStrings.dismiss` (catalog key `failure.dismiss`). Debug builds accept a
  `-failUpdates` launch argument that fails every toggle, which `LaunchTests` uses to
  prove the alert shows over the detail screen (#78)

- `LaunchTests` no longer fails intermittently on CI: it waits for `newItemField` to
  take keyboard focus before typing, and `just uitest` boots the simulator and waits
  for it before `xcodebuild` launches the app, so a cold boot no longer times out the
  launch
